import AppKit
import KarunManagerCore

let app = NSApplication.shared
let delegate = AppDelegate(options: LaunchOptions(arguments: CommandLine.arguments))
app.delegate = delegate
// Mirrors LSUIElement so `swift run` also stays out of the Dock and Cmd+Tab.
app.setActivationPolicy(.accessory)
app.run()
