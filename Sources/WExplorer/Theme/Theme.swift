import AppKit

/// Внешний вид окна: Проводник Windows XP или Windows 10. Меняется на лету — окна пересобираются.
enum Theme: String, CaseIterable {
    case xp, win10

    private static let defaultsKey = "theme"

    /// Читается один раз при запуске, дальше меняется только через `choose`.
    private(set) static var current: Theme = {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Theme.init(rawValue:)) ?? .xp
    }()

    static func choose(_ theme: Theme) {
        current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: defaultsKey)
    }

    static var isWin10: Bool { current == .win10 }

    var title: String {
        switch self {
        case .xp: return tr(.themeXP)
        case .win10: return tr(.themeWin10)
        }
    }

    /// Шрифт списка, дерева и строки состояния.
    static var font: NSFont { isWin10 ? Win10.font : Luna.font }
}

/// Палитра и метрики Проводника Windows 10 (светлая тема).
enum Win10 {
    static let accent = NSColor(hex: 0x0078D7)
    static let text = NSColor.black
    static let secondaryText = NSColor(hex: 0x6D6D6D)
    static let disabledText = NSColor(hex: 0xA0A0A0)

    // Выделение и наведение в списке, дереве и на кнопках
    static let hover = NSColor(hex: 0xE5F3FF)
    static let hoverBorder = NSColor(hex: 0xCCE8FF)
    static let selection = NSColor(hex: 0xCCE8FF)
    static let selectionBorder = NSColor(hex: 0x99D1FF)
    static let inactiveSelection = NSColor(hex: 0xD9D9D9)

    // Лента
    static let fileTab = NSColor(hex: 0x1979CA)
    static let fileTabHover = NSColor(hex: 0x2A8AD4)
    static let ribbonBackground = NSColor(hex: 0xF5F6F7)
    static let ribbonBorder = NSColor(hex: 0xDADBDC)
    static let groupSeparator = NSColor(hex: 0xE2E3E4)
    static let groupLabel = NSColor(hex: 0x6D6D6D)

    // Адресная строка, поиск, заголовки колонок
    static let fieldBorder = NSColor(hex: 0xD9D9D9)
    static let fieldHoverBorder = NSColor(hex: 0x7EB4EA)
    static let headerText = NSColor(hex: 0x4C607A)
    static let headerSeparator = NSColor(hex: 0xE5E5E5)
    static let paneDivider = NSColor(hex: 0xF0F0F0)
    static let glyph = NSColor(hex: 0x606060)

    // Метрики
    static let tabStripHeight: CGFloat = 25
    static let ribbonPanelHeight: CGFloat = 94
    static let navigationBarHeight: CGFloat = 36
    static let statusBarHeight: CGFloat = 22
    static let rowHeight: CGFloat = 22
    static let sidebarWidth: CGFloat = 200

    /// Segoe UI 9 pt в Windows — это 12 точек на Mac. Сам Segoe не поставляем — см. `Fonts`.
    static var font: NSFont { Fonts.ui(12) }
    static var smallFont: NSFont { Fonts.ui(11) }
}

/// Шрифт окна. Шрифтов Microsoft в программе нет: берём те, что уже стоят в системе. Tahoma — шрифт
/// интерфейса Windows XP — входит в macOS; Segoe UI (Windows 10) используется, только если
/// пользователь установил его сам. «Вид → Шрифт как в Windows» возвращает системный шрифт macOS.
enum Fonts {
    private static let key = "windowsFont"

    /// Включён по умолчанию: пока пользователь не выключил, ключа в настройках нет.
    static var windows: Bool = UserDefaults.standard.object(forKey: key) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(windows, forKey: key)
            cache = [:]
        }
    }

    private static let available: Set<String> = Set(["Segoe UI", "Tahoma"].filter {
        NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 12) != nil
    })
    private static var cache: [String: NSFont] = [:]

    static func ui(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let wanted = !windows ? [] : Theme.isWin10 ? ["Segoe UI", "Tahoma"] : ["Tahoma"]
        let family = wanted.first { available.contains($0) }
        let key = "\(family ?? "")|\(size)|\(bold)"
        if let font = cache[key] { return font }
        let system = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        let font = family.flatMap {
            NSFontManager.shared.font(withFamily: $0, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size)
        } ?? system
        cache[key] = font
        return font
    }
}

extension NSBezierPath {
    /// Прямоугольник с рамкой в один пиксель, как у кнопок и выделения Windows 10.
    static func win10Box(_ rect: NSRect, fill: NSColor, border: NSColor?) {
        fill.setFill()
        rect.fill()
        guard let border else { return }
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        border.setStroke()
        path.stroke()
    }
}
