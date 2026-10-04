import Foundation
import SwiftSoup

private func makeFieldConfigs(_ fieldsConfig: [String: Any]?) -> [String: FieldConfig] {
    parseFieldConfigs(fieldsConfig)
}

struct HtmlExtractor {
    func findRows(_ soup: Node, _ rowSelector: String) -> [Node] {
        SelectorEngine.findElementBySelector(soup, rowSelector)
    }

    func findFirst(_ soup: Node, _ selector: String) -> Node? {
        SelectorEngine.findFirstElementBySelector(soup, selector)
    }

    func findElementBySelector(_ soup: Node, _ selector: String) -> [Node] {
        SelectorEngine.findElementBySelector(soup, selector)
    }

    func extractFieldSync(_ element: Node, _ config: FieldConfig) -> ExtractedValue {
        extractField(element, config)
    }

    func extractFieldValuesSync(_ element: Node, _ config: FieldConfig) -> [String] {
        extractFieldValues(element, config)
    }

    func extractRowResultsSync(
        _ element: Node,
        _ fields: [String: FieldConfig]
    ) -> [String: FieldExtractionResult] {
        extractRowResults(element, fields)
    }

    static func parseFieldConfigs(_ fieldsConfig: [String: Any]?) -> [String: FieldConfig] {
        makeFieldConfigs(fieldsConfig)
    }
}
