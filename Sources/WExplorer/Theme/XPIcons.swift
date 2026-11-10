import AppKit
import UniformTypeIdentifiers

/// Собственный набор иконок в плоском стиле Windows 10. Всё рисуется векторно в сетке 32×32,
/// поэтому иконки чёткие в любом размере. Оригинальные ресурсы Microsoft не используются.
enum XPIcon: String {
    // Места
    case folder, folderOpen, desktop, documents, computer
    // Диски
    case hardDrive, removableDrive, networkDrive, cdDrive
    // Файлы
    case file, text, document, spreadsheet, image, audio, video, archive, pdf, code, program
    // Тулбар
    case back, forward, up, search, views, go
    // Панель задач
    case newFolder, moveTo, copyTo, delete, rename, info, settings
    // Адресная строка
    case copyPath
}

enum XPIcons {
    private static var cache: [String: NSImage] = [:]

    /// Иконка заданного вида. `size` — размер NSImage в точках; рисуется она в любом размере.
    static func image(_ icon: XPIcon, size: CGFloat = 32) -> NSImage {
        let key = "\(icon.rawValue)@\(size)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let devicePixels = rect.width * abs(cg.userSpaceToDeviceSpaceTransform.a)
            cg.saveGState()
            cg.scaleBy(x: rect.width / 32, y: rect.height / 32)
            draw(icon, Pen(pixel: 32 / max(devicePixels, 1)))
            cg.restoreGState()
            return true
        }
        cache[key] = image
        return image
    }

    // MARK: Сопоставление файлов и иконок

    static func icon(for item: FileItem, size: CGFloat = 32) -> NSImage {
        if item.isVolume { return image(volumeKind(item.url), size: size) }
        if item.isDirectory { return image(folderKind(item.url), size: size) }
        guard let kind = fileKind(item.contentType, ext: item.url.pathExtension) else {
            return systemIcon(item.url, size: size)
        }
        return image(kind, size: size)
    }

    /// Иконка для места (папка или диск) по адресу.
    static func icon(forLocation url: URL, size: CGFloat = 16) -> NSImage {
        let values = try? url.resourceValues(forKeys: [.isVolumeKey, .contentTypeKey, .isDirectoryKey, .isPackageKey])
        if values?.isVolume == true { return image(volumeKind(url), size: size) }
        if values?.isDirectory == true && values?.isPackage != true { return image(folderKind(url), size: size) }
        guard let kind = fileKind(values?.contentType, ext: url.pathExtension) else { return systemIcon(url, size: size) }
        return image(kind, size: size)
    }

    private static func systemIcon(_ url: URL, size: CGFloat) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    private static func folderKind(_ url: URL) -> XPIcon {
        let path = url.standardizedFileURL.path
        if path == Places.desktop.standardizedFileURL.path { return .desktop }
        if path == Places.documents.standardizedFileURL.path { return .documents }
        return .folder
    }

    private static func volumeKind(_ url: URL) -> XPIcon {
        let values = try? url.resourceValues(forKeys: [
            .volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeLocalizedFormatDescriptionKey,
        ])
        if values?.volumeIsLocal == false { return .networkDrive }
        let format = values?.volumeLocalizedFormatDescription?.lowercased() ?? ""
        if format.contains("iso") || format.contains("cd") || format.contains("udf") { return .cdDrive }
        if values?.volumeIsRemovable == true || values?.volumeIsEjectable == true { return .removableDrive }
        return .hardDrive
    }

    /// nil — у файла своя иконка (например, у приложения), её берём из системы.
    private static func fileKind(_ type: UTType?, ext: String) -> XPIcon? {
        let ext = ext.lowercased()
        let type = type ?? UTType(filenameExtension: ext)
        guard let type else { return .file }
        if type.conforms(to: .applicationBundle) || type.conforms(to: .application) { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archive }
        if type.conforms(to: .spreadsheet) { return .spreadsheet }
        if type.conforms(to: .presentation) || type.conforms(to: .rtf)
            || ["doc", "docx", "odt", "pages", "rtfd", "key", "ppt", "pptx"].contains(ext) { return .document }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json)
            || type.conforms(to: .xml) || type.conforms(to: .html) || type.conforms(to: .yaml) { return .code }
        if type.conforms(to: .text) { return .text }
        if type.conforms(to: .unixExecutable) || type.conforms(to: .executable) { return .program }
        return .file
    }

    // MARK: Рисование (плоский стиль Windows 10)

    private static func draw(_ icon: XPIcon, _ p: Pen) {
        switch icon {
        case .folder: folder(p, paper: .plain)
        case .folderOpen: folder(p, open: true, paper: .plain)
        case .documents: folder(p, paper: .lines)
        case .desktop: desktop(p)
        case .computer: computer(p)
        case .hardDrive: hardDrive(p)
        case .removableDrive: removableDrive(p)
        case .networkDrive: networkDrive(p)
        case .cdDrive: cdDrive(p)
        case .file: page(p)
        case .text: page(p); textLines(p, color: 0xA6A6A6)
        case .document: document(p)
        case .spreadsheet: spreadsheet(p)
        case .image: picture(p)
        case .audio: audio(p)
        case .video: video(p)
        case .archive: archive(p)
        case .pdf: pdf(p)
        case .code: code(p)
        case .program: program(p)
        case .back: navArrow(p, angle: 180)
        case .forward: navArrow(p, angle: 0)
        case .up: navArrow(p, angle: -90)
        case .search: magnifier(p)
        case .views: views(p)
        case .go: go(p)
        case .newFolder: folder(p, paper: .plain); badge(p, color: 0x2EA043, symbol: .plus)
        case .moveTo: folder(p, paper: .plain); badge(p, color: accent, symbol: .arrow)
        case .copyTo: copyTo(p)
        case .delete: deleteCross(p)
        case .rename: rename(p)
        case .info: info(p)
        case .settings: gear(p)
        case .copyPath: clipboard(p)
        }
    }

    /// Фирменный синий Windows 10.
    private static let accent: UInt32 = 0x0078D7
    private static let ink: UInt32 = 0x3A3A3A

    // MARK: Папки и места

    private enum Paper { case none, plain, lines }

    private static func folder(_ p: Pen, open: Bool = false, paper: Paper) {
        // Задняя стенка с ярлычком — темнее, передняя — светлее, без обводки, как в Windows 10.
        let back = poly([(2, 6.5), (2.6, 5.5), (11.5, 5.5), (13.8, 8), (29.4, 8), (30, 8.6), (30, 26), (2, 26)])
        p.fill(back, 0xE9AE3C, 0xDB9A28)

        switch paper {
        case .none:
            break
        case .plain:
            p.fill(rr(4.5, 9.5, 23, 6), 0xFFFFFF, 0xF2F2F2)
        case .lines:
            let sheet = rr(6, 3, 20, 14)
            p.fill(sheet, 0xFFFFFF, 0xF4F4F4)
            p.stroke(sheet, 0xD0D0D0, width: 0.7)
            for y in [6.5, 9.0, 11.5] as [CGFloat] {
                p.line(line([(9, y), (23, y)]), accent, width: 1.2)
            }
        }

        let front = open
            ? poly([(5.5, 12.5), (31, 12.5), (28, 26), (2, 26)])
            : rr(2, 11.5, 28, 14.5, 0.8)
        p.fill(front, 0xFFD86A, 0xFFC63A)
        if !open {
            p.line(line([(2.6, 12.1), (29.4, 12.1)]), 0xFFE9A6, width: 0.9)
        }
        p.line(line([(2.5, 25.6), (29.5, 25.6)]), 0xD9962A, width: 0.7)
    }

    private static func desktop(_ p: Pen) {
        let screen = rr(2, 5, 28, 21, 1)
        p.fill(screen, 0x3AA0F0, 0x1569C7)
        NSColor.white.withAlphaComponent(0.18).setFill()
        poly([(2, 5), (18, 5), (8, 22), (2, 22)]).fill()
        p.fill(NSBezierPath(rect: NSRect(x: 2, y: 22, width: 28, height: 4)), 0x2B2B2B, 0x1F1F1F)
        p.fill(rr(3.5, 23, 2.6, 2), 0x4CC2FF, 0x4CC2FF)
        p.stroke(screen, 0x0F4C91, width: 0.8)
    }

    private static func computer(_ p: Pen) {
        let bezel = rr(2.5, 4, 27, 19, 1.5)
        p.fill(bezel, 0x4A4A4A, 0x2E2E2E)
        let screen = NSRect(x: 4.5, y: 6, width: 23, height: 14)
        p.fill(NSBezierPath(rect: screen), 0x4CB4FA, 0x0A64C9)
        NSColor.white.withAlphaComponent(0.2).setFill()
        poly([(4.5, 6), (17, 6), (9, 20), (4.5, 20)]).fill()
        p.fill(NSBezierPath(rect: NSRect(x: 14, y: 23, width: 4, height: 3)), 0x9A9A9A, 0x7A7A7A)
        p.fill(rr(9, 26, 14, 2.4, 1), 0xB8B8B8, 0x9A9A9A)
    }

    // MARK: Диски

    private static func hardDrive(_ p: Pen, dy: CGFloat = 0) {
        let body = rr(2, 10 + dy, 28, 13, 1.5)
        p.fill(body, 0xF2F2F2, 0xDADADA)
        p.fill(rr(2, 17.5 + dy, 28, 5.5, 1.5), 0xA8A8A8, 0x8C8C8C)
        p.stroke(body, 0x8A8A8A, width: 0.7)
        p.line(line([(5, 20.2 + dy), (19, 20.2 + dy)]), 0xCFCFCF, width: 1.2)
        p.fill(oval(24.5, 19.2 + dy, 2.2, 2), 0x55E06A, 0x2DBA48)
    }

    private static func removableDrive(_ p: Pen) {
        let body = rr(5, 6, 22, 21, 1.5)
        p.fill(body, 0xF2F2F2, 0xDADADA)
        p.fill(rr(5, 21, 22, 6, 1.5), 0xA8A8A8, 0x8C8C8C)
        p.stroke(body, 0x8A8A8A, width: 0.7)
        p.fill(rr(9, 10, 14, 2.2, 0.8), 0x4A4A4A, 0x4A4A4A)
        p.fill(oval(21.5, 23.2, 2.2, 2), 0xFFB13B, 0xF08C00)
    }

    private static func networkDrive(_ p: Pen) {
        hardDrive(p, dy: -6)
        p.fill(NSBezierPath(rect: NSRect(x: 15, y: 17, width: 2, height: 5.5)), 0x5A5A5A, 0x5A5A5A)
        p.fill(rr(4, 22.5, 24, 3.6, 1.8), 0x4CC160, 0x2E9E4A)
    }

    private static func cdDrive(_ p: Pen) {
        let disc = oval(6, 2, 20, 20)
        NSGraphicsContext.saveGraphicsState()
        disc.addClip()
        NSGradient(colors: [NSColor(hex: 0xEDEFF7), NSColor(hex: 0xFCE6F1), NSColor(hex: 0xE4F7EC),
                            NSColor(hex: 0xFFF8DD), NSColor(hex: 0xDCE7FA)])?
            .draw(in: NSRect(x: 6, y: 2, width: 20, height: 20), angle: 45)
        NSGraphicsContext.restoreGraphicsState()
        p.stroke(disc, 0xA0A4B0, width: 0.7)
        p.fill(oval(13.5, 9.5, 5, 5), 0xFFFFFF, 0xFFFFFF)
        p.stroke(oval(13.5, 9.5, 5, 5), 0xA0A4B0, width: 0.7)
        let body = rr(2, 18, 28, 9, 1.5)
        p.fill(body, 0xF2F2F2, 0xDADADA)
        p.fill(rr(2, 23, 28, 4, 1.5), 0xA8A8A8, 0x8C8C8C)
        p.stroke(body, 0x8A8A8A, width: 0.7)
        p.fill(rr(5, 20, 14, 1.6, 0.6), 0x4A4A4A, 0x4A4A4A)
    }

    // MARK: Файлы

    private static func page(_ p: Pen, dx: CGFloat = 0, dy: CGFloat = 0) {
        let sheet = poly([(6 + dx, 2 + dy), (19.5 + dx, 2 + dy), (26 + dx, 8.5 + dy), (26 + dx, 30 + dy), (6 + dx, 30 + dy)])
        p.fill(sheet, 0xFFFFFF, 0xFAFAFA)
        p.stroke(sheet, 0xB4B4B4, width: 0.8)
        let ear = poly([(19.5 + dx, 2 + dy), (19.5 + dx, 8.5 + dy), (26 + dx, 8.5 + dy)])
        p.fill(ear, 0xE8E8E8, 0xE8E8E8)
        p.stroke(ear, 0xB4B4B4, width: 0.8)
    }

    private static func textLines(_ p: Pen, color: UInt32, from top: CGFloat = 12) {
        let widths: [CGFloat] = [14, 12, 14, 10, 13, 11]
        var y = top
        for w in widths where y <= 26 {
            p.line(line([(9, y), (9 + w, y)]), color, width: 1.3)
            y += 3
        }
    }

    private static func document(_ p: Pen) {
        page(p)
        p.fill(NSBezierPath(rect: NSRect(x: 9, y: 10, width: 9, height: 3)), accent, accent)
        textLines(p, color: 0x6AA6E8, from: 16)
    }

    private static func spreadsheet(_ p: Pen) {
        page(p)
        let green: UInt32 = 0x21A366
        let grid = NSRect(x: 8.5, y: 11, width: 15, height: 15)
        p.fill(NSBezierPath(rect: NSRect(x: grid.minX, y: grid.minY, width: grid.width, height: 4.5)), green, green)
        p.stroke(NSBezierPath(rect: grid), green, width: 0.9)
        for x in [13.5, 18.5] as [CGFloat] { p.line(line([(x, grid.minY), (x, grid.maxY)]), green, width: 0.8) }
        for y in [15.5, 20.5] as [CGFloat] { p.line(line([(grid.minX, y), (grid.maxX, y)]), green, width: 0.8) }
    }

    /// Плоская картинка: небо, горы, солнце.
    private static func landscape(_ p: Pen, _ r: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: r).addClip()
        p.fill(NSBezierPath(rect: r), 0x7CC8F8, 0x46A8EE)
        p.fill(poly([(r.minX - 1, r.maxY), (r.minX + r.width * 0.38, r.minY + r.height * 0.38), (r.minX + r.width * 0.75, r.maxY)]),
               0x2E9E4A, 0x2E9E4A)
        p.fill(poly([(r.minX + r.width * 0.4, r.maxY), (r.minX + r.width * 0.7, r.minY + r.height * 0.55), (r.maxX + 1, r.maxY)]),
               0x6CC24A, 0x6CC24A)
        p.fill(oval(r.maxX - r.width * 0.32, r.minY + r.height * 0.12, r.width * 0.2, r.width * 0.2), 0xFFC83D, 0xFFC83D)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func picture(_ p: Pen) {
        page(p)
        landscape(p, NSRect(x: 8.5, y: 11, width: 15, height: 13))
    }

    private static func audio(_ p: Pen) {
        page(p)
        p.fill(oval(9, 21.5, 6, 4.3), accent, accent)
        p.fill(oval(17, 19.5, 6, 4.3), accent, accent)
        p.fill(NSBezierPath(rect: NSRect(x: 13.6, y: 11.5, width: 1.5, height: 12)), accent, accent)
        p.fill(NSBezierPath(rect: NSRect(x: 21.6, y: 9.5, width: 1.5, height: 12)), accent, accent)
        p.fill(poly([(13.6, 11.5), (23.1, 9.5), (23.1, 12.3), (13.6, 14.3)]), accent, accent)
    }

    private static func video(_ p: Pen) {
        page(p)
        p.fill(rr(8, 11, 16, 15, 1), 0x3C3C3C, 0x3C3C3C)
        var x: CGFloat = 9.3
        while x < 23 {
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: x, y: 12.2, width: 1.4, height: 1.4)).fill()
            NSBezierPath(rect: NSRect(x: x, y: 23.4, width: 1.4, height: 1.4)).fill()
            x += 3
        }
        p.fill(NSBezierPath(rect: NSRect(x: 9.5, y: 15, width: 13, height: 7)), 0x3AA0F0, 0x1E7FD6)
        NSColor.white.setFill()
        poly([(14.3, 16.3), (14.3, 20.7), (18.3, 18.5)]).fill()
    }

    private static func archive(_ p: Pen) {
        folder(p, paper: .none)
        p.fill(NSBezierPath(rect: NSRect(x: 14.6, y: 11.5, width: 2.8, height: 14.5)), 0x5A5A5A, 0x5A5A5A)
        var y: CGFloat = 16.5
        var left = true
        while y < 25.5 {
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: left ? 14.6 : 16, y: y, width: 1.4, height: 1)).fill()
            y += 1.6
            left.toggle()
        }
        p.fill(rr(13.6, 11.5, 4.8, 4.5, 1), 0x7A7A7A, 0x5A5A5A)
    }

    private static func pdf(_ p: Pen) {
        page(p)
        textLines(p, color: 0xC4C4C4, from: 11)
        p.fill(NSBezierPath(rect: NSRect(x: 6.4, y: 19.5, width: 19.2, height: 8)), 0xD13438, 0xD13438)
        if p.pixel <= 1.4 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 6.4), .foregroundColor: NSColor.white,
            ]
            let size = ("PDF" as NSString).size(withAttributes: attrs)
            ("PDF" as NSString).draw(at: NSPoint(x: 16 - size.width / 2, y: 23.5 - size.height / 2), withAttributes: attrs)
        }
    }

    private static func code(_ p: Pen) {
        page(p)
        p.line(line([(13, 14.5), (9.5, 18), (13, 21.5)]), accent, width: 1.8)
        p.line(line([(19, 14.5), (22.5, 18), (19, 21.5)]), accent, width: 1.8)
        p.line(line([(17.3, 13.5), (14.7, 22.5)]), 0x7A7A7A, width: 1.4)
    }

    private static func program(_ p: Pen) {
        let window = rr(3, 5, 26, 22, 1)
        p.fill(window, 0xFFFFFF, 0xF4F4F4)
        p.fill(NSBezierPath(rect: NSRect(x: 3, y: 5, width: 26, height: 5)), accent, accent)
        p.stroke(window, 0x6A6A6A, width: 0.8)
        for (i, w) in [12, 9, 11].enumerated() {
            let y = 15 + CGFloat(i) * 3.5
            p.line(line([(7, y), (7 + CGFloat(w), y)]), 0xB4B4B4, width: 1.3)
        }
    }

    // MARK: Тулбар

    /// Тонкая стрелка, как кнопки навигации Проводника Windows 10. angle: 0 — вправо, 180 — влево, -90 — вверх.
    private static func navArrow(_ p: Pen, angle: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 16, yBy: 16)
        transform.rotate(byDegrees: angle)
        transform.translateX(by: -16, yBy: -16)
        transform.concat()
        let shaft = line([(5, 16), (26, 16)])
        let head = line([(17.5, 7.5), (26, 16), (17.5, 24.5)])
        for path in [shaft, head] {
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            p.line(path, accent, width: 3)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func magnifier(_ p: Pen) {
        let handle = line([(19.5, 19.5), (27.5, 27.5)])
        handle.lineCapStyle = .round
        p.line(handle, ink, width: 3.6)
        let lens = oval(4, 4, 17, 17)
        p.fill(lens, 0xEAF4FD, 0xD6EAFB)
        p.line(lens, ink, width: 2.4)
    }

    private static func views(_ p: Pen) {
        for (x, y) in [(3, 3), (18, 3), (3, 18), (18, 18)] as [(CGFloat, CGFloat)] {
            p.fill(rr(x, y, 11, 11, 1), accent, accent)
        }
    }

    private static func go(_ p: Pen) {
        p.fill(rr(2, 2, 28, 28, 3), accent, accent)
        let shaft = line([(8, 16), (23, 16)])
        let head = line([(16.5, 9.5), (23, 16), (16.5, 22.5)])
        for path in [shaft, head] {
            path.lineCapStyle = .round
            p.line(path, 0xFFFFFF, width: 2.8)
        }
    }

    // MARK: Панель задач

    private enum BadgeSymbol { case plus, arrow }

    /// Круглый значок в правом нижнем углу (новая папка, переместить).
    private static func badge(_ p: Pen, color: UInt32, symbol: BadgeSymbol) {
        let circle = oval(17, 15.5, 14, 14)
        p.fill(circle, color, color)
        p.line(circle, 0xFFFFFF, width: 1.2)
        let paths: [NSBezierPath]
        switch symbol {
        case .plus:
            paths = [line([(24, 18.8), (24, 26.2)]), line([(20.3, 22.5), (27.7, 22.5)])]
        case .arrow:
            paths = [line([(20, 22.5), (27.5, 22.5)]), line([(24.2, 19), (27.7, 22.5), (24.2, 26)])]
        }
        for path in paths {
            path.lineCapStyle = .round
            p.line(path, 0xFFFFFF, width: 2)
        }
    }

    private static func copyTo(_ p: Pen) {
        page(p, dx: -3.5, dy: -1)
        page(p, dx: 3, dy: 1.5)
        textLines(p, color: 0xA6A6A6, from: 16)
    }

    private static func deleteCross(_ p: Pen) {
        for path in [line([(8, 8), (24, 24)]), line([(24, 8), (8, 24)])] {
            path.lineCapStyle = .round
            p.line(path, 0xE81123, width: 4.2)
        }
    }

    private static func rename(_ p: Pen) {
        page(p)
        textLines(p, color: 0xC4C4C4, from: 11)
        p.fill(NSBezierPath(rect: NSRect(x: 8.5, y: 17, width: 13.5, height: 4.5)), accent, accent)
        p.line(line([(23.5, 15.5), (23.5, 23)]), 0x000000, width: 1.1)
    }

    private static func info(_ p: Pen) {
        p.fill(oval(2, 2, 28, 28), accent, accent)
        NSColor.white.setFill()
        oval(14, 7, 4, 4).fill()
        rr(14.2, 13, 3.6, 12.5, 1).fill()
    }

    private static func gear(_ p: Pen) {
        let center = NSPoint(x: 16, y: 16)
        let gear = NSBezierPath()
        for i in 0..<8 {
            let tooth = NSBezierPath(roundedRect: NSRect(x: -2.6, y: -14, width: 5.2, height: 7), xRadius: 1, yRadius: 1)
            var transform = AffineTransform(translationByX: center.x, byY: center.y)
            transform.rotate(byDegrees: CGFloat(i) * 45)
            tooth.transform(using: transform)
            gear.append(tooth)
        }
        gear.append(NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 22, height: 22)))
        gear.windingRule = .nonZero
        p.fill(gear, 0x6B6B6B, 0x5A5A5A)
        p.fill(oval(11.5, 11.5, 9, 9), 0xFFFFFF, 0xFFFFFF)
    }

    /// Планшет с зажимом и листом — «Копировать путь».
    private static func clipboard(_ p: Pen) {
        p.fill(rr(4, 4, 24, 27, 2), 0xB7834A, 0xA0703A)
        p.fill(rr(7, 8, 18, 20, 0.5), 0xFFFFFF, 0xFFFFFF)
        textLines(p, color: 0x6AA6E8, from: 13)
        p.fill(rr(11, 1.5, 10, 6, 1.5), 0x7A7A7A, 0x5A5A5A)
    }

    // MARK: Геометрия

    private static func poly(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = line(points)
        path.close()
        return path
    }

    private static func line(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: points[0].0, y: points[0].1))
        for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }
        return path
    }

    private static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 0) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }

    private static func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h))
    }
}

/// Кисть с учётом размера пикселя: линии не тоньше одного физического пикселя.
private struct Pen {
    /// Размер одного пикселя устройства в единицах сетки 32×32.
    let pixel: CGFloat

    /// Вертикальный градиент сверху вниз (в перевёрнутых координатах minY — верх).
    /// Для плоской заливки передаются одинаковые цвета.
    func fill(_ path: NSBezierPath, _ top: UInt32, _ bottom: UInt32) {
        guard top != bottom else {
            NSColor(hex: top).setFill()
            path.fill()
            return
        }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let b = path.bounds
        NSGradient(starting: NSColor(hex: top), ending: NSColor(hex: bottom))?.draw(
            from: NSPoint(x: b.midX, y: b.minY), to: NSPoint(x: b.midX, y: b.maxY),
            options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Тонкая обводка контура.
    func stroke(_ path: NSBezierPath, _ color: UInt32, width: CGFloat = 1) {
        line(path, color, width: width)
    }

    /// Линия заданной толщины, но не тоньше одного пикселя.
    func line(_ path: NSBezierPath, _ color: UInt32, width: CGFloat) {
        NSColor(hex: color).setStroke()
        path.lineWidth = max(width, pixel)
        path.stroke()
    }
}
