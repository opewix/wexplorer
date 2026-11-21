import AppKit

/// Пункты Git в контекстных меню — как у TortoiseGit в Проводнике: «Git Sync…»,
/// «Git Commit -> "ветка"…» и группа WTortoise с остальными командами (сверху Pull, Fetch, Push).
///
/// Работают через программу WTortoise (github.com/opewix/wtortoise): пункт открывает её ссылкой
/// `wtortoise://команда?path=…`. Не установлена — пунктов нет. Сами с git не работаем.
enum GitMenu {
    private static let bundleID = "dev.oleg.wtortoise"

    private static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    /// Язык пунктов — тот, что выбран в настройках WTortoise (по умолчанию английский), а не язык WExplorer:
    /// меню должно совпадать с окнами, которые оно открывает, и с меню WTortoise в Finder.
    private static var language: Language {
        UserDefaults(suiteName: bundleID)?.string(forKey: "language") == "ru" ? .russian : .english
    }

    /// WTortoise установлена.
    static var isAvailable: Bool { appURL != nil }

    /// Пункты для выбранных объектов (или для открытой папки). Пусто — WTortoise не установлена.
    static func items(for urls: [URL]) -> [NSMenuItem] {
        guard let first = urls.first, let app = appURL else { return [] }
        let paths = urls.map(\.path)
        // Значки — те же, что в меню Finder: WTortoise хранит их у себя в Resources/MenuIcons/<команда>.png.
        func icon(_ name: String) -> NSImage? {
            let image = NSImage(contentsOf: app.appendingPathComponent("Contents/Resources/MenuIcons/\(name).png"))
            image?.size = NSSize(width: 16, height: 16)
            return image
        }
        func item(_ title: String, _ command: String) -> NSMenuItem {
            let item = ActionMenuItem(title: title) { run(command, paths: paths) }
            item.image = icon(command)
            return item
        }
        func group(_ items: [NSMenuItem]) -> NSMenuItem {
            let parent = Menus.submenu("WTortoise", items)
            parent.image = icon("app")
            return parent
        }
        let language = self.language
        func tr(_ key: Str, _ args: CustomStringConvertible...) -> String {
            args.isEmpty ? L10n.tr(key, in: language) : L10n.tr(key, in: language, args[0])
        }
        let tail = [item(tr(.gitSettings), "settings"), item(tr(.gitAbout), "about")]

        guard let root = root(of: first.path) else {
            return [item(tr(.gitClone), "clone"), item(tr(.gitCreateRepository), "init"), group(tail)]
        }
        return [
            item(tr(.gitSync), "sync"),
            item(tr(.gitCommitTo, branch(root: root) ?? "HEAD"), "commit"),
            group([
                // Порядок и разделители — как в подменю TortoiseGit; тот же, что в меню WTortoise в Finder.
                item(tr(.gitPullInGroup), "pull"), item(tr(.gitFetchInGroup), "fetch"), item(tr(.gitPush), "push"),
                .separator(),
                item(tr(.gitDiff), "diff"), item(tr(.gitDiffPrevious), "diffprev"),
                .separator(),
                item(tr(.gitLog), "log"), item(tr(.gitRefLog), "reflog"), item(tr(.gitRefBrowse), "refbrowse"),
                item(tr(.gitStatus), "status"), item(tr(.gitRebase), "rebase"),
                item(tr(.gitStash), "stash"), item(tr(.gitStashPop), "stashpop"), item(tr(.gitStashList), "stashlist"),
                .separator(),
                item(tr(.gitResolve), "resolve"),
                item(tr(.gitRename), "rename"), item(tr(.gitDelete), "delete"), item(tr(.gitRevert), "revert"),
                item(tr(.gitCleanup), "cleanup"), item(tr(.gitReset), "reset"),
                .separator(),
                item(tr(.gitSwitch), "switch"), item(tr(.gitMerge), "merge"),
                item(tr(.gitBranch), "branch"), item(tr(.gitTag), "tag"), item(tr(.gitExport), "export"),
                .separator(),
                item(tr(.gitAdd), "add"), item(tr(.gitBlame), "blame"),
                .separator(),
                item(tr(.gitCloneInGroup), "clone"),
                .separator(),
            ] + tail),
        ]
    }

    private static func run(_ command: String, paths: [String]) {
        var parts = URLComponents()
        parts.scheme = "wtortoise"
        parts.host = command
        parts.queryItems = paths.map { URLQueryItem(name: "path", value: $0) }
        if let url = parts.url { NSWorkspace.shared.open(url) }
    }

    /// Корень рабочей копии: ближайшая папка вверх, где есть `.git`.
    static func root(of path: String) -> String? {
        let fm = FileManager.default
        var dir = path
        var isDir: ObjCBool = false
        if !(fm.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue) {
            dir = (dir as NSString).deletingLastPathComponent
        }
        while !dir.isEmpty {
            if fm.fileExists(atPath: dir + "/.git") { return dir }
            if dir == "/" { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Текущая ветка из `HEAD`; nil — HEAD отсоединён. `.git` бывает файлом-ссылкой (worktree, submodule).
    private static func branch(root: String) -> String? {
        var gitDir = root + "/.git"
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: gitDir, isDirectory: &isDir), !isDir.boolValue,
           let text = try? String(contentsOfFile: gitDir, encoding: .utf8), text.hasPrefix("gitdir:") {
            let target = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            gitDir = target.hasPrefix("/") ? target : root + "/" + target
        }
        guard let head = try? String(contentsOfFile: gitDir + "/HEAD", encoding: .utf8) else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
    }
}
