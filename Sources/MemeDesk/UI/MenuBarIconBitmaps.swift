import AppKit

// 由 `Scripts/make_menubar_icons.py` 从用户提供的照片生成，**不要手改**。
// 4 级 alpha（照片里亮的脸 = 实心、暗的五官 = 透明）按 2bit/像素打包成 base64：
// 为什么不用图片资源 —— 这样 App 里不多一份资源，本文件也仍然只依赖 AppKit，
// 能像 MenuBarIcon.swift 一样单独 swiftc 出来 dump 成 PNG 做目视校对。
enum MenuBarIconBitmaps {
    static let side = 54

    /// jimiSmile：54×54，4 级 alpha 打包成 2bit/像素
    static let jimiSmile = """
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        AAAAAAAAAAAAAAAAGqpQAAAAAAAAAAAAAG/lv5AAAAAAAAAAAAG//lvv4AAAAAAAAAAAf//mv//QAAAAAAAAAG///qv//9AAAAAA
        AABf///v////5AAAAAAAv//////////AAAAAAC//////////+gAAAAAL///////////0AAAABv///////////+AAAAH/////////
        ////gAAAf/////////////0AAB/////+/+/6////gAAB/////9/+/6////AAAALv///+///2////QAAAH//9Av///vwC//wAAAH/
        /0AD//+uAAD/4AAAP/74AB//68AAG/8AAAf//0AA//6wAA/b8AAAf//4QE//+wAD/RoAAAf//+tv///QAv/hYAAAf/////v/6C//
        +hkAAAf/+///r/5H/79UkAAAvv/v//7/5H/9VoAAAAf//7////4H/8GoAAAAP///////8HweW5AAAAL//u////8P+/BtEAAAL/v/
        +//rgP//2+cAAAL/////wBAP//+VoAAAP/////4AAP//tB4AAAL//////QAv//+B0AAAH/////+UAa///qwAAAL/5W//4AAG+/6v
        gAAAP//+6qkAAAAaqvQAAAf///5AAVUAAZq+AAAAv////AAAAABVK4AAAA/////0AAAAGWbwAAAC/////9AAAAamrQAAAH///v//
        q+qWqq9AAAAL///6/+v//+qrtAAAAP///9alX//laqHAAAAP///+AABqpVVQDQAAAP////0AAAAAAAFgAAAAAAAAAAAAAAAAAAAA
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        """

    /// jimiFacepalm：54×54，4 级 alpha 打包成 2bit/像素
    static let jimiFacepalm = """
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFv
        +VAAAAAAAAAAAAABv///UAAAAAAAAAAAAf////+AAAAAAAAAAAH//////kAAAAAAAAAAf//////9AAAAAAAAAa///6v//+AAAAAA
        AAH/////////gAAAAAAAd/////////4AAAAAAA3////n////9AAAAAACv////P/////AAAAAADv///9f/////gAAAAAPpv//9/+/
        /+/0AAAAAqpv//9////+/4AAAAAfQ///1gD//7wMAAAAAJC///gAA//7AOAAAAAJ////SAAv/uAOAAAAAf///9LQAf/+AOAAAAAv
        ///8OgAf/8A+AAAAAv///4PUBn/9L6AAAAA////wKv/X/+v6AAAAB////gGv/lv+vqAAAAH////QBqv1b+vuAAAAf////AVWrpW6
        vqAAAB////9AGpqrmpfqAAAD////4AAH2/UEL9AAAL////UAb/h/AAP9AAAP///+QAGv//wAf+AAAP///+gAAf//9Br/QAAP///+
        QAAL//+Ra/gAAP76/+AAAB/6kBpvgAAP6mqpAAAAKpQAFv0AAOqqqlAAAAAAAAFv4AALqqqkAFQAAAABWr8AAHqqqlAFUAFWqlVr
        8AABqqqqAFlUBqpAFr8AAB6qqVAKla0AABWv8AAAeqqUAJpa/qqma/8AAAGqpUAKqb//////4AAACapAAGrX/////voAAABmpBQG
        r6/////+oAAAAJlVQGv//////6oAAAACa6QGv//////+8AAAAAm6QGr///////8AAAAAe5AWr///////8AAAAAAAAAAAAAAAAAAA
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        """
}
