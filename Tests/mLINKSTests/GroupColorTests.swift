import Foundation
import Testing
@testable import mLINKSCore

@Suite struct GroupColorTests {
    @Test func paletteIsValid() {
        for hex in GroupColor.palette { #expect(GroupColor.isValid(hex), "\(hex)") }
        #expect(Set(GroupColor.palette).count == GroupColor.palette.count)
    }

    @Test func componentsAndInvalidValues() throws {
        let c = try #require(GroupColor.components("#FBBF24"))
        #expect(abs(c.red - 251.0 / 255) < 0.001 && abs(c.green - 191.0 / 255) < 0.001 && abs(c.blue - 36.0 / 255) < 0.001)
        for bad in ["", "FBBF24", "#FBBF2", "#GGGGGG", "#FBBF24FF", "red"] {
            #expect(GroupColor.components(bad) == nil, "\(bad)")
        }
    }

    @Test func oldLibraryFilesWithoutColorStillLoad() throws {
        let old = #"{"version":1,"groups":[{"id":"6903F13A-0000-4000-8000-000000000001","name":"ADOBE","links":[]}]}"#
        let library = try JSONDecoder().decode(Library.self, from: Data(old.utf8))
        #expect(library.groups.first?.name == "ADOBE")
        #expect(library.groups.first?.color == nil)
    }

    @Test func colorSurvivesSaveAndLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = LibraryFile(url: directory.appendingPathComponent("links.json"))
        try file.save(Library(groups: [LinkGroup(name: "ADOBE", color: "#F97316"), LinkGroup(name: "SYSTEME")]))
        let back = file.load()
        #expect(back.groups.map(\.color) == ["#F97316", nil])
    }

    @Test func mergeKeepsAnExistingGroupColor() {
        var library = Library(groups: [LinkGroup(name: "ADOBE", color: "#34D399")])
        library.merge([LinkGroup(name: "adobe", links: [LinkItem(name: "X", target: "/x")])])
        #expect(library.groups.count == 1)
        #expect(library.groups[0].color == "#34D399")
    }
}
