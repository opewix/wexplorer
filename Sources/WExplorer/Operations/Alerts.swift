import AppKit

/// Диалоги подтверждений и ошибок с формулировками в духе XP.
enum Alerts {
    enum Replace { case yes, yesToAll, no, cancel }

    static func error(_ message: String, info: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = info ?? ""
        alert.addButton(withTitle: tr(.ok))
        alert.runModal()
    }

    static func message(_ message: String, info: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: tr(.ok))
        alert.runModal()
    }

    /// Запрашивает пароль архива. nil — пользователь отказался.
    static func password(for name: String, wrong: Bool) -> String? {
        let alert = NSAlert()
        alert.alertStyle = wrong ? .warning : .informational
        alert.messageText = wrong ? tr(.archiveWrongPassword) : tr(.archiveEnterPassword)
        alert.informativeText = tr(.quotedName, name)
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        alert.accessoryView = field
        alert.addButton(withTitle: tr(.ok))
        alert.addButton(withTitle: tr(.cancel)).keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    static func confirmReplace(_ name: String) -> Replace {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr(.confirmReplaceTitle)
        alert.informativeText = tr(.confirmReplaceText, name)
        alert.addButton(withTitle: tr(.yes))
        alert.addButton(withTitle: tr(.yesToAll))
        alert.addButton(withTitle: tr(.no))
        alert.addButton(withTitle: tr(.cancel)).keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .yes
        case .alertSecondButtonReturn: return .yesToAll
        case .alertThirdButtonReturn: return .no
        default: return .cancel
        }
    }

    static func confirmTrash(_ urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if urls.count == 1 {
            let isDir = (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            alert.messageText = isDir ? tr(.confirmDeleteFolderTitle) : tr(.confirmDeleteFileTitle)
            alert.informativeText = tr(.confirmDeleteOne, urls[0].lastPathComponent)
        } else {
            alert.messageText = tr(.confirmDeleteManyTitle)
            alert.informativeText = tr(.confirmDeleteMany, urls.count)
        }
        alert.addButton(withTitle: tr(.yes))
        alert.addButton(withTitle: tr(.no)).keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }
}
