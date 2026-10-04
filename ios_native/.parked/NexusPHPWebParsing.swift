import Foundation
import SwiftSoup

enum NexusPHPWebRequestConfigCacheEntry {
    case value([String: Any])
    case missing
}

struct NexusPHPWebParseSearchParams {
    let html: String
    let searchConfig: [String: Any]
    let totalPagesConfig: [String: Any]
    let discountMapping: [String: String]
    let tagMapping: [String: String]
    let baseUrl: String
    let passKey: String
    let userId: String
    let pageNumber: Int
    let pageSize: Int
}

struct NexusPHPWebParsedTorrentResult {
    let items: [TorrentItem]
    let totalPages: Int
    let logs: [String]
}

enum NexusPHPWebErrorText {
    static func text(_ error: Error) -> String {
        if let siteError = error as? SiteException {
            return "Exception: \(siteError.descriptionText)"
        }
        return String(describing: error)
    }
}

enum NexusPHPWebCore {
    private static let placeholderRegex = try! NSRegularExpression(
        pattern: #"\{([A-Za-z0-9_]+)\}"#
    )

    static let htmlUrlRegex = try! NSRegularExpression(
        pattern: #"(src|href)="((?!https?://|//|data:|javascript:|#)[^"]+)"#,
        options: [.caseInsensitive]
    )

    static func replacePlaceholders(_ source: String, _ variables: [String: Any]) -> String {
        let matches = placeholderRegex.matches(
            in: source,
            options: [],
            range: NSRange(source.startIndex..., in: source)
        )
        if matches.isEmpty { return source }

        var result = ""
        var cursor = source.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: source) else { continue }
            result += source[cursor..<fullRange.lowerBound]
            let name = groupText(match, 1, source) ?? ""
            if let value = variables[name], !(value is NSNull) {
                result += dartToString(value)
            } else {
                result += ""
            }
            cursor = fullRange.upperBound
        }
        result += source[cursor...]
        return result
    }

    static func replacePlaceholdersDeep(_ value: Any, _ variables: [String: Any]) -> Any {
        if let string = value as? String {
            return replacePlaceholders(string, variables)
        }
        if let list = value as? [Any] {
            return list.map { replacePlaceholdersDeep($0, variables) }
        }
        if let map = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, entry) in map {
                out[key] = replacePlaceholdersDeep(entry, variables)
            }
            return out
        }
        return value
    }

    static func resolveHttpUrl(_ value: String?, _ baseUrl: String) -> String? {
        guard let value else { return nil }
        let raw = value.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return nil }

        guard let base = URL(string: baseUrl),
              let scheme = base.scheme,
              !scheme.isEmpty,
              let baseHost = base.host,
              !baseHost.isEmpty
        else { return nil }

        let resolved: URL?
        if raw.hasPrefix("//") {
            resolved = URL(string: "\(scheme):\(raw)")
        } else if let candidate = URL(string: raw), let candidateScheme = candidate.scheme, !candidateScheme.isEmpty {
            resolved = candidate
        } else {
            resolved = URL(string: raw, relativeTo: base)?.absoluteURL
        }

        guard let resolved,
              let resolvedScheme = resolved.scheme?.lowercased(),
              resolvedScheme == "http" || resolvedScheme == "https",
              let host = resolved.host,
              !host.isEmpty
        else { return nil }
        return resolved.absoluteString
    }

    static func replaceAssetUrls(_ html: String, _ baseUrl: String) -> String {
        let matches = htmlUrlRegex.matches(
            in: html,
            options: [],
            range: NSRange(html.startIndex..., in: html)
        )
        if matches.isEmpty { return html }

        var result = ""
        var cursor = html.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: html) else { continue }
            result += html[cursor..<fullRange.lowerBound]
            let attr = groupText(match, 1, html) ?? ""
            let path = groupText(match, 2, html) ?? ""
            let separator = path.hasPrefix("/") ? "" : "/"
            result += "\(attr)=\"\(baseUrl)\(separator)\(path)\""
            cursor = fullRange.upperBound
        }
        result += html[cursor...]
        return result
    }

    static func groupText(
        _ match: NSTextCheckingResult,
        _ index: Int,
        _ string: String
    ) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else {
            return nil
        }
        return String(string[swiftRange])
    }
}

enum NexusPHPWebSafeContentTypeTransformer {
    static func transform(_ contentType: String) -> String {
        guard contentType.contains(";") else { return contentType }

        let parts = contentType.components(separatedBy: ";")
        var validParts: [String] = []
        for (index, part) in parts.enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if index == 0 {
                validParts.append(trimmed)
            } else if trimmed.contains("=") && !trimmed.contains(":") {
                validParts.append(trimmed)
            }
        }

        if validParts.count < parts.count {
            return validParts.joined(separator: "; ")
        }
        return contentType
    }
}

enum NexusPHPWebParser {
    static func parseSoup(_ html: String) throws -> Document {
        do {
            return try SwiftSoup.parse(html)
        } catch {
            throw SiteServiceException(
                message: "解析HTML失败",
                detail: ApiExceptionAdapter.truncateDetail(NexusPHPWebErrorText.text(error))
            )
        }
    }

    static func parseSearchResponse(
        _ params: NexusPHPWebParseSearchParams
    ) throws -> NexusPHPWebParsedTorrentResult {
        let soup = try parseSoup(params.html)
        var logs: [String]? = []

        let torrents = parseTorrentList(
            soup,
            params.searchConfig,
            params.discountMapping,
            params.tagMapping,
            params.baseUrl,
            params.passKey,
            params.userId,
            logs: &logs
        )

        let totalPages = parseTotalPages(
            soup,
            params.totalPagesConfig,
            logs: &logs
        )

        return NexusPHPWebParsedTorrentResult(
            items: torrents,
            totalPages: totalPages,
            logs: logs ?? []
        )
    }

    static func parseTotalPages(
        _ soup: Node,
        _ config: [String: Any],
        logs: inout [String]?
    ) -> Int {
        let extractor = HtmlExtractor()
        var totalPages = 1
        do {
            guard let rowsConfig = try JSONCast.optionalMap(config["rows"]),
                  let fieldsConfig = try JSONCast.optionalMap(config["fields"])
            else {
                return 1
            }

            guard let rowSelector = try JSONCast.optionalString(rowsConfig["selector"]),
                  !rowSelector.isEmpty
            else {
                return 1
            }

            let rows = extractor.findRows(soup, rowSelector)
            if rows.isEmpty {
                return 1
            }

            guard let fieldConfig = HtmlExtractor.parseFieldConfigs(fieldsConfig)["totalPages"] else {
                return 1
            }

            var pageValues: [Int] = []
            for row in rows {
                let parsed = extractor.extractFieldSync(row, fieldConfig).intValue
                if let parsed {
                    pageValues.append(parsed)
                }
            }

            if !pageValues.isEmpty {
                totalPages = pageValues.max() ?? totalPages
            }
        } catch {
            logs?.append("解析总页数失败: \(NexusPHPWebErrorText.text(error))")
        }
        return totalPages
    }

    static func parseTorrentList(
        _ soup: Node,
        _ searchConfig: [String: Any],
        _ discountMapping: [String: String],
        _ tagMapping: [String: String],
        _ baseUrl: String,
        _ passKey: String,
        _ userId: String,
        logs: inout [String]?
    ) -> [TorrentItem] {
        var torrents: [TorrentItem] = []

        do {
            guard let rowsConfig = try JSONCast.optionalMap(searchConfig["rows"]),
                  let fieldsConfig = try JSONCast.optionalMap(searchConfig["fields"])
            else {
                logs?.append("search.config.missing: \(dartToString(searchConfig))")
                return torrents
            }

            guard let rowSelector = try JSONCast.optionalString(rowsConfig["selector"]) else {
                logs?.append("search.rowSelector.missing: \(dartToString(rowsConfig))")
                return torrents
            }

            let extractor = HtmlExtractor()
            let rows = extractor.findRows(soup, rowSelector)

            let torrentExtractor = TorrentRowExtractor(
                fieldsConfig: fieldsConfig,
                discountMapping: discountMapping,
                tagMapping: tagMapping,
                userId: userId
            )

            for rowElement in rows {
                if let item = torrentExtractor.extract(
                    rowElement,
                    baseUrl: baseUrl,
                    passKey: passKey,
                    logs: &logs
                ) {
                    torrents.append(item)
                }
            }
        } catch {
            logs?.append("search.parse.failed: \(NexusPHPWebErrorText.text(error))")
        }

        return torrents
    }
}
