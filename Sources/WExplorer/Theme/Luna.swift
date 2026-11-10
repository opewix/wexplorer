import AppKit

/// Палитра и константы темы Luna (синяя). Всё, что связано с видом, живёт здесь.
enum Luna {
    // Поверхности
    static let face = NSColor(hex: 0xECE9D8)
    static let white = NSColor.white
    static let border = NSColor(hex: 0x7F9DB9)
    static let separator = NSColor(hex: 0xACA899)
    static let separatorLight = NSColor.white
    static let thumbBorder = NSColor(hex: 0xD0D0BF)

    // Выделение и текст
    static let selection = NSColor(hex: 0x316AC5)
    static let inactiveSelection = NSColor(hex: 0xDCDAD5)
    static let selectionText = NSColor.white
    static let text = NSColor.black
    static let secondaryText = NSColor(hex: 0x808080)
    static let linkBlue = NSColor(hex: 0x215DC6)
    static let linkHover = NSColor(hex: 0x428EFF)

    // Левая панель
    static let paneTop = NSColor(hex: 0x7BA2E7)
    static let paneBottom = NSColor(hex: 0x6375D6)
    static let groupHeaderLeft = NSColor.white
    static let groupHeaderRight = NSColor(hex: 0xC6D3F7)
    static let groupSpecialLeft = NSColor(hex: 0x0055E5)
    static let groupSpecialRight = NSColor(hex: 0x2663E0)
    static let groupBody = NSColor(hex: 0xD6DFF7)
    static let chevronBorder = NSColor(hex: 0xBFCBEA)

    // Панель инструментов
    static let toolbarTop = NSColor(hex: 0xFAF9F4)
    static let toolbarBottom = NSColor(hex: 0xECE9D8)
    static let buttonHover = NSColor(hex: 0xFFF3C4)
    static let buttonHoverBorder = NSColor(hex: 0xE2A93B)
    static let buttonPressed = NSColor(hex: 0xE3D9B5)

    // Значки
    static let green = NSColor(hex: 0x3C9A3C)
    static let folderYellow = NSColor(hex: 0xF2BE45)
    static let iconBlue = NSColor(hex: 0x2B6BD6)
    static let red = NSColor(hex: 0xD2373C)

    // Метрики
    static let menuBarHeight: CGFloat = 24
    static let toolbarHeight: CGFloat = 48
    static let addressBarHeight: CGFloat = 26
    static let statusBarHeight: CGFloat = 22
    static let sidebarWidth: CGFloat = 260

    // Шрифт: пока системный; Tahoma-подобный свободный шрифт подключим позже.
    static let font = NSFont.systemFont(ofSize: 11)
    static let fontBold = NSFont.boldSystemFont(ofSize: 11)
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
