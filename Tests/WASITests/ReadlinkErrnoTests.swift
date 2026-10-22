import Foundation
import Testing
import WASI
import WasmTypes

@Suite struct ReadlinkErrnoTests {
    @Test func hostReadlinkReturnsErrnosAndLinkBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("unchanged".utf8).write(to: directory.appendingPathComponent("file"))
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("link").path, withDestinationPath: "file")
        let bridge = try WASIBridgeToHost(
            fileSystem: .host().withPreopens([
                .init(guestPath: ".", hostPath: directory.path)
            ]))
        try bridge.runAndClose { bridge in
            let functions: [String: WASIHostFunction<TestSupport.TestGuestMemory>] = bridge.hostFunctions(capabilities: [.fileSystem])
            let readlink = try #require(functions["path_readlink"])
            let memory = TestSupport.TestGuestMemory()
            for (name, expectedErrno) in [("file", UInt32(28)), ("missing", 44), ("file/child", 54), ("link", 0)] {
                #if os(iOS)
                    let path = directory.appendingPathComponent(name).path
                #else
                    let path = name
                #endif
                let bytes = Array(path.utf8)
                memory.write(bytes, at: 0)
                let result = try readlink.implementation(memory, [.i32(3), .i32(0), .i32(UInt32(bytes.count)), .i32(4096), .i32(256), .i32(8192)])
                #expect(result == [.i32(expectedErrno)])
                if expectedErrno == 0 {
                    #expect(memory.read(count: 4, at: 4096) == Array("file".utf8))
                }
            }
        }
    }
}
