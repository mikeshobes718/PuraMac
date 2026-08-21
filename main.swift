import AppKit
import UserNotifications

let app = NSApplication.shared
let delegate = AppDelegate()
let notifyDelegate = NotifyDelegate()
UNUserNotificationCenter.current().delegate = notifyDelegate
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
