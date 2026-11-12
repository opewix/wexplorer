import AppKit
import UniformTypeIdentifiers

/// «Скрывать расширения для зарегистрированных типов файлов», как в свойствах папки Windows.
/// Прячется только расширение, которое система знает (у него есть тип); у папок, дисков и
/// файлов с незнакомым расширением имя показывается целиком. Выключено по умолчанию.
enum FileExtensions {
    static let didChange = Notification.Name("FileExtensionsDidChange")
    private static let key = "hideExtensions"
    /// Переключатель рассылается и другим экземплярам программы, как смена темы.
    private static let distributedName = Notification.Name("dev.oleg.wexplorer.hideExtensions")

    static var hidden: Bool { UserDefaults.standard.bool(forKey: key) }

    static func setHidden(_ hidden: Bool) {
        UserDefaults.standard.set(hidden, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
        DistributedNotificationCenter.default().postNotificationName(
            distributedName, object: hidden ? "1" : "0",
            userInfo: ["pid": Int(ProcessInfo.processInfo.processIdentifier)], deliverImmediately: true)
    }

    /// Подхватывает переключение из других экземпляров.
    static func observeOtherInstances() {
        DistributedNotificationCenter.default().addObserver(forName: distributedName, object: nil, queue: .main) { note in
            guard note.userInfo?["pid"] as? Int != Int(ProcessInfo.processInfo.processIdentifier) else { return }
            UserDefaults.standard.set(note.object as? String == "1", forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Расширение, которое можно прятать: у файла (не папки и не диска), известное системе.
    static func knownExtension(name: String, isDirectory: Bool, isVolume: Bool, contentType: UTType?) -> String? {
        // У ярлыка «расширение» — часть имени цели («Ярлык для отчёт.txt»): его не прячем.
        guard !isDirectory, !isVolume, contentType?.conforms(to: .aliasFile) != true else { return nil }
        let ns = name as NSString
        let ext = ns.pathExtension
        guard !ext.isEmpty, !ns.deletingPathExtension.isEmpty,
              let type = UTType(filenameExtension: ext), !type.isDynamic else { return nil }
        return ext
    }
}

extension FileItem {
    /// Расширение, спрятанное сейчас из имени, или nil.
    var hiddenExtension: String? { FileExtensions.hidden ? knownExtension : nil }

    /// Имя, как его показывает список: без расширения, если оно спрятано.
    var displayName: String {
        guard let ext = hiddenExtension else { return name }
        return String(name.dropLast(ext.count + 1))
    }

    /// Полное имя из того, что ввели при переименовании: спрятанное расширение возвращается на место.
    func fullName(fromEdited edited: String) -> String {
        guard let ext = hiddenExtension else { return edited }
        return edited + "." + ext
    }
}
