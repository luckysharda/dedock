// Posts one E2E debug command to the app under test over its debug channel (debug build with
// DEDOCK_E2E=1 only; contract.md). Not input: no event is posted and nothing is clicked.
//
// Build: swiftc -O Scripts/e2e/notify.swift -o build/e2e/notify
// Run:   build/e2e/notify <cmd>        e.g. openSettings, reveal, hide, setEdge=right

import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: notify <cmd>\n".data(using: .utf8)!); exit(2)
}
DistributedNotificationCenter.default().postNotificationName(
    .init("app.dedock.debug.command"), object: nil,
    userInfo: ["cmd": CommandLine.arguments[1]], deliverImmediately: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.1))  // let the post leave before exiting
print("posted cmd=\(CommandLine.arguments[1])")
