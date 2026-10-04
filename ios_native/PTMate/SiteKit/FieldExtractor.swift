import Foundation
import SwiftSoup

struct FieldExtractionResult {
    let first: ExtractedValue
    let allValues: [String]
}

struct FieldConfig {
    let selector: String?
    let attribute: String?
    let filter: [String: Any]?
    let defaultValue: Any?
    let required: Bool
    let value: String?
    let regexpFilter: NSRegularExpression?
    let filterFormat: String?
    private let json: [String: Any]

    init(
        selector: String? = nil,
        attribute: String? = nil,
        filter: [String: Any]? = nil,
        defaultValue: Any? = nil,
        required: Bool = false,
        value: String? = nil
    ) {
        self.selector = selector
        self.attribute = attribute
        self.filter = filter
        self.defaultValue = defaultValue
        self.required = required
        self.value = value
        var json: [String: Any] = [:]
        if let selector {
            json["selector"] = selector
        }
        if let attribute {
            json["attribute"] = attribute
        }
        if let filter {
            json["filter"] = filter
        }
        if let value {
            json["value"] = value
        }
        if let defaultValue {
            json["defaultValue"] = defaultValue
        }
        if required {
            json["required"] = true
        }
        self.json = json
        self.regexpFilter = FieldConfig.compileRegexpFilter(filter)
        self.filterFormat = filter?["value"] as? String
    }

    private init(
        raw: [String: Any],
        selector: String?,
        attribute: String?,
        filter: [String: Any]?,
        defaultValue: Any?,
        required: Bool,
        value: String?
    ) {
        self.selector = selector
        self.attribute = attribute
        self.filter = filter
        self.defaultValue = defaultValue
        self.required = required
        self.value = value
        self.json = raw
        self.regexpFilter = FieldConfig.compileRegexpFilter(filter)
        self.filterFormat = filter?["value"] as? String
    }

    static func fromJson(_ json: [String: Any]) -> FieldConfig {
        FieldConfig(
            raw: json,
            selector: json["selector"] as? String,
            attribute: json["attribute"] as? String,
            filter: json["filter"] as? [String: Any],
            defaultValue: json["defaultValue"],
            required: json["required"] as? Bool ?? false,
            value: json["value"] as? String
        )
    }

    func toJson() -> [String: Any] {
        json
    }

    var hasDefaultValue: Bool {
        if let defaultValue, !(defaultValue is NSNull) {
            return true
        }
        return false
    }

    var defaultValueString: String {
        dartToString(defaultValue)
    }

    var hasValue: Bool {
        guard let value else { return false }
        return !value.isEmpty
    }

    static func compileRegexpFilter(_ filter: [String: Any]?) -> NSRegularExpression? {
        guard let filter, filter["name"] as? String == "regexp" else { return nil }
        guard let args = filter["args"] as? String else { return nil }
        return try? NSRegularExpression(pattern: args)
    }
}

struct ExtractedValue {
    let raw: String?
    let found: Bool

    init(raw: String?, found: Bool) {
        self.raw = raw
        self.found = found
    }

    static func missing() -> ExtractedValue {
        ExtractedValue(raw: nil, found: false)
    }

    static func fromString(_ value: String?) -> ExtractedValue {
        guard let value, !value.isEmpty else {
            return ExtractedValue(raw: nil, found: false)
        }
        return ExtractedValue(raw: value, found: true)
    }

    var string: String? {
        raw
    }

    var stringOrEmpty: String {
        raw ?? ""
    }

    var intValue: Int? {
        guard let raw else { return nil }
        return dartParseInt(raw)
    }

    func intValueOr(_ defaultValue: Int) -> Int {
        intValue ?? defaultValue
    }

    var doubleValue: Double? {
        guard let raw else { return nil }
        return Double(raw.replacingOccurrences(of: ",", with: ""))
    }

    func parseDateTime(
        format: String? = nil,
        zone: String? = nil,
        fieldName: String? = nil
    ) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return try? parseDateTimeCustom(
            raw,
            format: format,
            zone: zone,
            fieldName: fieldName
        )
    }

    var hasValue: Bool {
        guard let raw else { return false }
        return found && !raw.isEmpty
    }

    var asBool: Bool {
        found
    }
}

enum TypedConverter {
    private static let sizeRegExp = try! NSRegularExpression(
        pattern: #"([\d.]+)\s*(\w+)"#
    )

    static func parseSizeToBytes(_ sizeText: String?) -> Int {
        guard let sizeText, !sizeText.isEmpty else { return 0 }
        let range = NSRange(sizeText.startIndex..., in: sizeText)
        guard let match = sizeRegExp.firstMatch(in: sizeText, options: [], range: range) else {
            return 0
        }
        let sizeValue = Double(groupText(match, 1, sizeText) ?? "0") ?? 0
        let unit = (groupText(match, 2, sizeText) ?? "B").uppercased()
        switch unit {
        case "KB", "KIB":
            return Int((sizeValue * 1024).rounded())
        case "MB", "MIB":
            return Int((sizeValue * 1024 * 1024).rounded())
        case "GB", "GIB":
            return Int((sizeValue * 1024 * 1024 * 1024).rounded())
        case "TB", "TIB":
            return Int((sizeValue * 1024 * 1024 * 1024 * 1024).rounded())
        default:
            return Int(sizeValue.rounded())
        }
    }

    static func parseDownloadStatus(_ text: String?) -> DownloadStatus {
        guard let text, !text.isEmpty else { return .none }
        guard let percentInt = dartParseInt(text) else { return .none }
        if percentInt == 100 {
            return .completed
        }
        return .downloading
    }

    static func parseDiscount(_ raw: String?, _ mapping: [String: String]) -> DiscountType {
        guard let raw, !raw.isEmpty else { return .normal }
        guard let enumValue = mapping[raw] else { return .normal }
        return DiscountType(rawValue: enumValue) ?? .normal
    }

    static func parseTagType(_ raw: String?, _ mapping: [String: String]) -> TagType? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let enumName = mapping[raw] else { return nil }
        for type in TagType.allCases {
            if type.rawValue.lowercased() == enumName.lowercased() {
                return type
            }
            if type.content == enumName {
                return type
            }
        }
        return nil
    }

    static func parseTags(
        _ torrentName: String,
        _ description: String,
        _ rawTagList: [String],
        _ mapping: [String: String]
    ) -> [TagType] {
        var tags = TagType.matchTags("\(torrentName) \(description)")
        for tagStr in rawTagList {
            if let mappedTag = parseTagType(tagStr, mapping), !tags.contains(mappedTag) {
                tags.append(mappedTag)
            }
        }
        return tags
    }

    static func resolveUrl(_ relativeUrl: String?, _ baseUrl: String) -> String {
        guard let relativeUrl, !relativeUrl.isEmpty else { return "" }
        if relativeUrl.hasPrefix("http") {
            return relativeUrl
        }
        var cleanBase = baseUrl
        if cleanBase.hasSuffix("/") {
            cleanBase.removeLast()
        }
        let separator = relativeUrl.hasPrefix("/") ? "" : "/"
        return cleanBase + separator + relativeUrl
    }

    static func resolveDownloadUrl(
        _ template: String,
        _ torrentId: String,
        _ passKey: String,
        _ baseUrl: String,
        userId: String? = nil
    ) -> String {
        var url = template
        url = url.replacingOccurrences(of: "{torrentId}", with: torrentId)
        url = url.replacingOccurrences(of: "{passKey}", with: passKey)
        if let userId {
            url = url.replacingOccurrences(of: "{userId}", with: userId)
        }
        var cleanBase = baseUrl
        if cleanBase.hasSuffix("/") {
            cleanBase.removeLast()
        }
        url = url.replacingOccurrences(of: "{baseUrl}", with: cleanBase)
        return url
    }
}

private let filterGroupRegExp = try! NSRegularExpression(pattern: #"\$(\d+)"#)

private func groupText(_ match: NSTextCheckingResult, _ index: Int, _ string: String) -> String? {
    let range = match.range(at: index)
    guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
    return String(string[swiftRange])
}

private func substituteFilterGroups(
    _ template: String,
    _ match: NSTextCheckingResult,
    _ input: String
) -> String {
    var result = ""
    var searchStart = template.startIndex
    while searchStart < template.endIndex {
        let searchRange = NSRange(searchStart..., in: template)
        guard let groupMatch = filterGroupRegExp.firstMatch(
            in: template,
            options: [],
            range: searchRange
        ), let fullRange = Range(groupMatch.range, in: template) else {
            break
        }
        result += template[searchStart..<fullRange.lowerBound]
        if let digitsRange = Range(groupMatch.range(at: 1), in: template),
           let groupIndex = Int(template[digitsRange])
        {
            if groupIndex <= match.numberOfRanges - 1 {
                let groupRange = match.range(at: groupIndex)
                if groupRange.location != NSNotFound,
                   let swiftGroupRange = Range(groupRange, in: input)
                {
                    result += input[swiftGroupRange]
                }
            } else {
                result += template[fullRange]
            }
        } else {
            result += template[fullRange]
        }
        searchStart = fullRange.upperBound
    }
    result += template[searchStart...]
    return result
}

private func applyCompiledFilter(_ value: String, _ config: FieldConfig) -> String? {
    guard let regex = config.regexpFilter else {
        guard let filter = config.filter else { return value }
        return applyFilter(value, filter)
    }
    let range = NSRange(value.startIndex..., in: value)
    guard let match = regex.firstMatch(in: value, options: [], range: range) else {
        return nil
    }
    let template = config.filterFormat ?? "$0"
    return substituteFilterGroups(template, match, value)
}

func applyFilter(_ value: String, _ filter: [String: Any]) -> String? {
    let filterName = filter["name"] as? String
    if filterName == "regexp" {
        let args = filter["args"] as? String
        let format = filter["value"] as? String
        if let args, let regex = SelectorEngine.cachedRegExp(args) {
            let range = NSRange(value.startIndex..., in: value)
            if let match = regex.firstMatch(in: value, options: [], range: range) {
                let template = format ?? "$0"
                return substituteFilterGroups(template, match, value)
            }
        }
    }
    return nil
}

func extractFieldValues(_ element: Node, _ config: FieldConfig) -> [String] {
    var targetElements: [Node] = [element]

    if let selector = config.selector, !selector.isEmpty {
        targetElements = SelectorEngine.findElementBySelector(element, selector)
    }

    if targetElements.isEmpty {
        return []
    }

    var values: [String] = []
    for targetElement in targetElements {
        let value: String?
        if config.attribute == "text" {
            value = SelectorEngine.dartText(targetElement).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if config.attribute == "href" {
            value = SelectorEngine.attributeValue(targetElement, "href")
        } else {
            value = SelectorEngine.attributeValue(targetElement, config.attribute ?? "text")
        }

        let filteredValue: String?
        if let value {
            filteredValue = applyCompiledFilter(value, config)
        } else {
            filteredValue = nil
        }

        if let finalValue = filteredValue, !finalValue.isEmpty {
            values.append(SelectorEngine.collapseWhitespace(finalValue))
        }
    }

    return values
}

func extractFieldResult(_ element: Node, _ config: FieldConfig) -> FieldExtractionResult {
    let values = extractFieldValues(element, config)
    if values.isEmpty {
        if config.hasDefaultValue {
            return FieldExtractionResult(
                first: ExtractedValue.fromString(config.defaultValueString),
                allValues: []
            )
        }
        return FieldExtractionResult(first: ExtractedValue.missing(), allValues: [])
    }
    return FieldExtractionResult(
        first: ExtractedValue.fromString(values[0]),
        allValues: values
    )
}

func extractField(_ element: Node, _ config: FieldConfig) -> ExtractedValue {
    extractFieldResult(element, config).first
}

func extractRowResults(
    _ element: Node,
    _ fields: [String: FieldConfig]
) -> [String: FieldExtractionResult] {
    var result: [String: FieldExtractionResult] = [:]
    for (key, config) in fields {
        result[key] = extractFieldResult(element, config)
    }
    return result
}

func parseFieldConfigs(_ fieldsConfig: [String: Any]?) -> [String: FieldConfig] {
    guard let fieldsConfig else { return [:] }
    var result: [String: FieldConfig] = [:]
    for (key, value) in fieldsConfig {
        guard let fieldJson = value as? [String: Any] else { continue }
        result[key] = FieldConfig.fromJson(fieldJson)
    }
    return result
}
