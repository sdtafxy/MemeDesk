import Foundation

enum UpdateInstallError: Error, Sendable {
    /// `ditto` 解压失败。
    case unarchiveFailed(Int32)
    /// 解出来的目录里没有 .app。
    case bundleNotFound
    /// 解出来的东西不是 MemeDesk。
    case identityMismatch(expected: String, actual: String)
    /// 解出来的版本号和 Release 上写的不一致。
    case versionMismatch(expected: String, actual: String)
    /// 目标位置不可写，没法覆盖。
    case destinationNotWritable(String)
    case helperFailed(Int32)
}

/// 把新版本**原地覆盖**到正在运行的这个 App 上。
///
/// 为什么不能在 App 里直接替换自己：正在执行的二进制被替换掉会得到未定义行为，
/// 而且中途任何一次读写都可能撞上"半个包"。所以标准做法是——
///
/// 1. 先把新版本解压到缓存目录并校验；
/// 2. 生成一个 **/bin/sh 脚本**，把它交给系统后**自己立刻退出**；
/// 3. 脚本等我们的进程真的消失，然后把旧 App 挪到隐藏的备份位，
///    再把新 App 拷进去；**任何一步失败都把备份挪回来**；
/// 4. 末尾重新 `open` 新版本。
///
/// 用户数据（`~/Library/Application Support/MemeDesk/desk.json`、素材本身）
/// 全都在 App 包之外，**替换包体不会碰它们** —— 这就是"无损覆盖"的含义。
enum UpdateInstaller {

    // MARK: - 准备

    /// 解开 zip，校验里面确实是我们期望的那个版本，返回 .app 的路径。
    static func prepare(zipURL: URL,
                        in workingDirectory: URL,
                        expectedBundleID: String,
                        expectedVersion: String) throws -> URL {
        let fm = FileManager.default
        let unpacked = workingDirectory.appendingPathComponent("unpacked", isDirectory: true)
        try? fm.removeItem(at: unpacked)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)

        let status = run("/usr/bin/ditto", ["-x", "-k", "--rsrc", zipURL.path, unpacked.path])
        guard status == 0 else { throw UpdateInstallError.unarchiveFailed(status) }

        guard let app = findAppBundle(in: unpacked) else {
            throw UpdateInstallError.bundleNotFound
        }

        guard let bundle = Bundle(path: app.path) else {
            throw UpdateInstallError.bundleNotFound
        }
        let identifier = bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String ?? ""
        guard identifier == expectedBundleID else {
            throw UpdateInstallError.identityMismatch(expected: expectedBundleID, actual: identifier)
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard version == expectedVersion else {
            throw UpdateInstallError.versionMismatch(expected: expectedVersion, actual: version)
        }
        return app
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil) else {
            return nil
        }
        if let direct = entries.first(where: { $0.pathExtension == "app" }) { return direct }
        // 有些打包方式会多套一层目录
        for entry in entries where entry.hasDirectoryPath {
            if let nested = findAppBundle(in: entry) { return nested }
        }
        return nil
    }

    // MARK: - 权限预检

    /// 能不能覆盖这个 App。**必须在退出之前问**，
    /// 否则用户会看到"App 退出了但什么也没发生"。
    static func canReplace(destination: URL) -> Bool {
        let parent = destination.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: parent.path)
    }

    // MARK: - 交给 helper

    /// 生成并启动替换脚本。调用方**紧接着就应该退出 App**。
    static func scheduleInstall(workingDirectory: URL,
                                destination: URL,
                                replacement: URL,
                                relaunch: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let logURL = workingDirectory.appendingPathComponent("update.log")
        let scriptURL = workingDirectory.appendingPathComponent("apply-update.sh")
        try helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil)
        }

        // 备份放在**同一个目录**里：同卷 rename 是原子的，而且比跨卷复制快得多。
        // 用点开头 + 非 .app 后缀，Finder 里看不见，LaunchServices 也不会当成第二个 App。
        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).updating")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path,
                             String(ProcessInfo.processInfo.processIdentifier),
                             destination.path,
                             replacement.path,
                             backup.path,
                             relaunch ? "1" : "0",
                             logURL.path]
        process.currentDirectoryURL = workingDirectory
        // 把三个标准流都从我们身上摘掉：我们马上就要退出，
        // 让子进程继续往已关闭的管道里写会拿到 SIGPIPE。
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
    }

    /// 上一次更新留下的日志，排查失败时很有用。
    static func logURL(workingDirectory: URL) -> URL {
        workingDirectory.appendingPathComponent("update.log")
    }

    // MARK: - helper 脚本

    private static let helperScript = #"""
    #!/bin/sh
    # 由 MemeDesk 在退出前生成。等 App 退出后把新版本原地覆盖上去，失败则回滚。
    set -u

    PID="$1"; DEST="$2"; SRC="$3"; BACKUP="$4"; RELAUNCH="$5"; LOG="$6"

    say() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG" 2>/dev/null; }
    reopen() { [ "$RELAUNCH" = "1" ] && open "$DEST" >/dev/null 2>&1; return 0; }

    say "helper 启动 pid=$PID dest=$DEST src=$SRC"

    # 中间目录。赋值放在 trap 之前，`set -u` 下才不会在 trap 里炸。
    STAGE=""
    cleanup() {
      # 收到能捕获的信号（TERM/INT/HUP）时收拾中间态：
      # 万一正好停在"旧版本已挪走、新版本还没就位"那一瞬间，先把备份还原回去。
      if [ ! -e "$DEST" ] && [ -e "$BACKUP" ]; then
        mv "$BACKUP" "$DEST" 2> /dev/null
      fi
      [ -n "$STAGE" ] && rm -rf "$STAGE"
      exit 143
    }
    trap cleanup TERM INT HUP

    # ① 等旧进程真的退出（最多 30 秒）
    #
    # ⚠️ 判据要把**僵尸**一起认掉：`kill -0` 对僵尸进程照样返回 0，而僵尸已经不占用任何
    # 文件了。`ps -o state=` 报 `Z` 就当它已经退出 —— 否则这里会白等 30 秒，
    # 然后既不换版本也不重开，用户看到的是"App 关掉了，但什么都没发生"。
    i=0
    while [ "$i" -lt 150 ]; do
      if ! kill -0 "$PID" 2> /dev/null; then break; fi
      case "$(ps -o state= -p "$PID" 2> /dev/null)" in Z*) break ;; esac
      sleep 0.2
      i=$((i + 1))
    done
    if kill -0 "$PID" 2> /dev/null; then
      case "$(ps -o state= -p "$PID" 2> /dev/null)" in
        Z*) : ;;
        *) say "旧进程 30 秒内没退出，放弃"
           # 别就这么走掉 —— 把还在的旧版本重新拉起来，总好过"App 没了"
           reopen
           exit 1 ;;
      esac
    fi

    # ② 先把新版本**完整拷到旁边**，再动旧版本。
    #
    # ⚠️ 顺序是重点。以前是"先把旧的 mv 走、再 ditto 拷新的"，于是在整个 ditto 期间
    # `$DEST` 根本不存在 —— helper 在这段时间被杀、或者断电，用户就**连旧版本都没了**。
    # 改成先拷到同级目录（同卷），之后只剩两次 rename，窗口从"数秒"缩到"微秒"。
    STAGE="$DEST.staging.$$"
    rm -rf "$STAGE"
    if ! ditto "$SRC" "$STAGE"; then
      rm -rf "$STAGE"
      say "拷贝新版本失败（磁盘空间？）"
      reopen
      exit 1
    fi

    # ③ 两次 rename 完成换装，任一步失败都回滚。
    rm -rf "$BACKUP"
    if ! mv "$DEST" "$BACKUP"; then
      rm -rf "$STAGE"
      say "无法移动旧版本（权限不足？）"
      reopen
      exit 1
    fi
    if ! mv "$STAGE" "$DEST"; then
      say "新版本就位失败，回滚"
      rm -rf "$STAGE"
      mv "$BACKUP" "$DEST"
      reopen
      exit 1
    fi

    xattr -dr com.apple.quarantine "$DEST" > /dev/null 2>&1
    rm -rf "$BACKUP"
    say "更新完成 → $DEST"
    reopen
    exit 0
    """#

    // MARK: - 跑一个子进程

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
