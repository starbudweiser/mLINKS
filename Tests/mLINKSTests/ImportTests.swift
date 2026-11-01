import Foundation
import SQLite3
import Testing
@testable import mLINKSCore

private func temporaryFile(_ name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(name)
}

/// Base au schéma de QuickLinks 3.6, dans un dossier dont le nom contient une espace comme le vrai.
private func makeDatabase() throws -> URL {
    let url = try temporaryFile("ql migrated.sqlite")
    var db: OpaquePointer?
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let sql = """
    CREATE TABLE ql_links_tbl (ql_uid VARCHAR PRIMARY KEY NOT NULL UNIQUE, ql_name VARCHAR, ql_grp_id INTEGER,
      ql_type INTEGER, ql_url VARCHAR, ql_key VARCHAR, ql_mask INTEGER, ql_show BOOL, ql_idx INTEGER);
    CREATE TABLE ql_grps_tbl (ql_grp_id VARCHAR PRIMARY KEY NOT NULL UNIQUE, ql_grp_name VARCHAR, ql_grp_clr VARCHAR, ql_grp_idx INTEGER);
    INSERT INTO ql_grps_tbl VALUES ('b', 'SYSTEME', '', 1), ('a', 'ADOBE', '', 0);
    INSERT INTO ql_links_tbl VALUES
      ('1', 'Scripts', 'a', 2, '/Applications/AE/Scripts', '', 0, 1, 5),
      ('2', 'CameraRaw', 'a', 2, '/Users/me/CameraRaw', '', 0, 1, 1),
      ('3', '.zshrc', 'b', 2, '/Users/me/.zshrc', '40', 1572864, 0, 0),
      ('4', 'Orphelin', 'zz', 2, '/Users/me/Orphelin', '', 0, 1, 0);
    """
    #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    return url
}

@Test func readsDatabaseInOrder() throws {
    let groups = try QuickLinksImporter.readDatabase(makeDatabase())
    #expect(groups.map(\.name) == ["ADOBE", "SYSTEME", "QuickLinks"])
    #expect(groups[0].links.map(\.name) == ["CameraRaw", "Scripts"])
    let zshrc = groups[1].links[0]
    #expect(zshrc.visible == false)
    #expect(zshrc.hotkey == Hotkey(keyCode: 40, modifiers: Hotkey.command | Hotkey.option))
    #expect(groups[2].links[0].target == "/Users/me/Orphelin")
}

@Test func missingDatabaseIsReported() {
    #expect(throws: ImportError.databaseNotFound) {
        try QuickLinksImporter.readDatabase(URL(fileURLWithPath: "/nulle/part.sqlite"))
    }
}

@Test func readsCSVExport() throws {
    let url = try temporaryFile("export.csv")
    let csv = [
        "GroupID,Group Name,GroupIndex,QL_ID,QL_Key,QL_Mask,QL_Name,QL_Show,QL_Type,QL_UID,QL_URL",
        #"2,SYSTEME,2,0,,0,".zshrc, le vrai",1,2,u1,/Users/me/.zshrc"#,
        "1,ADOBE,1,1,,0,LUTs,0,2,u2,/Library/LUTs",
        #"1,ADOBE,1,0,,0,"Dit ""RAW""",1,2,u3,file:///Users/me/Camera%20Raw/"#,
        "",
    ].joined(separator: "\r\n")
    try csv.write(to: url, atomically: true, encoding: .utf8)
    let groups = try QuickLinksImporter.read(url)
    #expect(groups.map(\.name) == ["ADOBE", "SYSTEME"])
    #expect(groups[0].links.map(\.name) == ["Dit \"RAW\"", "LUTs"])
    #expect(groups[0].links[0].target == "/Users/me/Camera Raw")
    #expect(groups[0].links[1].visible == false)
    #expect(groups[1].links[0].name == ".zshrc, le vrai")
}

@Test func foreignCSVIsRefused() throws {
    let url = try temporaryFile("autre.csv")
    try "a,b\n1,2\n".write(to: url, atomically: true, encoding: .utf8)
    #expect(throws: ImportError.notQuickLinksCSV) { try QuickLinksImporter.readCSV(url) }
}

@Test func mergeKeepsExistingAndSkipsDuplicates() {
    let hotkey = Hotkey(keyCode: 1, modifiers: Hotkey.command)
    var library = Library(groups: [LinkGroup(name: "Adobe", links: [LinkItem(name: "Mien", target: "/a", hotkey: hotkey)])])
    let report = library.merge([
        LinkGroup(name: "ADOBE", links: [LinkItem(name: "Doublon", target: "/a"), LinkItem(name: "B", target: "/b", hotkey: hotkey)]),
        LinkGroup(name: "Neuf", links: [LinkItem(name: "C", target: "/c")]),
        LinkGroup(name: "Vide"),
    ])
    #expect(library.groups.map(\.name) == ["Adobe", "Neuf"])
    #expect(library.groups[0].links.map(\.name) == ["Mien", "B"])
    #expect(library.groups[0].links[1].hotkey == nil)
    #expect(report.added == 2 && report.groupsCreated == 1 && report.alreadyPresent == 1 && report.hotkeysDropped == 1)
    // Réimporter ne duplique rien.
    #expect(library.merge([LinkGroup(name: "Neuf", links: [LinkItem(name: "C", target: "/c")])]).added == 0)
}

@Test func moveLinkAcrossGroups() {
    let a = LinkItem(name: "a", target: "/a"), b = LinkItem(name: "b", target: "/b"), c = LinkItem(name: "c", target: "/c")
    let one = LinkGroup(name: "1", links: [a, b]), two = LinkGroup(name: "2", links: [c])
    var library = Library(groups: [one, two])
    library.moveLink(b.id, to: one.id, before: a.id)
    #expect(library.groups[0].links.map(\.name) == ["b", "a"])
    library.moveLink(a.id, to: two.id, before: c.id)
    #expect(library.groups[1].links.map(\.name) == ["a", "c"])
    library.moveLink(c.id, to: one.id)
    #expect(library.groups[0].links.map(\.name) == ["b", "c"])
    library.moveLink(a.id, to: two.id, before: a.id) // sur lui-même : rien ne se perd
    #expect(library.allLinks.count == 3)
    library.moveGroup(two.id, before: one.id)
    #expect(library.groups.map(\.name) == ["2", "1"])
}

@Test func libraryFileRoundTripAndCorruption() throws {
    let url = try temporaryFile("links.json")
    let file = LibraryFile(url: url)
    let library = Library(groups: [LinkGroup(name: "G", links: [LinkItem(name: "n", target: "/t", hotkey: Hotkey(keyCode: 3, modifiers: Hotkey.option))])])
    try file.save(library)
    #expect(file.load() == library)
    try Data("pas du json".utf8).write(to: url)
    #expect(file.load() == Library())
    #expect(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("illisible.json").path))
}

@Test func targetsAndVolumes() {
    #expect(LinkItem.defaultName(for: "/Applications/Mail.app") == "Mail")
    #expect(LinkItem.defaultName(for: "https://example.com/x") == "example.com")
    #expect(LinkItem.isWeb("https://example.com") && !LinkItem.isWeb("file:///a") && !LinkItem.isWeb("/a"))
    #expect(Library.volumeRoot(of: "/Volumes/Disk/Tools/x") == "/Volumes/Disk")
    #expect(Library.volumeRoot(of: "/Users/me") == "/")
}

@Test func translationsShareTheSameKeysAndCoverTheCode() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func keys(_ language: String) throws -> Set<String> {
        let url = root.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        return Set(try #require(NSDictionary(contentsOf: url) as? [String: String]).keys)
    }
    let french = try keys("fr")
    for language in ["en", "es", "it"] { #expect(try keys(language) == french, "\(language)") }

    let sources = root.appendingPathComponent("Sources/mLINKS")
    let pattern = try NSRegularExpression(pattern: #"\bL\("([a-z.]+)""#)
    var used = Set<String>()
    for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) where name.hasSuffix(".swift") {
        let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            used.insert(String(text[Range(match.range(at: 1), in: text)!]))
        }
    }
    #expect(used.count > 30)
    #expect(used.subtracting(french).isEmpty, "\(used.subtracting(french))")
}

@Test func versionsCompareNumerically() {
    #expect(AppVersion("1.10")! > AppVersion("1.9")!)
    #expect(AppVersion("v2.0")! == AppVersion("2.0.0")!)
    #expect(AppVersion("1.0.1")! > AppVersion("1.0")!)
    #expect(AppVersion("abc") == nil && AppVersion("1..2") == nil)
}

@Test func feedParsing() throws {
    func feed(_ extra: String = "", asset: String = "mLINKS.zip") -> Data {
        Data(#"{"tag_name":"v1.2","body":"Notes",\#(extra)"assets":[{"name":"autre.dmg","browser_download_url":"https://x/a.dmg"},{"name":"\#(asset)","browser_download_url":"https://x/mLINKS.zip"}]}"#.utf8)
    }
    let release = try UpdateFeed.parse(feed())
    #expect(release.version == AppVersion("1.2") && release.downloadURL.absoluteString == "https://x/mLINKS.zip" && release.notes == "Notes")
    #expect(throws: UpdateError.noRelease) { try UpdateFeed.parse(feed(asset: "rien.zip")) }
    #expect(throws: UpdateError.noRelease) { try UpdateFeed.parse(feed(#""prerelease":true,"#)) }
    #expect(throws: UpdateError.invalidFeed) { try UpdateFeed.parse(Data("{}".utf8)) }
}
