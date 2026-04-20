import Foundation

// LaunchAgent management — install / remove / check the user-scope
// agent that keeps `killwindow daemon` running. We don't rely on brew
// services since this is a cask distribution now.

let agentLabel = "com.cristim.killwindow"

func agentPlistURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
}

func agentProgramPath() -> String {
    // Stable path: the cask puts the .app in /Applications (or the
    // user's ~/Applications for non-admin installs). Prefer the global
    // location; fall back to the user-local one.
    let candidates = [
        "/Applications/killwindow.app/Contents/MacOS/killwindow",
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/killwindow.app/Contents/MacOS/killwindow").path,
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
}

func agentPlistContents(program: String, logPath: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>                <string>\(agentLabel)</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(program)</string>
            <string>daemon</string>
        </array>
        <key>RunAtLoad</key>            <true/>
        <key>KeepAlive</key>            <true/>
        <key>ProcessType</key>          <string>Interactive</string>
        <key>StandardOutPath</key>      <string>\(logPath)</string>
        <key>StandardErrorPath</key>    <string>\(logPath)</string>
    </dict>
    </plist>
    """
}

func defaultAgentLogPath() -> String {
    "/tmp/killwindow.log"
}

@discardableResult
func runLaunchctl(_ args: [String]) -> Int32 {
    let p = Process()
    p.launchPath = "/bin/launchctl"
    p.arguments = args
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    } catch {
        FileHandle.standardError.write(
            Data("launchctl \(args.joined(separator: " ")): \(error)\n".utf8))
        return -1
    }
}

func agentDomain() -> String {
    "gui/\(getuid())"
}

func enableDaemon() throws {
    let plist = agentPlistURL()
    let program = agentProgramPath()
    if !FileManager.default.fileExists(atPath: program) {
        FileHandle.standardError.write(Data("""
        cannot find \(program).
        install killwindow first:
          brew install --cask cristim/tap/killwindow

        """.utf8))
        exit(1)
    }
    try FileManager.default.createDirectory(
        at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
    let body = agentPlistContents(program: program, logPath: defaultAgentLogPath())
    try body.write(to: plist, atomically: true, encoding: .utf8)

    // Boot it out first in case a previous version is loaded.
    _ = runLaunchctl(["bootout", agentDomain(), plist.path])
    let rc = runLaunchctl(["bootstrap", agentDomain(), plist.path])
    if rc != 0 {
        FileHandle.standardError.write(Data(
            "launchctl bootstrap returned \(rc). plist is at \(plist.path).\n".utf8))
        exit(1)
    }
    print("daemon enabled (\(plist.path))")
    print("log: \(defaultAgentLogPath())")
}

func disableDaemon() {
    let plist = agentPlistURL()
    _ = runLaunchctl(["bootout", agentDomain(), plist.path])
    try? FileManager.default.removeItem(at: plist)
    print("daemon disabled; removed \(plist.path)")
}
