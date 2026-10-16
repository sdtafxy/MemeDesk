import AppKit

// 由 `Scripts/make_menubar_icons.py` 从用户提供的照片生成，**不要手改**。
// 4 级 alpha（照片里亮的脸 = 实心、暗的五官 = 透明）按 2bit/像素打包成 base64：
// 为什么不用图片资源 —— 这样 App 里不多一份资源，本文件也仍然只依赖 AppKit，
// 能像 MenuBarIcon.swift 一样单独 swiftc 出来 dump 成 PNG 做目视校对。
enum MenuBarIconBitmaps {
    static let side = 54

    /// jimiSmile：54×54，4 级 alpha 打包成 2bit/像素
    static let jimiSmile = """
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGqpAAAAAAAAAAAAAAK/m/5AAAAAAAAAAAAG/+V
        vv1AAAAAAAAAAC//+Wv//gAAAAAAAAAb//+qr//+AAAAAAAAC///+qv///5AAAAAABb///+v/////kAAAAAf///////////9AAAA
        B////////////3AAAAL/////////////gAAAv/////////////4AAH//////////////+QAf///////////////wA//////7///+
        /////0H//////7/+++v////gCv/////3/+/9v///+AAfv////7///5v////QAL///0/////r+Af//gAL//9AA///+rwABf/0Af//
        9AAP//+vAAAL/8Av/79AAD//58AAC6/8A///8AAD//+8AAD9a8A////IBT//+0AAf/FoA////rr////gBb//CYA//////+//6R//
        /+RUA/7////+v/5C//v1hkB/v/v///v/5C//qWgUA///2///v/5C//gG0AAv////////9C+rka0AAv////////9D9H5W5AAf///f
        ////9D//4C5IAP/r////+bQD///r6sAf//////ABAD///+VoAf//////wAAH//+4F0Af//////9AAP///4B0AP//////+QAb///+
        WwAL//l///4AAGqv7r/gAf/+Wr/+UAAG/q+pvQAv///9VBAAAAABqa+AA////+gAApUAABmn8AC/////4AAAAAAVkq0AC/////+A
        AAAABpZvQAH//////wAAAAGpauAAL///7//5GpVRqqr4AAf///6///////qqv4AA////+b/p///+mq9YAA/////QVUL//pWqQNAA
        /////0AABpVVVUAWAA/////9AAAAAAAAATQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        """

    /// jimiFacepalm：54×54，4 级 alpha 打包成 2bit/像素
    static let jimiFacepalm = """
        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB/+RAAAAAAAAAAAAAB////kAAAAAAAAAAABv/////gAAAAAAAAAAb///
        ///4AAAAAAAAAB////////QAAAAAAAAH////7///wAAAAAAAa////+////4AAAAAAC//////////+AAAAAAJv//////////gAAAA
        Aq/////W/////0AAAAB7////9P/////9AAAACv////8v/////+AAAALuv///8/////7/QAAAeqb///5/+//v7/gAAAqpf///36f/
        ///50AAAfgf///iAD///+AoAAAKA///+AAA//+8ANAAAJu///9GAAP/+0AdAAAf////4fAAP//0AtAAAv////g9QAL//wA9AAAv/
        ///g9gAb//gH9AAA/////AuaWl/+m/tAAB////+Aqv/lv/m/tAAC////9AWv/1b/m+dAAL////4AFqv5W/2/tAAv////4BQWr5Vu
        q+tAC/////wAapaq5rl+dAL/////gAAW6/5RQ/8Af////6QAavg/wAAv8Av////1AAb/6/4AA/9A/////pAAFv//+QC/+A/////o
        AAAf///kGv/Av////kAAAL///kVq/Qv/6v/gAAAC/qpAGm/g/qqqugAAAAKqkAAW/w/qqqpQAAAAAAAAAW/0rqqqlAAEAAAAAABW
        v8eqqqpAAVQAAAVlVWv8KqqqpQAVVAFqqpRVr8DqqqqkBaVVAZVQBWr8CqqqlQBqla4AAAFa/8AqqqlABmpqvqqqpr/8AOqqVABm
        pf///////4AHapQABaub///////oACmpQEBavm//////uoAAZpQUAav+//////6kAAGaqkAa////////qoAABm+kAav////////8
        AAAa6UBav////////8AAAO6UFav////////8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        """
}
