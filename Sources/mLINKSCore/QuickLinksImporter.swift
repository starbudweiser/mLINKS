import Foundation
import SQLite3

public enum ImportError: Error, Equatable {
    case databaseNotFound
    case databaseUnreadable
    case notQuickLinksCSV
}

/// Lit les liens de QuickLinks (Appyogi), depuis sa base ou un export .CSV. N'écrit jamais dans ces fichiers.
public enum QuickLinksImporter {
    public static var defaultDatabase: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.appyogi.quicklinks/Data/Library/Application Support/com.appyogi.quicklinks/qlmigrated.sqlite")
    }

    private static let fallbackGroup = "QuickLinks"

    private struct Row {
        var groupName: String
        var groupOrder: Int
        var order: Int
        var name: String
        var url: String
        var key: String
        var mask: UInt
        var shown: Bool
    }

    public static func read(_ url: URL) throws -> [LinkGroup] {
        url.pathExtension.lowercased() == "csv" ? try readCSV(url) : try readDatabase(url)
    }

    // MARK: Base SQLite

    public static func readDatabase(_ url: URL) throws -> [LinkGroup] {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ImportError.databaseNotFound }
        var db: OpaquePointer?
        // immutable=1 : aucun verrou ni fichier annexe, QuickLinks peut rester ouvert.
        let uri = url.absoluteString + "?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw ImportError.databaseUnreadable
        }
        defer { sqlite3_close(db) }

        let groups = try query(db, "SELECT ql_grp_id, ql_grp_name, ql_grp_idx FROM ql_grps_tbl")
        var names: [String: (name: String, order: Int)] = [:]
        for g in groups { names[g[0]] = (g[1], Int(g[2]) ?? 0) }

        let links = try query(db, "SELECT ql_grp_id, ql_idx, ql_name, ql_url, ql_key, ql_mask, ql_show FROM ql_links_tbl")
        let rows = links.map { l in
            // Un identifiant de groupe inconnu ne fait pas perdre le lien.
            let group = names[l[0]] ?? (fallbackGroup, Int.max)
            return Row(groupName: group.name, groupOrder: group.order, order: Int(l[1]) ?? 0, name: l[2], url: l[3],
                       key: l[4], mask: UInt(l[5]) ?? 0, shown: l[6] != "0")
        }
        return assemble(rows)
    }

    private static func query(_ db: OpaquePointer?, _ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ImportError.databaseUnreadable }
        defer { sqlite3_finalize(statement) }
        var rows: [[String]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { throw ImportError.databaseUnreadable }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            })
        }
    }

    // MARK: Export .CSV

    public static func readCSV(_ url: URL) throws -> [LinkGroup] {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.notQuickLinksCSV }
        let text = String(decoding: data, as: UTF8.self)
        let table = parseCSV(text)
        guard let header = table.first else { throw ImportError.notQuickLinksCSV }
        let columns = Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        guard let group = columns["Group Name"], let name = columns["QL_Name"], let link = columns["QL_URL"] else {
            throw ImportError.notQuickLinksCSV
        }
        func cell(_ row: [String], _ column: String) -> String {
            guard let i = columns[column], i < row.count else { return "" }
            return row[i]
        }
        let rows = table.dropFirst().compactMap { row -> Row? in
            guard row.count > max(group, name, link) else { return nil }
            return Row(groupName: row[group], groupOrder: Int(cell(row, "GroupIndex")) ?? 0,
                       order: Int(cell(row, "QL_ID")) ?? 0, name: row[name], url: row[link],
                       key: cell(row, "QL_Key"), mask: UInt(cell(row, "QL_Mask")) ?? 0,
                       shown: cell(row, "QL_Show") != "0")
        }
        return assemble(rows)
    }

    /// Lecteur CSV : champs entre guillemets, guillemets doublés, fins de ligne Unix ou Windows.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text)[...]
        if chars.first == "\u{FEFF}" { chars = chars.dropFirst() }
        func endRow() {
            row.append(field)
            field = ""
            if row != [""] { rows.append(row) }
            row = []
        }
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars = chars.dropFirst() } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                endRow()
            } else {
                field.append(c)
            }
        }
        endRow()
        return rows
    }

    // MARK: Conversion

    private static func assemble(_ rows: [Row]) -> [LinkGroup] {
        let sorted = rows.enumerated().sorted {
            ($0.element.groupOrder, $0.element.order, $0.offset) < ($1.element.groupOrder, $1.element.order, $1.offset)
        }.map(\.element)
        var groups: [LinkGroup] = []
        for row in sorted {
            let target = LinkItem.normalizedTarget(row.url)
            guard !target.isEmpty else { continue }
            var hotkey: Hotkey?
            if let code = Int(row.key), row.mask != 0 { hotkey = Hotkey(keyCode: code, modifiers: row.mask) }
            let name = row.name.isEmpty ? LinkItem.defaultName(for: target) : row.name
            let link = LinkItem(name: name, target: target, visible: row.shown, hotkey: hotkey)
            let groupName = row.groupName.isEmpty ? fallbackGroup : row.groupName
            if let i = groups.firstIndex(where: { $0.name == groupName }) {
                groups[i].links.append(link)
            } else {
                groups.append(LinkGroup(name: groupName, links: [link]))
            }
        }
        return groups
    }
}
