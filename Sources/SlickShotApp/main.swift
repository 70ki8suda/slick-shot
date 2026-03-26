import AppKit

let delegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
