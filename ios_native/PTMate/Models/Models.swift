import Foundation
import CoreFoundation

enum ModelsError: Error {
    case formatException(String)
    case argumentException(String)
    case typeMismatch(String)
}

extension ModelsError: CustomStringConvertible {
    var description: String {
        switch self {
        case .formatException(let message):
            return "FormatException: \(message)"
        case .argumentException(let message):
            return "Invalid argument(s): \(message)"
        case .typeMismatch(let message):
            return message
        }
    }
}

struct JSONValue {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}

extension JSONValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([JSONValue].self) {
            value = array.map { $0.value }
        } else if let map = try? container.decode([String: JSONValue].self) {
            value = map.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }
}

extension JSONValue: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value is NSNull {
            try container.encodeNil()
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                try container.encode(number.boolValue)
            } else if dartIsFloatNumber(number) {
                try container.encode(number.doubleValue)
            } else {
                try container.encode(number.int64Value)
            }
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            try container.encode(array.map { JSONValue($0) })
        } else if let map = value as? [String: Any] {
            try container.encode(map.mapValues { JSONValue($0) })
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Unsupported JSON value"
                )
            )
        }
    }
}

extension KeyedDecodingContainer {
    func jsonMap() throws -> [String: Any] {
        var result: [String: Any] = [:]
        for key in allKeys {
            let decoded = try decode(JSONValue.self, forKey: key)
            result[key.stringValue] = decoded.value
        }
        return result
    }
}

extension Dictionary where Key == String, Value == Any {
    func firstValue(_ keys: String...) -> Any? {
        firstValue(keys)
    }

    func firstValue(_ keys: [String]) -> Any? {
        for key in keys {
            if let value = self[key], !(value is NSNull) {
                return value
            }
        }
        return nil
    }

    func lenientString(_ keys: String...) -> String? {
        lenientString(keys)
    }

    func lenientString(_ keys: [String]) -> String? {
        for key in keys {
            if let value = firstValue(key) {
                return dartToString(value)
            }
        }
        return nil
    }

    func coalesceBool(_ keys: String..., default defaultValue: Bool) throws -> Bool {
        for key in keys {
            if let value = firstValue(key) {
                guard let bool = strictBool(value) else {
                    throw typeMismatchError("bool", value)
                }
                return bool
            }
        }
        return defaultValue
    }
}

enum JSONCast {
    static func string(_ value: Any?) throws -> String {
        guard let value, !(value is NSNull) else {
            throw typeMismatchError("String", nil)
        }
        guard let string = value as? String else {
            throw typeMismatchError("String", value)
        }
        return string
    }

    static func optionalString(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String else {
            throw typeMismatchError("String", value)
        }
        return string
    }

    static func int(_ value: Any?) throws -> Int {
        guard let value, !(value is NSNull) else {
            throw typeMismatchError("int", nil)
        }
        guard let int = strictIntValue(value) else {
            throw typeMismatchError("int", value)
        }
        return int
    }

    static func optionalInt(_ value: Any?) throws -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        guard let int = strictIntValue(value) else {
            throw typeMismatchError("int", value)
        }
        return int
    }

    static func bool(_ value: Any?) throws -> Bool {
        guard let value, !(value is NSNull) else {
            throw typeMismatchError("bool", nil)
        }
        guard let bool = strictBool(value) else {
            throw typeMismatchError("bool", value)
        }
        return bool
    }

    static func optionalBool(_ value: Any?) throws -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        guard let bool = strictBool(value) else {
            throw typeMismatchError("bool", value)
        }
        return bool
    }

    static func num(_ value: Any?) throws -> Double {
        guard let value, !(value is NSNull) else {
            throw typeMismatchError("num", nil)
        }
        guard let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            throw typeMismatchError("num", value)
        }
        return number.doubleValue
    }

    static func list(_ value: Any?) throws -> [Any] {
        guard let value, !(value is NSNull) else {
            throw typeMismatchError("List<dynamic>", nil)
        }
        guard let array = value as? [Any] else {
            throw typeMismatchError("List<dynamic>", value)
        }
        return array
    }

    static func optionalList(_ value: Any?) throws -> [Any]? {
        guard let value, !(value is NSNull) else { return nil }
        return try list(value)
    }

    static func map(_ value: Any?) throws -> [String: Any] {
        guard let value, !(value is NSNull) else {
            throw typeMismatchError("Map<String, dynamic>", nil)
        }
        guard let map = value as? [String: Any] else {
            throw typeMismatchError("Map<String, dynamic>", value)
        }
        return map
    }

    static func optionalMap(_ value: Any?) throws -> [String: Any]? {
        guard let value, !(value is NSNull) else { return nil }
        return try map(value)
    }

    static func stringList(_ value: Any?) throws -> [String] {
        try list(value).map { try string($0) }
    }
}

func typeMismatchError(_ expected: String, _ value: Any?) -> ModelsError {
    .typeMismatch(
        "type '\(dartDynamicTypeName(value))' is not a subtype of type '\(expected)' in type cast"
    )
}

func dartDynamicTypeName(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "Null" }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return "bool" }
        return dartIsFloatNumber(number) ? "double" : "int"
    }
    if value is String { return "String" }
    if value is [Any] { return "List<dynamic>" }
    if value is [String: Any] { return "Map<String, dynamic>" }
    return String(describing: type(of: value))
}

func dartIsFloatNumber(_ number: NSNumber) -> Bool {
    let objCType = String(cString: number.objCType)
    return objCType == "f" || objCType == "d"
}

func strictBool(_ value: Any?) -> Bool? {
    guard let value, !(value is NSNull) else { return nil }
    if let number = value as? NSNumber {
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    if let bool = value as? Bool { return bool }
    return nil
}

func strictIntValue(_ value: Any?) -> Int? {
    guard let value, !(value is NSNull) else { return nil }
    if let number = value as? NSNumber {
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        guard !dartIsFloatNumber(number) else { return nil }
        return Int(number.int64Value)
    }
    return nil
}

func dartToString(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "null" }
    if let string = value as? String { return string }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        if dartIsFloatNumber(number) {
            return String(number.doubleValue)
        }
        return String(number.int64Value)
    }
    if let array = value as? [Any] {
        return "[" + array.map { dartToString($0) }.joined(separator: ", ") + "]"
    }
    if let map = value as? [String: Any] {
        let pairs = map.map { "\(dartToString($0.key)): \(dartToString($0.value))" }
        return "{" + pairs.joined(separator: ", ") + "}"
    }
    return String(describing: value)
}

func dartBoolFromLooseJSON(_ value: Any?) -> Bool {
    if let bool = strictBool(value) { return bool }
    if let string = value as? String, string == "true" { return true }
    return false
}

func dartParseInt(_ value: Any?) -> Int? {
    guard let value, !(value is NSNull) else { return nil }
    var str = dartToString(value)
    if str.isEmpty { return nil }
    if let dotIndex = str.firstIndex(of: ".") {
        str = String(str[..<dotIndex])
    }
    let digits = str.filter { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty else { return nil }
    return Int(digits)
}

func dartDoubleFromString(_ string: String) -> Double? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    switch trimmed {
    case "NaN", "+NaN", "-NaN":
        return .nan
    case "Infinity", "+Infinity":
        return .infinity
    case "-Infinity":
        return -.infinity
    default:
        break
    }
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    guard DartDateSupport.doublePattern.firstMatch(in: trimmed, range: range) != nil else {
        return nil
    }
    var sign = ""
    var body = trimmed
    if body.hasPrefix("+") {
        body.removeFirst()
    } else if body.hasPrefix("-") {
        sign = "-"
        body.removeFirst()
    }
    var exponent = ""
    if let exponentIndex = body.firstIndex(where: { $0 == "e" || $0 == "E" }) {
        exponent = String(body[exponentIndex...])
        body = String(body[..<exponentIndex])
    }
    if body.hasPrefix(".") {
        body = "0" + body
    }
    if body.hasSuffix(".") {
        body = body + "0"
    }
    if let value = Double(sign + body + exponent) {
        return value
    }
    return sign == "-" ? -.infinity : .infinity
}

func dartLenientDouble(_ value: Any?) -> Double {
    guard let value, !(value is NSNull) else { return 0.0 }
    if let number = value as? NSNumber {
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0.0 }
        return number.doubleValue
    }
    if let string = value as? String {
        return dartDoubleFromString(string) ?? 0.0
    }
    return 0.0
}

func dartDoubleToInt(_ value: Double) throws -> Int {
    guard value.isFinite else {
        throw ModelsError.typeMismatch("Unsupported operation: Infinity or NaN toInt")
    }
    if value >= 9_223_372_036_854_775_808.0 {
        return Int.max
    }
    if value <= -9_223_372_036_854_775_808.0 {
        return Int.min
    }
    return Int(value)
}

func dartLenientInt(_ value: Any?) throws -> Int {
    guard let value, !(value is NSNull) else { return 0 }
    if let number = value as? NSNumber {
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return dartParseInt(value) ?? 0
        }
        if dartIsFloatNumber(number) {
            return try dartDoubleToInt(number.doubleValue)
        }
        return Int(number.int64Value)
    }
    return dartParseInt(value) ?? 0
}

func dartParseDateTime(_ string: String) throws -> Date {
    let range = NSRange(string.startIndex..., in: string)
    guard let match = DartDateSupport.isoPattern.firstMatch(in: string, range: range) else {
        throw ModelsError.formatException("Invalid date format: \(string)")
    }
    func group(_ index: Int) -> String? {
        let groupRange = match.range(at: index)
        guard groupRange.location != NSNotFound,
            let swiftRange = Range(groupRange, in: string)
        else {
            return nil
        }
        return String(string[swiftRange])
    }
    guard let yearText = group(1), let monthText = group(2), let dayText = group(3),
        let year = Int(yearText), let month = Int(monthText), let day = Int(dayText)
    else {
        throw ModelsError.formatException("Invalid date format: \(string)")
    }
    let hour = group(4).flatMap { Int($0) } ?? 0
    var minute = group(5).flatMap { Int($0) } ?? 0
    let second = group(6).flatMap { Int($0) } ?? 0
    var millisecond = 0
    var microsecond = 0
    if let fraction = group(7) {
        var combined = 0
        for index in 0..<6 {
            combined *= 10
            if index < fraction.count {
                let digitIndex = fraction.index(fraction.startIndex, offsetBy: index)
                combined += Int(fraction[digitIndex].asciiValue! &- 48)
            }
        }
        millisecond = combined / 1000
        microsecond = combined % 1000
    }
    var isUTC = false
    if group(8) != nil {
        isUTC = true
        if let sign = group(9) {
            let signValue = sign == "-" ? -1 : 1
            guard let offsetHour = group(10).flatMap({ Int($0) }) else {
                throw ModelsError.formatException("Invalid date format: \(string)")
            }
            let offsetMinute = group(11).flatMap { Int($0) } ?? 0
            minute -= signValue * (60 * offsetHour + offsetMinute)
        }
    }
    var calendar = Calendar(identifier: .gregorian)
    #if canImport(Darwin)
    (calendar as NSCalendar).isLenient = true
    #endif
    calendar.timeZone = isUTC ? TimeZone(secondsFromGMT: 0)! : .current
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    components.nanosecond = millisecond * 1_000_000 + microsecond * 1000
    guard let date = calendar.date(from: components) else {
        throw ModelsError.formatException("Time out of range: \(string)")
    }
    let micros = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    let millis = micros >= 0 ? micros / 1000 : (micros - 999) / 1000
    let microsInMilli = micros - millis * 1000
    let maxMillis: Int64 = 8_640_000_000_000_000
    guard millis.magnitude <= maxMillis else {
        throw ModelsError.formatException("Time out of range: \(string)")
    }
    if millis.magnitude == maxMillis, microsInMilli != 0 {
        throw ModelsError.formatException("Time out of range: \(string)")
    }
    return date
}

func parseDateTimeCustom(
    _ dateStr: String?,
    format: String? = nil,
    zone: String? = nil,
    fieldName: String? = nil
) throws -> Date {
    guard let dateStr, !dateStr.isEmpty else { return Date() }
    do {
        let actualZone = zone ?? "+08:00"
        if let format, !format.isEmpty {
            let parsed = try dartDateFormatParse(
                format,
                dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return try dartParseDateTime(parsed + actualZone)
        }
        var normalized = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
        var units = Array(normalized.utf16)
        if units.count >= 19, units[10] == 32 {
            units[10] = 84
            normalized = String(utf16CodeUnits: units, count: units.count)
        }
        if normalized.range(
            of: "Z|[+-][0-9]{2}:?[0-9]{2}\\z",
            options: .regularExpression
        ) != nil {
            return try dartParseDateTime(normalized)
        }
        return try dartParseDateTime(normalized + actualZone)
    } catch {
        do {
            return try dartParseDateTime(dateStr)
        } catch {
            let field = fieldName ?? "unknown"
            var message = "字段 \(field) 时间解析失败，原始字符串: \"\(dateStr)\""
            if let format {
                message += "，解析时间格式: \"\(format)\""
            }
            throw ModelsError.formatException(message)
        }
    }
}

private func dartDateFormatParse(_ pattern: String, _ input: String) throws -> String {
    var tokens: [(String, String?)] = []
    var index = pattern.startIndex
    while index < pattern.endIndex {
        let character = pattern[index]
        guard character.isASCII, character.isLetter else {
            if let last = tokens.last, last.1 != nil {
                tokens[tokens.count - 1].1!.append(character)
            } else {
                tokens.append(("", String(character)))
            }
            index = pattern.index(after: index)
            continue
        }
        var run = String(character)
        var scan = pattern.index(after: index)
        while scan < pattern.endIndex, pattern[scan] == character {
            run.append(pattern[scan])
            scan = pattern.index(after: scan)
        }
        let token: String
        switch character {
        case "y":
            switch run.count {
            case 4: token = "yyyy"
            case 2: token = "yy"
            default:
                throw ModelsError.formatException("Unsupported date format token: \(run)")
            }
        case "M":
            switch run.count {
            case 3: token = "MMM"
            case 2: token = "MM"
            case 1: token = "M"
            default:
                throw ModelsError.formatException("Unsupported date format token: \(run)")
            }
        case "d":
            switch run.count {
            case 2: token = "dd"
            case 1: token = "d"
            default:
                throw ModelsError.formatException("Unsupported date format token: \(run)")
            }
        case "H":
            switch run.count {
            case 2: token = "HH"
            case 1: token = "H"
            default:
                throw ModelsError.formatException("Unsupported date format token: \(run)")
            }
        case "m":
            switch run.count {
            case 2: token = "mm"
            case 1: token = "m"
            default:
                throw ModelsError.formatException("Unsupported date format token: \(run)")
            }
        case "s":
            switch run.count {
            case 2: token = "ss"
            case 1: token = "s"
            default:
                throw ModelsError.formatException("Unsupported date format token: \(run)")
            }
        default:
            throw ModelsError.formatException("Unsupported date format token: \(run)")
        }
        tokens.append((token, nil))
        index = scan
    }

    var year = 1970
    var month = 1
    var day = 1
    var hour = 0
    var minute = 0
    var second = 0
    var position = input.startIndex

    func readDigits(_ count: Int, _ token: String) throws -> Int {
        var result = ""
        var remaining = count
        while remaining > 0, position < input.endIndex,
            input[position].isASCII, input[position].isNumber
        {
            result.append(input[position])
            position = input.index(after: position)
            remaining -= 1
        }
        guard remaining == 0, let value = Int(result), result.count == count else {
            throw ModelsError.formatException(
                "Failed to parse date \"\(input)\" using format \"\(pattern)\" at token \(token)"
            )
        }
        return value
    }

    func readDigitsFlexible(_ token: String) throws -> Int {
        var result = ""
        while position < input.endIndex, input[position].isASCII, input[position].isNumber,
            result.count < 4
        {
            result.append(input[position])
            position = input.index(after: position)
        }
        guard !result.isEmpty, let value = Int(result) else {
            throw ModelsError.formatException(
                "Failed to parse date \"\(input)\" using format \"\(pattern)\" at token \(token)"
            )
        }
        return value
    }

    for (token, literal) in tokens {
        if let literal {
            guard position < input.endIndex,
                input[position...].hasPrefix(literal)
            else {
                throw ModelsError.formatException(
                    "Failed to parse date \"\(input)\" using format \"\(pattern)\" at literal \"\(literal)\""
                )
            }
            position = input.index(position, offsetBy: literal.count)
            continue
        }
        switch token {
        case "yyyy":
            year = try readDigits(4, token)
        case "yy":
            year = 2000 + (try readDigits(2, token))
        case "MMM":
            let start = position
            while position < input.endIndex, input[position].isLetter {
                position = input.index(after: position)
            }
            let name = String(input[start..<position])
            guard let monthNumber = DartDateSupport.monthNumbers[name.lowercased()] else {
                throw ModelsError.formatException(
                    "Failed to parse date \"\(input)\" using format \"\(pattern)\" at token MMM"
                )
            }
            month = monthNumber
        case "MM":
            month = try readDigits(2, token)
        case "M":
            month = try readDigitsFlexible(token)
        case "dd":
            day = try readDigits(2, token)
        case "d":
            day = try readDigitsFlexible(token)
        case "HH":
            hour = try readDigits(2, token)
        case "H":
            hour = try readDigitsFlexible(token)
        case "mm":
            minute = try readDigits(2, token)
        case "m":
            minute = try readDigitsFlexible(token)
        case "ss":
            second = try readDigits(2, token)
        case "s":
            second = try readDigitsFlexible(token)
        default:
            throw ModelsError.formatException("Unsupported date format token: \(token)")
        }
    }
    return String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d",
        year,
        month,
        day,
        hour,
        minute,
        second
    )
}

func dartToIso8601String(_ date: Date) -> String {
    let micros = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    let floorMillis = micros >= 0 ? micros / 1000 : (micros - 999) / 1000
    let microsInMilli = Int(micros - floorMillis * 1000)
    let base = Date(timeIntervalSince1970: Double(floorMillis) / 1000.0)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let units = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: base
    )
    let year = units.year ?? 1970
    let yearString: String
    if year >= -9999 && year <= 9999 {
        yearString = dartFourDigits(year)
    } else {
        yearString = dartSixDigits(year)
    }
    let millisInSecond = ((floorMillis % 1000) + 1000) % 1000
    let microsString = microsInMilli == 0 ? "" : dartThreeDigits(microsInMilli)
    return "\(yearString)-\(dartTwoDigits(units.month ?? 0))-\(dartTwoDigits(units.day ?? 0))"
        + "T\(dartTwoDigits(units.hour ?? 0)):\(dartTwoDigits(units.minute ?? 0))"
        + ":\(dartTwoDigits(units.second ?? 0)).\(dartThreeDigits(Int(millisInSecond)))\(microsString)"
}

private func dartFourDigits(_ value: Int) -> String {
    let absValue = abs(value)
    let sign = value < 0 ? "-" : ""
    if absValue >= 1000 { return String(value) }
    if absValue >= 100 { return "\(sign)0\(absValue)" }
    if absValue >= 10 { return "\(sign)00\(absValue)" }
    return "\(sign)000\(absValue)"
}

private func dartSixDigits(_ value: Int) -> String {
    let absValue = abs(value)
    let sign = value < 0 ? "-" : "+"
    if absValue >= 100_000 { return "\(sign)\(absValue)" }
    return "\(sign)0\(absValue)"
}

private func dartThreeDigits(_ value: Int) -> String {
    if value >= 100 { return String(value) }
    if value >= 10 { return "0\(value)" }
    return "00\(value)"
}

private func dartTwoDigits(_ value: Int) -> String {
    if value >= 10 { return String(value) }
    return "0\(value)"
}

func jsonEncodeString(_ object: [String: Any]) -> String {
    guard JSONSerialization.isValidJSONObject(object),
        let data = try? JSONSerialization.data(withJSONObject: object),
        let string = String(data: data, encoding: .utf8)
    else {
        return String(describing: object)
    }
    return string
}

func legacyIdentifier() -> String {
    "legacy-\(Int64((Date().timeIntervalSince1970 * 1000).rounded()))"
}

func anyOrNil<T>(_ value: T?) -> Any {
    guard let value else { return NSNull() }
    return value
}

enum DartDateSupport {
    static let doublePattern = try! NSRegularExpression(
        pattern: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"
    )

    static let isoPattern = try! NSRegularExpression(
        pattern:
            "^([+-]?[0-9]{4,6})-?([0-9][0-9])-?([0-9][0-9])(?:[ T]([0-9][0-9])(?::?([0-9][0-9])(?::?([0-9][0-9])(?:[.,]([0-9]+))?)?)?( ?[zZ]| ?([-+])([0-9][0-9])(?::?([0-9][0-9]))?)?)?$"
    )

    static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
        "january": 1, "february": 2, "march": 3, "april": 4,
        "june": 6, "july": 7, "august": 8, "september": 9,
        "october": 10, "november": 11, "december": 12,
    ]
}
