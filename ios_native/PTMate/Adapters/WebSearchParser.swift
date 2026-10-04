import Foundation
import SwiftSoup

private struct WebSearchItems {
    let items: [TorrentItem]
    let candidateItemRows: Int
}

enum WebSearchParser {
    private static let positionalSelectorRegex = try! NSRegularExpression(
        pattern: "^@@(?:td|th):nth-child\\(\\d+\\)"
    )
    private static let columnSelectorRegex = try! NSRegularExpression(
        pattern: "\\b(td|th):nth-child\\((\\d+)\\)"
    )
    private static let torrentIdUrlRegex = try! NSRegularExpression(
        pattern: "[?&](?:torrentid|id)=(\\d+)"
    )
    private static let classTokenSeparator: CharacterSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ",[]"))

    static func parse(
        html: String,
        searchConfig: [String: Any],
        baseUrl: String,
        discountMapping: [String: String] = [:],
        tagMapping: [String: String] = [:]
    ) throws -> WebSearchParseResult {
        let soup = try SwiftSoup.parse(html)
        let parser = (searchConfig["parser"] as? String ?? "flatTable")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let parsedItems: WebSearchItems
        switch parser {
        case "flattable", "":
            parsedItems = try parseFlatTable(
                soup,
                searchConfig,
                baseUrl,
                discountMapping,
                tagMapping
            )
        case "gazellegrouped":
            parsedItems = try parseGazelleGrouped(
                soup,
                searchConfig,
                baseUrl,
                discountMapping,
                tagMapping
            )
        default:
            throw WebAdapterConfigurationException(
                message: "不支持的 Web 搜索解析器: \(dartToString(searchConfig["parser"]))"
            )
        }

        return WebSearchParseResult(
            items: parsedItems.items,
            totalPages: parseTotalPages(soup, searchConfig),
            candidateItemRows: parsedItems.candidateItemRows
        )
    }

    private static func parseFlatTable(
        _ soup: Node,
        _ config: [String: Any],
        _ baseUrl: String,
        _ discountMapping: [String: String],
        _ tagMapping: [String: String]
    ) throws -> WebSearchItems {
        let rows = try findRows(soup, config, required: true)
        let fields = mapValue(config["fields"])
        if fields.isEmpty {
            throw WebAdapterConfigurationException(message: "flatTable 缺少 infoFinder.search.fields 配置")
        }

        var items: [TorrentItem] = []
        for row in rows {
            let values = extractValues(row, fields)
            if let item = buildTorrentItem(
                values,
                fields,
                baseUrl,
                discountMapping,
                tagMapping
            ) {
                items.append(item)
            }
        }
        return WebSearchItems(items: items, candidateItemRows: rows.count)
    }

    private static func parseGazelleGrouped(
        _ soup: Node,
        _ config: [String: Any],
        _ baseUrl: String,
        _ discountMapping: [String: String],
        _ tagMapping: [String: String]
    ) throws -> WebSearchItems {
        let rows = try findRows(soup, config, required: true)
        let groupRows = findConfiguredRows(soup, config, "groupRows", "groupRow")
        let torrentRows = findConfiguredRows(soup, config, "torrentRows", "torrentRow")

        let groupFields = mapValue(config["groupFields"])
        let commonFields = mapValue(config["fields"])
        let childFields = mapValue(config["childFields"])
        let standaloneFields = mapValue(config["standaloneFields"])
        if commonFields.isEmpty && childFields.isEmpty && standaloneFields.isEmpty {
            throw WebAdapterConfigurationException(
                message: "gazelleGrouped 缺少 infoFinder.search.fields、childFields 或 standaloneFields 配置"
            )
        }

        let childOffset = asInt(config["childColumnOffset"]) ?? 0
        var currentGroup: [String: String] = [:]
        var items: [TorrentItem] = []
        var candidateItemRows = 0

        for row in rows {
            if containsRow(groupRows, row) || hasClass(row, "group_redline") {
                currentGroup = extractValues(row, groupFields)
                continue
            }

            let isChild = hasClass(row, "group_torrent_redline")
            let isStandalone = hasClass(row, "torrent_redline") || hasClass(row, "torrent")
            let isConfiguredTorrent = containsRow(torrentRows, row)
            if !isChild && !isStandalone && !isConfiguredTorrent { continue }
            candidateItemRows += 1

            var rowFields = commonFields
            if isChild {
                rowFields.merge(childFields) { _, child in child }
            } else if isStandalone {
                rowFields.merge(standaloneFields) { _, standalone in standalone }
            }
            let normalizedFields = isChild && childOffset > 0
                ? shiftColumnFields(rowFields, childOffset)
                : rowFields
            let rowValues = extractValues(row, normalizedFields)
            let inherited = isChild ? currentGroup : [:]
            let values = mergeNonEmpty(inherited, rowValues)
            if let item = buildTorrentItem(
                values,
                normalizedFields,
                baseUrl,
                discountMapping,
                tagMapping
            ) {
                items.append(item)
            }
        }
        return WebSearchItems(items: items, candidateItemRows: candidateItemRows)
    }

    private static func findRows(
        _ soup: Node,
        _ config: [String: Any],
        required: Bool
    ) throws -> [Node] {
        let rows = mapValue(config["rows"])
        let selector = presentSelector(rows["selector"])
        guard let selector else {
            if required {
                throw WebAdapterConfigurationException(
                    message: "Web 搜索解析缺少 infoFinder.search.rows.selector 配置"
                )
            }
            return []
        }
        return HtmlExtractor().findRows(soup, selector)
    }

    private static func findConfiguredRows(
        _ soup: Node,
        _ config: [String: Any],
        _ firstKey: String,
        _ alternateKey: String
    ) -> [Node] {
        let first = mapValue(config[firstKey])
        let rowConfig = first.isEmpty ? mapValue(config[alternateKey]) : first
        guard let selector = presentSelector(rowConfig["selector"]) else { return [] }
        return HtmlExtractor().findRows(soup, selector)
    }

    private static func containsRow(_ rows: [Node], _ row: Node) -> Bool {
        rows.contains { $0 === row }
    }

    private static func hasClass(_ row: Node?, _ className: String) -> Bool {
        guard let row, let raw = SelectorEngine.attributeValue(row, "class") else { return false }
        let tokens = raw.components(separatedBy: classTokenSeparator)
        return tokens.contains { $0 == className }
    }

    static func extractValues(_ row: Node, _ rawFields: [String: Any]) -> [String: String] {
        let normalizedRawFields = normalizePositionalSelectors(rawFields)
        let fields = HtmlExtractor.parseFieldConfigs(normalizedRawFields)
        let results = HtmlExtractor().extractRowResultsSync(row, fields)
        var values: [String: String] = [:]
        for (key, result) in results {
            if let value = result.first.string, !value.isEmpty {
                values[key] = value
            }
        }

        for (key, entry) in normalizedRawFields {
            let rawField = mapValue(entry)
            let stripped = extractStrippedTextValues(row, rawField)
            if let first = stripped.first {
                values[key] = first
            }
        }

        for (key, config) in fields {
            guard config.hasValue, let template = config.value else { continue }
            let templateVariables: [String: Any] = values
            let value = WebAdapterCore.replacePlaceholders(template, templateVariables)
            if !value.isEmpty {
                values[key] = value
            }
        }

        for (key, entry) in normalizedRawFields {
            let rawField = mapValue(entry)
            let joinedFieldNames = stringList(rawField["join"])
            if joinedFieldNames.isEmpty { continue }

            values.removeValue(forKey: key)
            let joinedValues = joinedFieldNames.compactMap { values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if joinedValues.isEmpty { continue }
            let separator = rawField["separator"] as? String ?? ""
            values[key] = joinedValues.joined(separator: separator)
        }
        return values
    }

    private static func normalizePositionalSelectors(
        _ fields: [String: Any]
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, rawValue) in fields {
            guard let rawMap = rawValue as? [String: Any] else {
                result[key] = rawValue
                continue
            }
            var field = rawMap
            if let selector = field["selector"] as? String,
               positionalSelectorRegex.firstMatch(
                   in: selector,
                   options: [],
                   range: NSRange(selector.startIndex..., in: selector)
               ) != nil
            {
                field["selector"] = String(selector.dropFirst(2))
            }
            result[key] = field
        }
        return result
    }

    private static func extractStrippedTextValues(
        _ row: Node,
        _ rawField: [String: Any]
    ) -> [String] {
        let selectors = stringList(coalesce(rawField["stripSelectors"], rawField["excludeSelectors"]))
        if selectors.isEmpty || (rawField["attribute"] as? String) != "text" { return [] }

        let selector = rawField["selector"] as? String
        let targets: [Node]
        if let selector, !selector.isEmpty {
            targets = HtmlExtractor().findElementBySelector(row, selector)
        } else {
            targets = [row]
        }

        var cleanedConfigJson: [String: Any] = ["attribute": "text"]
        if let filter = presentValue(rawField["filter"]) {
            cleanedConfigJson["filter"] = filter
        }
        if let defaultValue = presentValue(rawField["defaultValue"]) {
            cleanedConfigJson["defaultValue"] = defaultValue
        }
        let cleanedConfig = FieldConfig.fromJson(cleanedConfigJson)

        var values: [String] = []
        for target in targets {
            guard let html = try? target.outerHtml(), !html.isEmpty else { continue }
            let clonedSoup = try? SwiftSoup.parse(html)
            guard let clonedSoup else { continue }
            let rootName = (target as? Element)?.tagName()
            var root: Node = clonedSoup
            if let rootName, !rootName.isEmpty,
               let elements = try? clonedSoup.select(rootName),
               let matched = elements.first
            {
                root = matched
            }
            for stripSelector in selectors {
                let elements = HtmlExtractor().findElementBySelector(root, stripSelector)
                for element in elements {
                    try? element.remove()
                }
            }
            if let value = HtmlExtractor().extractFieldSync(root, cleanedConfig).string,
               !value.isEmpty
            {
                values.append(value)
            }
        }
        return values
    }

    private static func mergeNonEmpty(
        _ inherited: [String: String],
        _ values: [String: String]
    ) -> [String: String] {
        var merged = inherited
        for (key, value) in values where !value.isEmpty {
            merged[key] = value
        }
        return merged
    }

    private static func shiftColumnFields(
        _ fields: [String: Any],
        _ offset: Int
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, rawValue) in fields {
            guard let rawMap = rawValue as? [String: Any] else {
                result[key] = rawValue
                continue
            }
            var field = rawMap
            if let selector = field["selector"] as? String {
                field["selector"] = shiftColumnSelector(selector, offset)
            }
            result[key] = field
        }
        return result
    }

    private static func shiftColumnSelector(_ selector: String, _ offset: Int) -> String {
        let matches = columnSelectorRegex.matches(
            in: selector,
            options: [],
            range: NSRange(selector.startIndex..., in: selector)
        )
        guard !matches.isEmpty else { return selector }

        var output = ""
        var cursor = selector.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: selector),
                  let tagRange = Range(match.range(at: 1), in: selector),
                  let indexRange = Range(match.range(at: 2), in: selector),
                  let index = Int(selector[indexRange])
            else { continue }
            output += selector[cursor..<fullRange.lowerBound]
            let shifted = index > offset ? index - offset : 1
            output += "\(selector[tagRange]):nth-child(\(shifted))"
            cursor = fullRange.upperBound
        }
        output += selector[cursor...]
        return output
    }

    private static func buildTorrentItem(
        _ values: [String: String],
        _ rawFields: [String: Any],
        _ baseUrl: String,
        _ discountMapping: [String: String],
        _ tagMapping: [String: String]
    ) -> TorrentItem? {
        var torrentId = firstValue(values, ["torrentId", "id"])
        let rawDetailUrl = firstValue(values, ["detailUrl", "url"])
        let rawDownloadUrl = firstValue(values, ["downloadUrl", "link"])
        if torrentId == nil {
            torrentId = torrentIdFromUrl(rawDownloadUrl) ?? torrentIdFromUrl(rawDetailUrl)
        }
        guard let torrentId, !torrentId.isEmpty else { return nil }

        let detailUrl = WebAdapterCore.resolveHttpUrl(rawDetailUrl, baseUrl)
        let downloadUrl = WebAdapterCore.resolveHttpUrl(rawDownloadUrl, baseUrl)
        let name = firstValue(values, ["torrentName", "name", "title"]) ?? ""
        let description = firstValue(
            values,
            ["description", "smallDescr", "subtitle", "category"]
        ) ?? ""
        let sizeText = firstValue(values, ["sizeText", "size"]) ?? ""
        let discountRaw = firstValue(values, ["discount", "freeleech", "isFreeleech"])
        let discount = parseDiscount(discountRaw, discountMapping)
        let createDate = parseDate(values["createDate"], rawFields["createDate"])
        let discountEnd = parseDate(values["discountEndTime"], rawFields["discountEndTime"])
        let tagValues = values["tag"]?.components(separatedBy: ",") ?? []

        return TorrentItem(
            id: torrentId,
            name: name,
            smallDescr: description,
            discount: discount,
            discountEndTime: discountEnd,
            downloadUrl: downloadUrl,
            detailUrl: detailUrl,
            description: values["description"],
            seeders: asInt(firstValue(values, ["seedersText", "seeders"])) ?? 0,
            leechers: asInt(firstValue(values, ["leechersText", "leechers"])) ?? 0,
            sizeBytes: TypedConverter.parseSizeToBytes(sizeText),
            createdDate: createDate ?? Date(),
            imageList: [],
            cover: WebAdapterCore.resolveHttpUrl(values["cover"], baseUrl) ?? "",
            downloadStatus: TypedConverter.parseDownloadStatus(values["downloadStatus"]),
            collection: asBool(values["collection"]),
            doubanRating: values["doubanRating"] ?? "N/A",
            imdbRating: values["imdbRating"] ?? "N/A",
            isTop: asBool(values["isTop"]),
            tags: TypedConverter.parseTags(name, description, tagValues, tagMapping),
            comments: asInt(values["comments"]) ?? 0
        )
    }

    private static func firstValue(
        _ values: [String: String],
        _ keys: [String]
    ) -> String? {
        for key in keys {
            if let value = values[key], !value.isEmpty { return value }
        }
        return nil
    }

    private static func torrentIdFromUrl(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        if let components = URLComponents(string: url) {
            let fromQuery = lastQueryValue(components.queryItems, "torrentid")
                ?? lastQueryValue(components.queryItems, "id")
            if let fromQuery, !fromQuery.isEmpty { return fromQuery }
        }
        let match = torrentIdUrlRegex.firstMatch(
            in: url,
            options: [],
            range: NSRange(url.startIndex..., in: url)
        )
        guard let match,
              let groupRange = Range(match.range(at: 1), in: url)
        else { return nil }
        return String(url[groupRange])
    }

    private static func lastQueryValue(_ items: [URLQueryItem]?, _ name: String) -> String? {
        guard let items else { return nil }
        var result: String?
        for item in items where item.name == name {
            result = item.value
        }
        return result
    }

    private static func parseDiscount(
        _ raw: String?,
        _ mapping: [String: String]
    ) -> DiscountType {
        guard let raw, !raw.isEmpty else { return .normal }
        let mapped = TypedConverter.parseDiscount(raw, mapping)
        if mapped != .normal { return mapped }
        let normalized = raw.lowercased()
        if normalized == "true" || normalized == "1" || normalized.contains("free") {
            return .free
        }
        return .normal
    }

    private static func parseDate(_ raw: String?, _ rawField: Any?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let field = mapValue(rawField)
        let time = mapValue(field["time"])
        return ExtractedValue.fromString(raw).parseDateTime(
            format: time["format"] as? String,
            zone: time["zone"] as? String,
            fieldName: "createdDate"
        )
    }

    private static func asBool(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.lowercased() != "false" && value != "0"
    }

    private static func asInt(_ value: Any?) -> Int? {
        guard let present = presentValue(value) else { return nil }
        if let int = strictIntValue(present) { return int }
        return ExtractedValue.fromString(dartToString(present)).intValue
    }

    private static func parseTotalPages(_ soup: Node, _ config: [String: Any]) -> Int {
        let totalConfig = mapValue(config["totalPages"])
        if totalConfig.isEmpty { return 1 }
        let rowsConfig = mapValue(totalConfig["rows"])
        let selector = rowsConfig["selector"] as? String
        let fields = mapValue(totalConfig["fields"])
        let field = HtmlExtractor.parseFieldConfigs(fields)["totalPages"]
        guard let selector, let field else { return 1 }
        let values = HtmlExtractor().findRows(soup, selector).compactMap { row in
            HtmlExtractor().extractFieldSync(row, field).intValue
        }
        if values.isEmpty { return 1 }
        return values.reduce(values[0]) { a, b in a > b ? a : b }
    }

    private static func presentSelector(_ value: Any?) -> String? {
        guard let selector = value as? String,
              !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return selector
    }

    private static func presentValue(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        return value
    }

    private static func coalesce(_ first: Any?, _ second: Any?) -> Any? {
        presentValue(first) ?? presentValue(second)
    }

    private static func mapValue(_ value: Any?) -> [String: Any] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        var result: [String: Any] = [:]
        for (key, entry) in dictionary {
            result[key] = entry
        }
        return result
    }

    private static func stringList(_ value: Any?) -> [String] {
        if let string = value as? String {
            return string.isEmpty ? [] : [string]
        }
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { $0 as? String }.filter { !$0.isEmpty }
    }
}