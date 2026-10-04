import Foundation
import SwiftSoup

struct TorrentRowExtractor {
    private let rawFieldsConfig: [String: Any]
    private let fields: [String: FieldConfig]
    private let discountMapping: [String: String]
    private let tagMapping: [String: String]
    private let userId: String

    init(
        fieldsConfig: [String: Any],
        discountMapping: [String: String],
        tagMapping: [String: String],
        userId: String = ""
    ) {
        self.rawFieldsConfig = fieldsConfig
        self.fields = parseFieldConfigs(fieldsConfig)
        self.discountMapping = discountMapping
        self.tagMapping = tagMapping
        self.userId = userId
    }

    func extract(_ row: Node, baseUrl: String, passKey: String) -> TorrentItem? {
        var logs: [String]? = nil
        return extract(row, baseUrl: baseUrl, passKey: passKey, logs: &logs)
    }

    func extract(
        _ row: Node,
        baseUrl: String,
        passKey: String,
        logs: inout [String]?
    ) -> TorrentItem? {
        let extracted = extractRowResults(row, fields)

        let torrentId = extracted["torrentId"]?.first.stringOrEmpty ?? ""
        if torrentId.isEmpty {
            logs?.append(
                "TorrentRowExtractor: 缺失 torrentId，跳过当前行。配置: \(dartToString(fields["torrentId"]?.toJson()))"
            )
            return nil
        }

        let torrentName = extracted["torrentName"]?.first.stringOrEmpty ?? ""
        let description = extracted["description"]?.first.stringOrEmpty ?? ""
        let discountRaw = extracted["discount"]?.first.stringOrEmpty ?? ""
        let discountEndTimeRaw = extracted["discountEndTime"]?.first.stringOrEmpty ?? ""
        let sizeText = extracted["sizeText"]?.first.stringOrEmpty ?? ""
        let downloadStatusText = extracted["downloadStatus"]?.first.stringOrEmpty ?? ""
        let coverRaw = extracted["cover"]?.first.stringOrEmpty ?? ""
        let doubanRating = extracted["doubanRating"]?.first.stringOrEmpty ?? ""
        let imdbRating = extracted["imdbRating"]?.first.stringOrEmpty ?? ""

        let tagRawList = extracted["tag"]?.allValues ?? []

        let downloadUrl: String
        if let downloadUrlConfig = fields["downloadUrl"], downloadUrlConfig.hasValue {
            downloadUrl = TypedConverter.resolveDownloadUrl(
                downloadUrlConfig.value!,
                torrentId,
                passKey,
                baseUrl,
                userId: userId
            )
        } else {
            downloadUrl = extracted["downloadUrl"]?.first.stringOrEmpty ?? ""
        }

        let cover = TypedConverter.resolveUrl(coverRaw, baseUrl)

        let discountEndTimeTimeConfig = extractNestedConfig(
            "discountEndTime",
            nestedKey: "time"
        )
        let createDateTimeConfig = extractNestedConfig("createDate", nestedKey: "time")

        return TorrentItem(
            id: torrentId,
            name: torrentName,
            smallDescr: description.trimmingCharacters(in: .whitespacesAndNewlines),
            discount: TypedConverter.parseDiscount(
                discountRaw.isEmpty ? nil : discountRaw,
                discountMapping
            ),
            discountEndTime: discountEndTimeRaw.isEmpty
                ? nil
                : extracted["discountEndTime"]?.first.parseDateTime(
                    format: discountEndTimeTimeConfig?["format"] as? String,
                    zone: discountEndTimeTimeConfig?["zone"] as? String,
                    fieldName: "discountEndTime"
                ),
            downloadUrl: downloadUrl.isEmpty ? nil : downloadUrl,
            seeders: extracted["seedersText"]?.first.intValueOr(0) ?? 0,
            leechers: extracted["leechersText"]?.first.intValueOr(0) ?? 0,
            sizeBytes: TypedConverter.parseSizeToBytes(sizeText),
            createdDate: extracted["createDate"]?.first.parseDateTime(
                format: createDateTimeConfig?["format"] as? String,
                zone: createDateTimeConfig?["zone"] as? String,
                fieldName: "createdDate"
            ) ?? Date(),
            imageList: [],
            cover: cover,
            downloadStatus: TypedConverter.parseDownloadStatus(downloadStatusText),
            collection: extracted["collection"]?.first.asBool ?? false,
            doubanRating: doubanRating.isEmpty ? "N/A" : doubanRating,
            imdbRating: imdbRating.isEmpty ? "N/A" : imdbRating,
            isTop: extracted["isTop"]?.first.asBool ?? false,
            tags: TypedConverter.parseTags(
                torrentName,
                description,
                tagRawList,
                tagMapping
            ),
            comments: extracted["comments"]?.first.intValueOr(0) ?? 0
        )
    }

    private func extractNestedConfig(
        _ fieldName: String,
        nestedKey: String
    ) -> [String: Any]? {
        guard let fieldConfig = rawFieldsConfig[fieldName] as? [String: Any] else {
            return nil
        }
        return fieldConfig[nestedKey] as? [String: Any]
    }
}
