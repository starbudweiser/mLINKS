import Foundation

/// Numéro de version « 1.2.3 » (un « v » initial est ignoré), comparable composante par composante.
public struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }
        let numbers = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

public struct ReleaseInfo: Equatable, Sendable {
    public var version: AppVersion
    public var downloadURL: URL
    public var notes: String
}

public enum UpdateError: Error, Equatable {
    case noRelease
    case invalidFeed
}

public enum UpdateFeed {
    public static let assetName = "mLINKS.zip"
    public static let defaultURL = URL(string: "https://api.github.com/repos/starbudweiser/mLINKS/releases/latest")!

    private struct Release: Decodable {
        struct Asset: Decodable { var name: String; var browser_download_url: String }
        var tag_name: String
        var body: String?
        var draft: Bool?
        var prerelease: Bool?
        var assets: [Asset]
    }

    /// Lit la réponse de l'API GitHub « dernière release » : version du tag et lien du zip de l'appli.
    public static func parse(_ data: Data) throws -> ReleaseInfo {
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { throw UpdateError.invalidFeed }
        guard release.draft != true, release.prerelease != true else { throw UpdateError.noRelease }
        guard let version = AppVersion(release.tag_name) else { throw UpdateError.invalidFeed }
        guard let asset = release.assets.first(where: { $0.name == assetName }),
              let url = URL(string: asset.browser_download_url) else { throw UpdateError.noRelease }
        return ReleaseInfo(version: version, downloadURL: url, notes: release.body ?? "")
    }
}
