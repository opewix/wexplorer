import AppKit

/// Стандартная панель: Назад, Вперёд, Вверх | Поиск, Папки | Виды.
final class ToolbarView: GradientView {
    let back = LunaButton(title: tr(.back), symbol: nil)
    let forward = LunaButton(title: tr(.forward), symbol: nil)
    let up = LunaButton(title: tr(.up), symbol: nil)
    let search = LunaButton(title: tr(.search), symbol: nil)
    let folders = LunaButton(title: tr(.folders), symbol: nil)
    let views = LunaButton(title: tr(.views), symbol: nil)

    init() {
        super.init(start: Luna.toolbarTop, end: Luna.toolbarBottom)
        views.showsMenuArrow = true
        let icons: [(LunaButton, XPIcon)] = [
            (back, .back), (forward, .forward), (up, .up), (search, .search), (folders, .folder), (views, .views),
        ]
        for (button, icon) in icons { button.image = XPIcons.image(icon, size: 24) }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for item in [back, forward, up] { stack.addArrangedSubview(item) }
        stack.addArrangedSubview(Self.divider())
        for item in [search, folders] { stack.addArrangedSubview(item) }
        stack.addArrangedSubview(Self.divider())
        stack.addArrangedSubview(views)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func divider() -> NSView {
        let v = LunaView()
        v.wantsLayer = true
        v.layer?.backgroundColor = Luna.separator.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return v
    }
}
