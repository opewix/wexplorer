import Foundation

/// Форматирование размеров и дат в духе XP.
enum Format {
    private static var units: [String] { [tr(.unitBytes), tr(.unitKB), tr(.unitMB), tr(.unitGB), tr(.unitTB)] }
    private static var locale: Locale { L10n.current.locale }

    private static let integer: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = tr(.dateFormat)
        return f
    }()

    /// «1,23 МБ» / «1.23 MB» — для строки состояния и свойств.
    static func size(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) \(tr(.unitBytes))" }
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let f = NumberFormatter()
        f.locale = locale
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = value < 10 ? 2 : (value < 100 ? 1 : 0)
        return "\(f.string(from: NSNumber(value: value)) ?? "\(value)") \(units[unit])"
    }

    /// «12 КБ» — колонка «Размер» в таблице, всегда в килобайтах с округлением вверх.
    static func kilobytes(_ bytes: Int64) -> String {
        let kb = (bytes + 1023) / 1024
        return "\(integer.string(from: NSNumber(value: kb)) ?? "\(kb)") \(tr(.unitKB))"
    }

    static func bytesExact(_ bytes: Int64) -> String {
        "\(integer.string(from: NSNumber(value: bytes)) ?? "\(bytes)") \(tr(.unitBytes))"
    }

    static func date(_ value: Date?) -> String {
        value.map { date.string(from: $0) } ?? ""
    }
}
