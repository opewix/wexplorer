import AppKit

/// Элемент коллекции для видов «Эскизы», «Плитка», «Значки», «Список».
final class IconItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("IconItem")

    private var cell: IconCellView { view as! IconCellView }

    override func loadView() {
        view = IconCellView()
    }

    override var isSelected: Bool {
        didSet { cell.isSelected = isSelected }
    }

    func configure(_ item: FileItem, mode: ViewMode, image: NSImage) {
        cell.item = item
        cell.mode = mode
        cell.image = image
        cell.isSelected = isSelected
    }

    func setImage(_ image: NSImage) {
        cell.image = image
    }
}

/// Рисует значок и подпись целиком сам — так проще повторить вид XP.
final class IconCellView: LunaView {
    var item: FileItem? { didSet { needsDisplay = true } }
    var mode: ViewMode = .icons { didSet { needsDisplay = true } }
    var image: NSImage? { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        let w = bounds.width, h = bounds.height
        switch mode {
        case .icons:
            drawImage(in: NSRect(x: (w - 32) / 2, y: 4, width: 32, height: 32))
            drawLabel(item.name, in: NSRect(x: 2, y: 40, width: w - 4, height: h - 40), lines: 2, centered: true)

        case .thumbnails:
            let frame = NSRect(x: (w - 104) / 2, y: 2, width: 104, height: 104)
            NSColor.white.setFill()
            frame.fill()
            let border = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = isSelected ? 2 : 1
            (isSelected ? Luna.selection : Luna.thumbBorder).setStroke()
            border.stroke()
            let isThumbnail = image != nil && image !== item.icon
            let target = isThumbnail
                ? frame.insetBy(dx: 5, dy: 5)
                : NSRect(x: frame.midX - 24, y: frame.midY - 24, width: 48, height: 48)
            drawImage(in: target, tint: false)
            drawLabel(item.name, in: NSRect(x: 2, y: 110, width: w - 4, height: h - 110), lines: 2, centered: true)

        case .tiles:
            drawImage(in: NSRect(x: 4, y: (h - 48) / 2, width: 48, height: 48))
            let x: CGFloat = 58
            let textWidth = w - x - 4
            drawLabel(item.name, in: NSRect(x: x, y: 6, width: textWidth, height: 16), lines: 1, centered: false)
            drawSecondary(item.typeName, in: NSRect(x: x, y: 22, width: textWidth, height: 14))
            drawSecondary(tileDetail(item), in: NSRect(x: x, y: 36, width: textWidth, height: 14))

        case .list:
            drawImage(in: NSRect(x: 2, y: 1, width: 16, height: 16))
            drawLabel(item.name, in: NSRect(x: 21, y: 2, width: w - 23, height: 15), lines: 1, centered: false)

        case .details:
            break
        }
    }

    private func tileDetail(_ item: FileItem) -> String {
        if item.isVolume { return item.detail ?? "" }
        if item.isDirectory { return "" }
        return item.size.map(Format.size) ?? ""
    }

    private func drawImage(in rect: NSRect, tint: Bool = true) {
        guard let image else { return }
        let target = LunaButton.fit(image.size, in: rect)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if isSelected && tint {
            Luna.selection.withAlphaComponent(0.45).setFill()
            target.fill(using: .sourceAtop)
        }
    }

    private func drawLabel(_ text: String, in rect: NSRect, lines: Int, centered: Bool) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        style.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Luna.font,
            .foregroundColor: isSelected ? Luna.selectionText : Luna.text,
            .paragraphStyle: style,
        ]
        let lineHeight = ceil(Luna.font.ascender - Luna.font.descender + Luna.font.leading)
        let maxSize = NSSize(width: rect.width, height: min(rect.height, lineHeight * CGFloat(lines)))
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let measured = (text as NSString).boundingRect(with: maxSize, options: options, attributes: attrs)
        let width = min(ceil(measured.width), rect.width)
        let height = min(ceil(measured.height), maxSize.height)
        let textRect = NSRect(x: centered ? rect.midX - width / 2 : rect.minX, y: rect.minY, width: width, height: height)
        if isSelected {
            Luna.selection.setFill()
            textRect.insetBy(dx: -2, dy: 0).fill()
        }
        (text as NSString).draw(with: textRect, options: options, attributes: attrs)
    }

    private func drawSecondary(_ text: String, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: Luna.font, .foregroundColor: Luna.secondaryText, .paragraphStyle: style,
        ])
    }
}
