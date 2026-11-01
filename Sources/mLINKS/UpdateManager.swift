import AppKit
import Security
import mLINKSCore

/// Mise à jour automatique : lit la dernière release GitHub, télécharge le zip notarisé, vérifie sa signature
/// (même identifiant, certificat Developer ID de l'auteur, notarisation) puis remplace l'appli et la relance.
@MainActor
final class UpdateManager: ObservableObject {
    enum State: Equatable {
        case idle, checking, installing
        case available(ReleaseInfo)
    }

    @Published private(set) var state: State = .idle

    /// Équipe Apple qui signe les versions publiées ; une release signée par une autre est refusée.
    static let teamID = "35KLMK53PN"
    private static let bundleID = "fr.stephan.mlinks"
    private static let autoKey = "autoUpdate"
    private static let lastCheckKey = "lastUpdateCheck"
    private var timer: Timer?

    var autoCheckEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true
    }

    /// Version en cours (variable `MLINKS_FAKE_VERSION` pour les essais). Nil hors d'un .app : pas de mise à jour.
    var currentVersion: AppVersion? {
        let text = ProcessInfo.processInfo.environment["MLINKS_FAKE_VERSION"]
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return text.flatMap(AppVersion.init)
    }

    private var feedURL: URL {
        ProcessInfo.processInfo.environment["MLINKS_UPDATE_URL"].flatMap(URL.init(string:)) ?? UpdateFeed.defaultURL
    }

    /// Vérification discrète au lancement puis toutes les 24 h : rien ne s'affiche, le menu propose la mise à jour.
    func startAutomaticChecks() {
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.automaticCheckIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            MainActor.assumeIsolated { self?.automaticCheckIfDue() }
        }
    }

    private func automaticCheckIfDue() {
        guard autoCheckEnabled, state == .idle else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        Task { _ = await check() }
    }

    /// Cherche une version plus récente ; renvoie nil si l'appli est à jour (ou si la lecture échoue : `error`).
    @discardableResult
    func check() async -> Result<ReleaseInfo?, Error> {
        guard let current = currentVersion else { return .success(nil) }
        if state == .installing { return .success(nil) }
        state = .checking
        defer { if state == .checking { state = .idle } }
        do {
            var request = URLRequest(url: feedURL, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 { throw UpdateError.noRelease }
            let release = try UpdateFeed.parse(data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            if release.version > current {
                state = .available(release)
                return .success(release)
            }
            return .success(nil)
        } catch UpdateError.noRelease {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            return .success(nil)
        } catch {
            return .failure(error)
        }
    }

    // MARK: Installation

    struct InstallFailure: Error { var key: String }

    /// Télécharge, vérifie et remplace. En cas de succès l'appli se ferme et sa nouvelle version se relance.
    func install(_ release: ReleaseInfo) async -> InstallFailure? {
        guard state != .installing else { return nil }
        state = .installing
        let destination = Bundle.main.bundleURL
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("mLINKS-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
                throw InstallFailure(key: "update.error.notwritable")
            }
            let (downloaded, _) = try await URLSession.shared.download(from: release.downloadURL)
            let zip = work.appendingPathComponent("mLINKS.zip")
            try FileManager.default.moveItem(at: downloaded, to: zip)
            let unpacked = work.appendingPathComponent("new")
            let app = unpacked.appendingPathComponent("mLINKS.app")
            let expected = release.version
            try await Task.detached {
                guard Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else {
                    throw InstallFailure(key: "update.error.download")
                }
                try Self.verify(app, expected: expected)
            }.value
            try Self.swap(app: app, into: destination, work: work)
            NSApp.terminate(nil)
            return nil
        } catch let failure as InstallFailure {
            state = .available(release)
            return failure
        } catch {
            state = .available(release)
            return InstallFailure(key: "update.error.download")
        }
    }

    /// Même identifiant, version attendue, signature Developer ID de l'auteur sans altération, notarisation valide.
    nonisolated private static func verify(_ app: URL, expected: AppVersion) throws {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == bundleID,
              let text = info?["CFBundleShortVersionString"] as? String, AppVersion(text) == expected else {
            throw InstallFailure(key: "update.error.verify")
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text2 = "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(teamID)\""
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text2 as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode), requirement) == errSecSuccess,
              run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path]) == 0 else {
            throw InstallFailure(key: "update.error.verify")
        }
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Un script détaché attend la fin de l'appli, remplace le paquet (avec retour arrière si la copie échoue) et le relance.
    private static func swap(app: URL, into destination: URL, work: URL) throws {
        let script = """
        #!/bin/sh
        PID="$1"; NEW="$2"; DEST="$3"; WORK="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST.new" "$DEST.old"
        if /usr/bin/ditto "$NEW" "$DEST.new" && mv "$DEST" "$DEST.old"; then
            if mv "$DEST.new" "$DEST"; then rm -rf "$DEST.old"; else mv "$DEST.old" "$DEST"; fi
        fi
        rm -rf "$DEST.new" "$WORK"
        /usr/bin/open -g "$DEST"
        """
        let file = work.appendingPathComponent("swap.sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [file.path, String(ProcessInfo.processInfo.processIdentifier), app.path, destination.path, work.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
