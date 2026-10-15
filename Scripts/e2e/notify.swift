// Posts one E2E debug command to ONE app under test over its debug channel (debug build with
// DEDOCK_E2E=1 only; contract.md). Not input: no event is posted and nothing is clicked. The command
// is addressed by pid (userInfo "pid"): the app runs it only when the pid is its own, so another
// session's Dedock ignores it. It still changes a live app, so (REG-051) it refuses unless
// DEDOCK_LOCK_OWNER holds the REAL desktop lock, checked through Scripts/e2e/desktop-lock.sh require.
//
// Build: swiftc -O Scripts/e2e/notify.swift -o build/e2e/notify
// Run:   build/e2e/notify <pid> <cmd>        e.g. 12345 openSettings, 12345 setEdge=right

import Foundation

func fail(_ m: String) -> Never { FileHandle.standardError.write("notify: \(m)\n".data(using: .utf8)!); exit(2) }

let a = Array(CommandLine.arguments.dropFirst())
guard a.count == 2, let pid = Int(a[0]), pid > 0 else { fail("usage: notify <pid> <cmd>") }

let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let lockScript = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Scripts/e2e/desktop-lock.sh").path
guard let owner = ProcessInfo.processInfo.environment["DEDOCK_LOCK_OWNER"], !owner.isEmpty else {
    fail("refusing: set DEDOCK_LOCK_OWNER (REG-051: needs the REAL desktop lock)")
}
guard FileManager.default.isExecutableFile(atPath: lockScript) else { fail("refusing: cannot find \(lockScript) to check the lock") }
let lock = Process()
lock.executableURL = URL(fileURLWithPath: lockScript)
lock.arguments = ["require", owner]
lock.standardOutput = FileHandle.nullDevice; lock.standardError = FileHandle.nullDevice
do { try lock.run(); lock.waitUntilExit() } catch { fail("refusing: lock check did not run") }
guard lock.terminationStatus == 0 else { fail("refusing: '\(owner)' does not hold the REAL desktop lock (REG-051)") }

DistributedNotificationCenter.default().postNotificationName(
    .init("app.dedock.debug.command"), object: nil,
    userInfo: ["cmd": a[1], "pid": pid], deliverImmediately: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.1))  // let the post leave before exiting
print("posted cmd=\(a[1]) pid=\(pid)")
