import Foundation

/// Метод сжатия и допустимые для него размеры словаря и слова.
enum SevenZipMethod: String {
    case lzma2 = "LZMA2", lzma = "LZMA", ppmd = "PPMd", bzip2 = "BZip2", deflate = "Deflate", deflate64 = "Deflate64"

    private static let kb: Int64 = 1024
    private static let mb: Int64 = 1024 * 1024

    /// Размеры, которые поместятся в память: большой словарь 7-Zip просто не смог бы выделить.
    func dictionaries(in format: SevenZipFormat,
                      physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> [Int64] {
        let memory = Int64(clamping: physicalMemory)
        switch self {
        case .lzma, .lzma2:
            let sizes = [64 * Self.kb] + [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536]
                .map { $0 * Self.mb }
            return sizes.filter { $0 * 12 <= memory }
        case .ppmd:
            let sizes = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2047]
                .map { $0 * Self.mb }
            // Формат zip не принимает для PPMd больше 256 МБ.
            let limit = format == .zip ? 256 * Self.mb : Int64.max
            return sizes.filter { $0 * 2 <= memory && $0 <= limit }
        case .bzip2:
            return (1...9).map { $0 * 100 * Self.kb }
        case .deflate, .deflate64:
            return []
        }
    }

    /// У Deflate словарь задан самим форматом: его можно показать, но нельзя изменить.
    var fixedDictionary: Int64? {
        switch self {
        case .deflate: return 32 * Self.kb
        case .deflate64: return 64 * Self.kb
        default: return nil
        }
    }

    /// Для LZMA и Deflate это длина совпадения, для PPMd — порядок модели. У BZip2 такого параметра нет.
    func wordSizes(in format: SevenZipFormat) -> [Int] {
        switch self {
        case .lzma, .lzma2: return [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 273]
        case .ppmd:
            // Формат zip не принимает для PPMd порядок больше 16.
            let orders = [2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 32]
            return format == .zip ? orders.filter { $0 <= 16 } : orders
        case .deflate: return [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 258]
        case .deflate64: return [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 257]
        case .bzip2: return []
        }
    }
}

enum SevenZipFormat: String, CaseIterable {
    case sevenZ = "7z", zip, gzip, bzip2, xz, tar, wim

    var fileExtension: String {
        switch self {
        case .gzip: return "gz"
        case .bzip2: return "bz2"
        default: return rawValue
        }
    }

    /// gzip, bzip2 и xz сжимают только один файл: на нескольких 7-Zip отвечает ошибкой.
    var onlySingleFile: Bool {
        self == .gzip || self == .bzip2 || self == .xz
    }

    /// tar и wim только упаковывают, поэтому уровня сжатия у них нет.
    var levels: [Int] {
        switch self {
        case .sevenZ, .zip: return [0, 1, 3, 5, 7, 9]
        case .gzip: return [1, 5, 7, 9]
        case .bzip2, .xz: return [1, 3, 5, 7, 9]
        case .tar, .wim: return []
        }
    }

    var methods: [SevenZipMethod] {
        switch self {
        case .sevenZ: return [.lzma2, .lzma, .ppmd, .bzip2]
        case .zip: return [.deflate, .deflate64, .bzip2, .lzma, .ppmd]
        case .gzip: return [.deflate]
        case .bzip2: return [.bzip2]
        case .xz: return [.lzma2]
        case .tar, .wim: return []
        }
    }

    var supportsSolid: Bool { self == .sevenZ }
    var supportsThreads: Bool { self == .sevenZ || self == .zip || self == .bzip2 || self == .xz }
    var supportsPassword: Bool { self == .sevenZ || self == .zip }
    var supportsEncryptedNames: Bool { self == .sevenZ }
}

enum SevenZipUpdateMode: String, CaseIterable {
    case addAndReplace = "-up1q1r2x2y2z2w2"
    case updateAndAdd = "-up1q1r2x1y2z1w2"
    case freshen = "-up1q1r0x1y2z1w2"
    case synchronize = "-up1q0r2x1y2z1w2"
}

enum SevenZipPathMode: CaseIterable {
    case relative, full, absolute
}

enum SevenZipZipEncryption: String, CaseIterable {
    case zipCrypto = "ZipCrypto", aes256 = "AES256"
}

/// Настройки окна «Добавить к архиву» и их перевод в параметры 7zz.
struct SevenZipAddOptions {
    var format: SevenZipFormat = .sevenZ
    var level = 5
    var method: SevenZipMethod?
    /// nil здесь и ниже — значение по умолчанию для выбранного уровня.
    var dictionary: Int64?
    var wordSize: Int?
    /// Значение -ms: «off», «on» или размер блока вроде «16m».
    var solid: String?
    var threads: Int?
    /// Размер тома как значение -v: «100m».
    var volumeSize: String?
    /// Поле «Параметры»: свойства через пробел, например «qs=on».
    var parameters = ""
    var updateMode: SevenZipUpdateMode = .addAndReplace
    var pathMode: SevenZipPathMode = .relative
    var password = ""
    var zipEncryption: SevenZipZipEncryption = .zipCrypto
    var encryptNames = false

    /// Пароль в аргументы не попадает: 7-Zip читает его из stdin.
    func arguments(sources: [URL], archive: URL) -> [String] {
        var result = ["a", "-t\(format.rawValue)", "-bd", "-y", "-snl", "-spd", "-xr!.DS_Store", updateMode.rawValue]
        if !format.levels.isEmpty {
            result.append("-mx=\(level)")
        }
        if level > 0 || format.levels.isEmpty {
            result += compressionArguments
        }
        if let threads, format.supportsThreads { result.append("-mmt=\(threads)") }
        if let volumeSize { result.append("-v\(volumeSize)") }
        result += parameters.split(whereSeparator: \.isWhitespace).map { "-m\($0)" }
        if !password.isEmpty && format.supportsPassword {
            result.append("-p")
            if format == .zip { result.append("-mem=\(zipEncryption.rawValue)") }
            if encryptNames && format.supportsEncryptedNames { result.append("-mhe=on") }
        }
        switch pathMode {
        case .relative: break
        case .full: result.append("-spf2")
        case .absolute: result.append("-spf")
        }
        result += ["--", archive.path]
        // Префикс «./» не даёт принять имена вроде «@list» или «-x» за параметры 7-Zip.
        result += sources.map { pathMode == .relative ? "./" + $0.lastPathComponent : $0.path }
        return result
    }

    private var compressionArguments: [String] {
        var result: [String] = []
        switch format {
        case .sevenZ:
            let chosen = method ?? .lzma2
            var value = "-m0=\(chosen.rawValue)"
            if let dictionary {
                value += ":\(chosen == .ppmd ? "mem" : "d")=\(Self.sizeValue(dictionary))"
            }
            if let wordSize { value += ":\(chosen == .ppmd ? "o" : "fb")=\(wordSize)" }
            result.append(value)
            if let solid { result.append("-ms=\(solid)") }
        case .zip:
            let chosen = method ?? .deflate
            result.append("-mm=\(chosen.rawValue)")
            if let dictionary { result.append("-m\(chosen == .ppmd ? "mem" : "d")=\(Self.sizeValue(dictionary))") }
            if let wordSize { result.append("-m\(chosen == .ppmd ? "o" : "fb")=\(wordSize)") }
        case .gzip, .xz, .bzip2:
            if let dictionary { result.append("-md=\(Self.sizeValue(dictionary))") }
            if let wordSize { result.append("-mfb=\(wordSize)") }
        case .tar, .wim:
            break
        }
        return result
    }

    private static func sizeValue(_ bytes: Int64) -> String {
        bytes % (1024 * 1024) == 0 ? "\(bytes / (1024 * 1024))m" : "\(bytes / 1024)k"
    }

    // MARK: Проверка ввода

    /// «650M - CD» → «650m». nil — размер записан неверно, пустая строка — разбивка не нужна.
    static func volumeSwitch(from text: String) -> String? {
        let value = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if value.isEmpty { return "" }
        let digits = value.prefix { $0.isASCII && $0.isNumber }
        let unit = value.dropFirst(digits.count).lowercased()
        guard let number = Int64(digits), number > 0, unit.isEmpty || ["b", "k", "m", "g"].contains(unit) else {
            return nil
        }
        return "\(number)\(unit)"
    }

    /// В zip 7-Zip принимает только пароль из латиницы, цифр и знаков.
    static func isValidZipPassword(_ password: String) -> Bool {
        password.allSatisfy(\.isASCII)
    }
}
