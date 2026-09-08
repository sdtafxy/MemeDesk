import AppKit

// 纯 AppKit 入口，不经过 SwiftUI 生命周期。
//
// 之所以不用 SwiftUI 的 MenuBarExtra：它对窗口尺寸有自己的一套协商逻辑，
// 内容一变（比如加了素材）面板顶部就会被顶下去几十像素，我们无法干预。
// 改为自管 NSStatusItem + NSPopover 后，面板尺寸是算术常量，想变都变不了。
let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
