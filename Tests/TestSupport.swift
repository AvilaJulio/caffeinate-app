import Foundation

/// Number of failed checks so far. `Tests/main.swift` uses this as the exit code signal.
var failureCount = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok    \(message)")
    } else {
        print("  FAIL  \(message)")
        failureCount += 1
    }
}

/// True when *this* process currently holds a PreventUserIdleDisplaySleep
/// assertion, according to `pmset` — the same view the user gets from the
/// command line. Checking the kernel's own accounting rather than our
/// instance variable is the point: it proves the assertion is really taken.
func processHoldsDisplayAssertion() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["-g", "assertions"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try! task.run()
    // Read before waiting, or a full pipe buffer would deadlock.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    let marker = "pid \(getpid())("
    return output.split(separator: "\n").contains { line in
        line.contains(marker) && line.contains("PreventUserIdleDisplaySleep")
    }
}
