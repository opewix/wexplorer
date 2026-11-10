import Foundation

/// Один язык интерфейса: код, самоназвание и таблица строк.
struct Language {
    /// Код ISO 639-1: "en", "ru", "de"…
    let code: String
    /// Как язык называет сам себя — так он показывается в меню «Сервис → Язык».
    let name: String
    let strings: [Str: String]

    var locale: Locale { Locale(identifier: code) }
}

/// Выбор языка интерфейса и доступ к строкам. Как добавить язык — см. Localization/README.md.
enum L10n {
    /// Все встроенные языки в порядке показа в меню.
    static let languages: [Language] = [.english, .russian]
    /// Язык по умолчанию и источник строк, которых нет в переводе.
    static let fallback: Language = .english

    static let appName = "WExplorer"

    private(set) static var current: Language = fallback
    private static let defaultsKey = "interfaceLanguage"

    /// Вызывается при запуске до создания интерфейса.
    static func setUp() {
        current = resolve()
        // Системные надписи (типы файлов, кнопки стандартных диалогов, «Отменить …»)
        // тоже показываются на выбранном языке.
        UserDefaults.standard.set([current.code], forKey: "AppleLanguages")
        #if DEBUG
        reportMissingStrings()
        #endif
    }

    /// Язык, выбранный в меню (может ещё не действовать — до перезапуска).
    static var chosenCode: String? { UserDefaults.standard.string(forKey: defaultsKey) }

    /// Запоминает выбор пользователя; применяется при следующем запуске.
    static func choose(_ language: Language) {
        UserDefaults.standard.set(language.code, forKey: defaultsKey)
    }

    static func language(_ code: String) -> Language? {
        languages.first { $0.code == code }
    }

    static func string(_ key: Str, in language: Language) -> String {
        language.strings[key] ?? fallback.strings[key] ?? key.rawValue
    }

    /// Выбранный пользователем язык, иначе язык системы, иначе английский.
    private static func resolve() -> Language {
        if let code = UserDefaults.standard.string(forKey: defaultsKey), let chosen = language(code) {
            return chosen
        }
        for identifier in systemLanguages {
            if let code = Locale(identifier: identifier).language.languageCode?.identifier,
               let match = language(code) {
                return match
            }
        }
        return fallback
    }

    /// Языки системы. Читаем глобальные настройки: в настройках приложения AppleLanguages
    /// перезаписываем мы сами.
    private static var systemLanguages: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
    }

    private static func reportMissingStrings() {
        for language in languages {
            let missing = Str.allCases.filter { language.strings[$0] == nil }
            if !missing.isEmpty {
                print("[L10n] \(language.code): нет перевода для \(missing.map(\.rawValue).joined(separator: ", "))")
            }
        }
    }
}

/// Строка интерфейса на текущем языке. Подстановки: {0}, {1}… по порядку аргументов.
func tr(_ key: Str, _ args: CustomStringConvertible...) -> String {
    L10n.format(L10n.string(key, in: L10n.current), args)
}

extension L10n {
    /// Строка на заданном языке (например, чтобы спросить о перезапуске уже на новом языке).
    static func tr(_ key: Str, in language: Language, _ args: CustomStringConvertible...) -> String {
        format(string(key, in: language), args)
    }

    fileprivate static func format(_ template: String, _ args: [CustomStringConvertible]) -> String {
        var result = template
        for (index, arg) in args.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: arg.description)
        }
        return result
    }
}
