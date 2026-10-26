import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("ImagePaste")
struct ImagePasteTests {

    @Test("Cmd+V pastes the image only when there's no text to paste")
    func pastePrefersText() {
        #expect(ImagePaste.shouldPasteImage(trigger: .paste, hasText: false, hasImage: true))
        #expect(!ImagePaste.shouldPasteImage(trigger: .paste, hasText: true, hasImage: true))
        #expect(!ImagePaste.shouldPasteImage(trigger: .paste, hasText: true, hasImage: false))
        #expect(!ImagePaste.shouldPasteImage(trigger: .paste, hasText: false, hasImage: false))
    }

    @Test("Ctrl+V pastes the image whenever there is one, and passes through otherwise")
    func controlVPrefersImage() {
        #expect(ImagePaste.shouldPasteImage(trigger: .controlV, hasText: false, hasImage: true))
        #expect(ImagePaste.shouldPasteImage(trigger: .controlV, hasText: true, hasImage: true))
        #expect(!ImagePaste.shouldPasteImage(trigger: .controlV, hasText: true, hasImage: false))
        #expect(!ImagePaste.shouldPasteImage(trigger: .controlV, hasText: false, hasImage: false))
    }

    @Test("stored images get distinct png paths with no spaces, and purge removes them")
    func storeAndPurge() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-paste-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try ImagePaste.store(Data([1, 2, 3]), in: directory)
        let second = try ImagePaste.store(Data([4]), in: directory)

        #expect(first != second)
        #expect(first.pathExtension == "png")
        #expect(!first.lastPathComponent.contains(" "))
        #expect(try Data(contentsOf: first) == Data([1, 2, 3]))

        ImagePaste.purge(directory: directory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
