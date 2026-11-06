// Quits a running Margin the normal way (saves documents), without needing
// Automation permission the way `osascript ... quit` does.
import AppKit
for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.diegogilon.margin") {
    app.terminate()
    let deadline = Date().addingTimeInterval(5)
    while !app.isTerminated && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    if !app.isTerminated { print("Margin is still open (it may be asking about unsaved changes)."); exit(1) }
}
