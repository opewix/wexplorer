import AppKit

/// «Извлечь» для подключённых томов: образов dmg, флешек, внешних и сетевых дисков.
enum VolumeEject {
    /// Том можно извлечь: это корень тома, но не загрузочный диск и не встроенный накопитель.
    static func canEject(_ url: URL) -> Bool {
        guard url.path != "/" else { return false }
        let keys: Set<URLResourceKey> = [.isVolumeKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isVolume == true else { return false }
        return values.volumeIsEjectable == true || values.volumeIsRemovable == true || values.volumeIsInternal != true
    }

    /// Извлекает тома по очереди, не занимая окно: занятый диск отвечает не сразу. Об отказе — сообщение.
    static func eject(_ urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async {
            for url in urls {
                let name = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? url.lastPathComponent
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                } catch {
                    DispatchQueue.main.async { Alerts.error(tr(.ejectFailed, name), info: error.localizedDescription) }
                }
            }
        }
    }
}
