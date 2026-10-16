import AppKit

// 由 `Scripts/make_menubar_icons.py` 从用户提供的照片生成，**不要手改**。
// 4 级 alpha（照片里亮的脸 = 实心、暗的五官 = 透明）按 2bit/像素打包成 base64：
// 为什么不用图片资源 —— 这样 App 里不多一份资源，本文件也仍然只依赖 AppKit，
// 能像 MenuBarIcon.swift 一样单独 swiftc 出来 dump 成 PNG 做目视校对。
enum MenuBarIconBitmaps {
    static let side = 54

    /// jimiSmile：54×54，4 级 alpha 打包成 2bit/像素
    static let jimiSmile = """
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGqpQAAAAAAAAAAAAAG/l
        v5QAAAAAAAAAAAG//lvv5AAAAAAAAAAAvv/mr//kAAAAAAAAAH///qr//+AAAAAAAAAv///r////5AAAAAABr////v/////0AAAA
        AH///////////sAAAAAv///////////+AAAAC/////////////QAAAb/////////////4AAB///////////////AAD/////////+
        /////QAf/////+/+++v///+AAe/////9///9v///8AAB7////+///5////9AAA///4G////r8Af//AAAv//QAP//+rgAAv/QAC//
        /gAD//+uAAAf/wAD///gAA//98AAD6/wAD///gAA//+8AAP8WwAD///2Q3///kAC/9FgAD///u/////hH//9FQAH/////+v/9R//
        vlGQAH+/7/////5C//vWRQAH//+///v/5C//QaQAAD////////+C+/QbgAAC////////+D8H1bkAAB//+7////9D/v0H0QAB/+//
        7/+bgD//+r5wAC//////wBAD///5WgAC//////wAAH//+gHQAB//////+QAP///0HQAA///////kAL///+bQAB//pf//4AAGr/7q
        +AAC//66//kAABqWqq9AAD////UAAAQAACab4AAH////5AAVUAAGirgAAL/////QAAAAAVV/AAAf/////0AAAACpatAAAv/////9
        AVQAaqq0AAB///+v/////qqqvwAAD////q/6v//+qq5wAAD////0WVH//pWqQoAAD////9AAAaVVVUAcAAD/////QAAAAAAAANAA
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        """

    /// jimiFacepalm：54×54，4 级 alpha 打包成 2bit/像素
    static let jimiFacepalm = """
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFv+VAAAAAAAAAAAAABv///kAAAAAAAAAAAAf//
        ///gAAAAAAAAAAH//////4AAAAAAAAAAf///////QAAAAAAAAG///+7///wAAAAAAAL/////////4AAAAAAA7/////////+AAAAA
        ACb////6/////QAAAAAK/////X/////0AAAAAO////+P/////4AAAAAu7///8f/////9AAAAC6m///9/////v/AAAADqW///9+v/
        ///7QAAAC5D///1gC///8BgAAAA0L///gAAv/+wA0AAAA3v///BQAP/7wA4AAAC////9PgAP//wB4AAAD////4NgAL//QD4AAAH/
        ///0fUAa//RfoAAAH////warrl//n+0AAAL////QKv/1v/n50AAAv////AGr/5X/n90AAB////+ABWr5R/m+0AAH////9AZZaqlv
        n50AAv////4ABVuv6mi/0AA/////kAFX0/wAA/0AC////9QAb/5vwAB/0AD////+QAGv//9AD/4AD////6AAAL///gGv9AC////6
        AAAL///kWr9AC++r/5AAAB/upAWX+AD+qqqoAAAAKqkABX/AD+qqqkAAAAAAAAAb/gCuqqqQAFAAAAAAFavwB6qqqUAVUAFVqpVa
        /wAqqqqVAVVQBqqkBWrwAOqqqlAalWkEAAFavwAKqqpQAapa+QABVr/wACqqpQAZqb///+qv/wAAmqlAAaqb//////+gAAdqkAAW
        vm/////++gAAHaUFAWr+//////qQAAA2lpAGv///////qgAAAdr5AWv////////wAAAHvpAWr////////wAAAB6lBWr////////w
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        """
}
