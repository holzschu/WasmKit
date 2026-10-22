import Foundation
import Testing
import WASI
import WasmTypes

@Suite struct RenameDescriptorTests {
    #if os(iOS)
        @Test func repeatedRenameUnderSyntheticTTYReturnsNotDirectory() throws {
            let bridge = try WASIBridgeToHost(
                fileSystem: .host().withPreopens([
                    .init(guestPath: "/", hostPath: "/")
                ]))
            try bridge.runAndClose { bridge in
                let functions: [String: WASIHostFunction<TestSupport.TestGuestMemory>] = bridge.hostFunctions(capabilities: [.fileSystem])
                let rename = try #require(functions["path_rename"])
                let memory = TestSupport.TestGuestMemory()
                let source = Array("dev/tty/child".utf8)
                let destination = Array("unused-rename-destination".utf8)
                memory.write(source, at: 0)
                memory.write(destination, at: 256)
                for _ in 0..<2 {
                    let result = try rename.implementation(memory, [.i32(3), .i32(0), .i32(UInt32(source.count)), .i32(3), .i32(256), .i32(UInt32(destination.count))])
                    #expect(result == [.i32(54)])
                }
            }
        }
    #endif

    @Test func renameUsesSourceAndDestinationDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDirectory = root.appendingPathComponent("source")
        let destinationDirectory = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = sourceDirectory.appendingPathComponent("file")
        let destination = destinationDirectory.appendingPathComponent("file")
        try Data("replacement".utf8).write(to: source)
        try Data("original".utf8).write(to: destination)
        let bridge = try WASIBridgeToHost(
            fileSystem: .host().withPreopens([
                .init(guestPath: "/source", hostPath: sourceDirectory.path),
                .init(guestPath: "/destination", hostPath: destinationDirectory.path),
            ]))
        try bridge.runAndClose { bridge in
            let functions: [String: WASIHostFunction<TestSupport.TestGuestMemory>] = bridge.hostFunctions(capabilities: [.fileSystem])
            let rename = try #require(functions["path_rename"])
            let memory = TestSupport.TestGuestMemory()
            memory.write(Array("file".utf8), at: 0)
            let result = try rename.implementation(memory, [.i32(3), .i32(0), .i32(4), .i32(4), .i32(0), .i32(4)])
            #expect(result == [.i32(0)])
            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(try Data(contentsOf: destination) == Data("replacement".utf8))
        }
    }
}
