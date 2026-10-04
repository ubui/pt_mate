import Foundation
import SwiftSoup

struct SelectorAttributeSpec {
    let tag: String?
    let attribute: String
    let op: String?
    let value: String?
    let regex: NSRegularExpression?
}

struct SelectorClassAttributeSpec {
    let tag: String?
    let className: String
    let attribute: String
    let op: String?
    let value: String?
    let regex: NSRegularExpression?
}

struct SelectorContainsSpec {
    let preSelector: String
    let groups: [[String]]
}

struct SelectorIndexedSpec {
    let tag: String?
    let index: Int
}

struct SelectorNamedSpec {
    let tag: String?
    let value: String
}

struct SelectorPlan {
    let selector: String
    var isEmpty: Bool = false
    var cssSelector: String? = nil
    var childParts: [String]? = nil
    var classAndAttrValue: SelectorClassAttributeSpec? = nil
    var classAndAttrExists: SelectorClassAttributeSpec? = nil
    var attrValue: SelectorAttributeSpec? = nil
    var attrExists: SelectorAttributeSpec? = nil
    var contains: SelectorContainsSpec? = nil
    var nthChild: SelectorIndexedSpec? = nil
    var nthChildTag: String? = nil
    var nthNode: SelectorIndexedSpec? = nil
    var nthNodeTag: String? = nil
    var firstChild: Bool = false
    var lastChild: Bool = false
    var firstNode: Bool = false
    var lastNode: Bool = false
    var idSelector: SelectorNamedSpec? = nil
    var classSelector: SelectorNamedSpec? = nil
    var tagSelector: String? = nil
}

enum SelectorEngine {
    private static let lock = NSRecursiveLock()
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static var regexOrder: [String] = []
    private static var planCache: [String: SelectorPlan] = [:]
    private static var planOrder: [String] = []
    private static let maxRegexCacheSize = 100
    private static let maxPlanCacheSize = 200

    private static let classAndAttrValueRegExp = try! NSRegularExpression(
        pattern: #"^([a-zA-Z0-9_-]*)\.([a-zA-Z0-9_-]+)\[([a-zA-Z0-9_-]+)([\^=~*])="([^"]+)"\]"#
    )
    private static let classAndAttrExistsRegExp = try! NSRegularExpression(
        pattern: #"^([a-zA-Z0-9_-]*)\.([a-zA-Z0-9_-]+)\[([a-zA-Z0-9_-]+)\]"#
    )
    private static let attributeExistsRegExp = try! NSRegularExpression(
        pattern: #"^([a-zA-Z0-9_-]*)\[([a-zA-Z0-9_-]+)\]"#
    )
    private static let attributeValueRegExp = try! NSRegularExpression(
        pattern: #"^([a-zA-Z0-9_-]*)\[([a-zA-Z0-9_-]+)([\^=~*])="([^"]+)"\]"#
    )
    private static let containsAllRegExp = try! NSRegularExpression(
        pattern: #"^([^:]*):contains\((.*)\)$"#
    )
    private static let nthChildWithParenRegExp = try! NSRegularExpression(
        pattern: #"^([^:]*):nth-child\((\d+)\)"#
    )
    private static let nthChildRegExp = try! NSRegularExpression(
        pattern: #"^([^:]+):nth-child$"#
    )
    private static let nthNodeWithParenRegExp = try! NSRegularExpression(
        pattern: #"^([^:]*):nth-node\((\d+)\)"#
    )
    private static let nthNodeRegExp = try! NSRegularExpression(
        pattern: #"^([^:]+):nth-node$"#
    )
    private static let singleQuoteRegExp = try! NSRegularExpression(
        pattern: #"^'(.*)'$"#
    )
    private static let doubleQuoteRegExp = try! NSRegularExpression(
        pattern: #"^"(.*)"$"#
    )

    private static func firstMatch(_ regex: NSRegularExpression, _ string: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string))
    }

    private static func groupText(_ match: NSTextCheckingResult, _ index: Int, _ string: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
        return String(string[swiftRange])
    }

    private static func trimmedGroup(_ match: NSTextCheckingResult, _ index: Int, _ string: String) -> String? {
        guard let text = groupText(match, index, string) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func emptyToNull(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func cachedRegExp(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = regexCache[pattern] {
            if let index = regexOrder.firstIndex(of: pattern) {
                regexOrder.remove(at: index)
            }
            regexOrder.append(pattern)
            return cached
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache[pattern] = regex
        regexOrder.append(pattern)
        if regexOrder.count > maxRegexCacheSize {
            let oldest = regexOrder.removeFirst()
            regexCache.removeValue(forKey: oldest)
        }
        return regex
    }

    private static func tryBuildRegExp(_ pattern: String) -> NSRegularExpression? {
        cachedRegExp(pattern)
    }

    static func getSelectorPlan(_ selector: String) -> SelectorPlan {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        if let plan = planCache[trimmed] {
            if let index = planOrder.firstIndex(of: trimmed) {
                planOrder.remove(at: index)
            }
            planOrder.append(trimmed)
            return plan
        }
        let plan = buildPlan(trimmed)
        planCache[trimmed] = plan
        planOrder.append(trimmed)
        if planOrder.count > maxPlanCacheSize {
            let oldest = planOrder.removeFirst()
            planCache.removeValue(forKey: oldest)
        }
        return plan
    }

    private static func buildPlan(_ selector: String) -> SelectorPlan {
        if selector.isEmpty {
            return SelectorPlan(selector: "", isEmpty: true)
        }
        if selector.hasPrefix("@@") {
            return SelectorPlan(
                selector: selector,
                cssSelector: String(selector.dropFirst(2))
            )
        }
        if selector.contains(">") {
            let parts = selector
                .split(separator: ">", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return SelectorPlan(selector: selector, childParts: parts)
        }

        if let match = firstMatch(classAndAttrValueRegExp, selector) {
            let op = trimmedGroup(match, 4, selector)
            let value = trimmedGroup(match, 5, selector)
            return SelectorPlan(
                selector: selector,
                classAndAttrValue: SelectorClassAttributeSpec(
                    tag: emptyToNull(trimmedGroup(match, 1, selector)),
                    className: trimmedGroup(match, 2, selector) ?? "",
                    attribute: trimmedGroup(match, 3, selector) ?? "",
                    op: op,
                    value: value,
                    regex: op == "~" ? value.flatMap(tryBuildRegExp) : nil
                )
            )
        }

        if let match = firstMatch(classAndAttrExistsRegExp, selector) {
            return SelectorPlan(
                selector: selector,
                classAndAttrExists: SelectorClassAttributeSpec(
                    tag: emptyToNull(trimmedGroup(match, 1, selector)),
                    className: trimmedGroup(match, 2, selector) ?? "",
                    attribute: trimmedGroup(match, 3, selector) ?? "",
                    op: nil,
                    value: nil,
                    regex: nil
                )
            )
        }

        if let match = firstMatch(attributeExistsRegExp, selector) {
            return SelectorPlan(
                selector: selector,
                attrExists: SelectorAttributeSpec(
                    tag: emptyToNull(trimmedGroup(match, 1, selector)),
                    attribute: trimmedGroup(match, 2, selector) ?? "",
                    op: nil,
                    value: nil,
                    regex: nil
                )
            )
        }

        if let match = firstMatch(attributeValueRegExp, selector) {
            let op = trimmedGroup(match, 3, selector)
            let value = trimmedGroup(match, 4, selector)
            return SelectorPlan(
                selector: selector,
                attrValue: SelectorAttributeSpec(
                    tag: emptyToNull(trimmedGroup(match, 1, selector)),
                    attribute: trimmedGroup(match, 2, selector) ?? "",
                    op: op,
                    value: value,
                    regex: op == "~" ? value.flatMap(tryBuildRegExp) : nil
                )
            )
        }

        if let match = firstMatch(containsAllRegExp, selector) {
            let preSelector = (groupText(match, 1, selector) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let expr = (groupText(match, 2, selector) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SelectorPlan(
                selector: selector,
                contains: SelectorContainsSpec(
                    preSelector: preSelector,
                    groups: parseContainsExpr(expr)
                )
            )
        }

        if selector.contains(":nth-child") {
            if selector.contains(":nth-child(") {
                if let match = firstMatch(nthChildWithParenRegExp, selector) {
                    let index = dartParseInt(groupText(match, 2, selector) ?? "1") ?? 1
                    return SelectorPlan(
                        selector: selector,
                        nthChild: SelectorIndexedSpec(
                            tag: emptyToNull(trimmedGroup(match, 1, selector)),
                            index: index
                        )
                    )
                }
            } else {
                if let match = firstMatch(nthChildRegExp, selector) {
                    return SelectorPlan(
                        selector: selector,
                        nthChildTag: emptyToNull(trimmedGroup(match, 1, selector))
                    )
                }
            }
        } else if selector.contains(":first-child") {
            return SelectorPlan(selector: selector, firstChild: true)
        } else if selector.contains(":last-child") {
            return SelectorPlan(selector: selector, lastChild: true)
        } else if selector.contains(":nth-node") {
            if selector.contains(":nth-node(") {
                if let match = firstMatch(nthNodeWithParenRegExp, selector) {
                    let index = dartParseInt(groupText(match, 2, selector) ?? "1") ?? 1
                    return SelectorPlan(
                        selector: selector,
                        nthNode: SelectorIndexedSpec(
                            tag: emptyToNull(trimmedGroup(match, 1, selector)),
                            index: index
                        )
                    )
                }
            } else {
                if let match = firstMatch(nthNodeRegExp, selector) {
                    return SelectorPlan(
                        selector: selector,
                        nthNodeTag: emptyToNull(trimmedGroup(match, 1, selector))
                    )
                }
            }
        } else if selector.contains(":first-node") {
            return SelectorPlan(selector: selector, firstNode: true)
        } else if selector.contains(":last-node") {
            return SelectorPlan(selector: selector, lastNode: true)
        } else if selector.contains("#") {
            let parts = selector
                .split(separator: "#", omittingEmptySubsequences: false)
                .map(String.init)
            if parts.count == 2 {
                let value = parts[1]
                    .split(separator: " ", omittingEmptySubsequences: false)
                    .first
                    .map(String.init) ?? ""
                return SelectorPlan(
                    selector: selector,
                    idSelector: SelectorNamedSpec(tag: emptyToNull(parts[0]), value: value)
                )
            }
        } else if selector.contains(".") {
            let parts = selector
                .split(separator: ".", omittingEmptySubsequences: false)
                .map(String.init)
            if parts.count == 2 {
                let value = parts[1]
                    .split(separator: " ", omittingEmptySubsequences: false)
                    .first
                    .map(String.init) ?? ""
                return SelectorPlan(
                    selector: selector,
                    classSelector: SelectorNamedSpec(tag: emptyToNull(parts[0]), value: value)
                )
            }
        }

        return SelectorPlan(selector: selector, tagSelector: selector)
    }

    static func findElementBySelector(_ soup: Node, _ selector: String) -> [Node] {
        let plan = getSelectorPlan(selector)
        if plan.isEmpty {
            return [soup]
        }
        if let cssSelector = plan.cssSelector {
            return selectCSS(soup, cssSelector)
        }
        if let childParts = plan.childParts {
            return findViaChildChain(soup, childParts)
        }

        if let spec = plan.classAndAttrValue,
           !spec.className.isEmpty,
           !spec.attribute.isEmpty,
           let op = spec.op,
           let value = spec.value
        {
            let elements = findAll(spec.tag ?? "*", root: soup, class_: spec.className)
            var filtered: [Node] = []
            for element in elements {
                guard let attrValue = attributeValue(element, spec.attribute) else { continue }
                if matchesAttribute(attrValue, op: op, value: value, regex: spec.regex, normalize: false) {
                    filtered.append(element)
                }
            }
            return filtered
        }

        if let spec = plan.classAndAttrExists,
           !spec.className.isEmpty,
           !spec.attribute.isEmpty
        {
            let elements = findAll(spec.tag ?? "*", root: soup, class_: spec.className)
            return elements.filter { attributeValue($0, spec.attribute) != nil }
        }

        if let spec = plan.attrExists, !spec.attribute.isEmpty {
            return findAll(spec.tag ?? "*", root: soup, attrs: [spec.attribute: true])
        }

        if let spec = plan.attrValue,
           !spec.attribute.isEmpty,
           let op = spec.op,
           let value = spec.value
        {
            let elements = findAll(spec.tag ?? "*", root: soup)
            var filtered: [Node] = []
            for element in elements {
                guard let attrValue = attributeValue(element, spec.attribute) else { continue }
                if matchesAttribute(attrValue, op: op, value: value, regex: spec.regex, normalize: true) {
                    filtered.append(element)
                }
            }
            return filtered
        }

        if let spec = plan.contains {
            let candidates = spec.preSelector.isEmpty
                ? findAll("*", root: soup)
                : findElementBySelector(soup, spec.preSelector)
            var results: [Node] = []
            for element in candidates {
                let text = normalizeContainsText(dartText(element) ?? "")
                let matched = spec.groups.contains { group in
                    group.allSatisfy { needle in text.contains(needle) }
                }
                if matched {
                    results.append(element)
                }
            }
            return results
        }

        if let nthChild = plan.nthChild {
            let children = elementChildren(soup)
            if !children.isEmpty, nthChild.index > 0, nthChild.index <= children.count {
                let child = children[nthChild.index - 1]
                if let tag = nthChild.tag, !tag.isEmpty, tag != "*" {
                    return child.tagName().lowercased() == tag.lowercased() ? [child] : []
                }
                return [child]
            }
        } else if let tag = plan.nthChildTag {
            return elementChildren(soup).filter { $0.tagName().lowercased() == tag.lowercased() }
        } else if plan.firstChild {
            if let first = elementChildren(soup).first {
                return [first]
            }
        } else if plan.lastChild {
            if let last = elementChildren(soup).last {
                return [last]
            }
        } else if let nthNode = plan.nthNode {
            let nodes = soup.getChildNodes()
            if !nodes.isEmpty, nthNode.index > 0, nthNode.index <= nodes.count {
                let node = nodes[nthNode.index - 1]
                if let tag = nthNode.tag, !tag.isEmpty, tag != "*" {
                    if let element = node as? Element, element.tagName().lowercased() == tag.lowercased() {
                        return [node]
                    }
                    return []
                }
                return [node]
            }
        } else if let tag = plan.nthNodeTag {
            return soup.getChildNodes().filter { node in
                (node as? Element)?.tagName().lowercased() == tag.lowercased()
            }
        } else if plan.firstNode {
            if let first = soup.getChildNodes().first {
                return [first]
            }
        } else if plan.lastNode {
            if let last = soup.getChildNodes().last {
                return [last]
            }
        } else if let idSelector = plan.idSelector {
            return findAll(idSelector.tag ?? "*", root: soup, id: idSelector.value)
        } else if let classSelector = plan.classSelector {
            return findAll(classSelector.tag ?? "*", root: soup, attrs: ["class": classSelector.value])
        } else if let tagSelector = plan.tagSelector {
            return findAll(tagSelector, root: soup)
        }

        return []
    }

    static func findFirstElementBySelector(_ soup: Node, _ selector: String) -> Node? {
        findElementBySelector(soup, selector).first
    }

    private static func findViaChildChain(_ soup: Node, _ parts: [String]) -> [Node] {
        var current: [Node] = [soup]
        for part in parts {
            if current.isEmpty { break }
            var next: [Node] = []
            for element in current {
                switch part {
                case "next":
                    if let target = element as? Element,
                       let sibling = try? target.nextElementSibling()
                    {
                        next.append(sibling)
                    }
                case "prev":
                    if let target = element as? Element,
                       let sibling = try? target.previousElementSibling()
                    {
                        next.append(sibling)
                    }
                case "nextParsed":
                    if let node = nextParsedNode(element) {
                        next.append(node)
                    }
                case "previousParsed":
                    if let node = previousParsedNode(element) {
                        next.append(node)
                    }
                case "nextNode":
                    if let sibling = siblingNode(element, offset: 1) {
                        next.append(sibling)
                    }
                case "previousNode":
                    if let sibling = siblingNode(element, offset: -1) {
                        next.append(sibling)
                    }
                case "parent":
                    if let parent = elementParent(element) {
                        next.append(parent)
                    }
                default:
                    next.append(contentsOf: findElementBySelector(element, part))
                }
            }
            current = next
        }
        return current
    }

    private static func rawParentNode(_ node: Node) -> Node? {
        if let element = node as? Element {
            return element.parent()
        }
        return node.parent()
    }

    private static func elementParent(_ node: Node) -> Element? {
        guard let parent = rawParentNode(node),
              let element = parent as? Element,
              !(parent is Document)
        else {
            return nil
        }
        return element
    }

    private static func nextParsedNode(_ node: Node) -> Node? {
        let children = node.getChildNodes()
        if !children.isEmpty {
            return children[0]
        }
        guard let parentNode = rawParentNode(node) else { return nil }
        let siblings = parentNode.getChildNodes()
        let currentIndex = siblings.firstIndex(where: { $0 === node }) ?? -1
        let nextIndex = currentIndex + 1
        if nextIndex < siblings.count {
            return siblings[nextIndex]
        }
        var previousNode: Node = parentNode
        var ancestor = rawParentNode(parentNode)
        while let current = ancestor {
            let ancestorSiblings = current.getChildNodes()
            let index = ancestorSiblings.firstIndex(where: { $0 === previousNode }) ?? -1
            let indexAfter = index + 1
            if indexAfter < ancestorSiblings.count {
                return ancestorSiblings[indexAfter]
            }
            previousNode = current
            ancestor = rawParentNode(current)
        }
        return nil
    }

    private static func previousParsedNode(_ node: Node) -> Node? {
        guard let parentNode = rawParentNode(node) else { return nil }
        let siblings = parentNode.getChildNodes()
        let currentIndex = siblings.firstIndex(where: { $0 === node }) ?? -1
        let previousIndex = currentIndex - 1
        if previousIndex >= 0 {
            return siblings[previousIndex]
        }
        return rawParentNode(parentNode)
    }

    private static func siblingNode(_ node: Node, offset: Int) -> Node? {
        guard let parent = elementParent(node),
              let currentHtml = try? node.outerHtml()
        else {
            return nil
        }
        let nodes = parent.getChildNodes()
        for (index, sibling) in nodes.enumerated() {
            guard let html = try? sibling.outerHtml() else { continue }
            if html == currentHtml {
                let targetIndex = index + offset
                if targetIndex >= 0, targetIndex < nodes.count {
                    return nodes[targetIndex]
                }
                return nil
            }
        }
        return nil
    }

    private static func matchesAttribute(
        _ attrValue: String,
        op: String,
        value: String,
        regex: NSRegularExpression?,
        normalize: Bool
    ) -> Bool {
        let compareValue = normalize ? normalizeHrefForComparison(attrValue) : attrValue
        switch op {
        case "^":
            return compareValue.hasPrefix(value)
        case "*":
            return compareValue.contains(value)
        case "=":
            return compareValue == value
        case "~":
            guard let regex else { return false }
            let range = NSRange(attrValue.startIndex..., in: attrValue)
            return regex.firstMatch(in: attrValue, options: [], range: range) != nil
        default:
            return false
        }
    }

    static func selectCSS(_ root: Node, _ css: String) -> [Node] {
        guard let element = root as? Element else { return [] }
        guard let elements = try? element.select(css) else { return [] }
        return elements.array().filter { $0 !== root }
    }

    static func findAll(
        _ name: String,
        root: Node,
        id: String? = nil,
        class_: String? = nil,
        attrs: [String: Any]? = nil,
        selector: String? = nil
    ) -> [Node] {
        if let selector {
            return selectCSS(root, selector)
        }
        let anyTag = name == "*"
        let validTag = name != ""
        if attrs == nil {
            let css = (!validTag || anyTag) ? "*" : name
            return filterResults(selectCSS(root, css), id: id, class_: class_)
        }
        let tag = validTag ? name : "*"
        let matched = findAllWithAttributeConditions(tag: tag, attrs: attrs!, root: root)
        return filterResults(matched, id: id, class_: class_)
    }

    private static func filterResults(_ elements: [Node], id: String?, class_: String?) -> [Node] {
        var filtered = elements
        if let class_ {
            filtered = filtered.filter { element in
                let className = (try? element.attr("class")) ?? ""
                return className.contains(class_)
            }
        }
        if let id {
            filtered = filtered.filter { ($0 as? Element)?.id() == id }
        }
        return filtered
    }

    private static func findAllWithAttributeConditions(
        tag: String,
        attrs: [String: Any],
        root: Node
    ) -> [Node] {
        var results: [Node] = []
        for element in descendantElements(root) {
            if tag != "*", element.tagName().lowercased() != tag.lowercased() {
                continue
            }
            var matched = true
            for (key, raw) in attrs {
                guard element.hasAttr(key) else {
                    matched = false
                    break
                }
                if let presence = raw as? Bool, presence {
                    continue
                }
                let expected = String(describing: raw)
                let actual = (try? element.attr(key)) ?? ""
                if expected.contains(" ") {
                    if actual != expected {
                        matched = false
                        break
                    }
                } else {
                    let words = actual
                        .split(separator: " ", omittingEmptySubsequences: true)
                        .map(String.init)
                    if !words.contains(expected) {
                        matched = false
                        break
                    }
                }
            }
            if matched {
                results.append(element)
            }
        }
        return results
    }

    static func descendantElements(_ node: Node) -> [Element] {
        guard let element = node as? Element else { return [] }
        var results: [Element] = []
        var stack: [Element] = Array(element.children().array().reversed())
        while let current = stack.popLast() {
            results.append(current)
            stack.append(contentsOf: current.children().array().reversed())
        }
        return results
    }

    static func elementChildren(_ node: Node) -> [Element] {
        guard let element = node as? Element else { return [] }
        return element.children().array()
    }

    static func attributeValue(_ node: Node, _ key: String) -> String? {
        if key != key.lowercased() {
            return nil
        }
        guard node.hasAttr(key) else { return nil }
        return (try? node.attr(key)) ?? ""
    }

    static func normalizeHrefForComparison(_ href: String) -> String {
        if href.hasPrefix("http://") || href.hasPrefix("https://") {
            if let normalized = normalizeAbsoluteHttpUrl(href) {
                return normalized
            }
        }
        return href
    }

    private static func normalizeAbsoluteHttpUrl(_ href: String) -> String? {
        guard let schemeRange = href.range(of: "://") else { return nil }
        let afterScheme = href[schemeRange.upperBound...]
        let relativeStart = afterScheme.firstIndex(where: {
            $0 == "/" || $0 == "?" || $0 == "#"
        }) ?? afterScheme.endIndex
        var rest = String(afterScheme[relativeStart...])
        if let hashIndex = rest.firstIndex(of: "#") {
            rest = String(rest[..<hashIndex])
        }
        var path = rest
        var query = ""
        if let queryIndex = rest.firstIndex(of: "?") {
            path = String(rest[..<queryIndex])
            query = String(rest[rest.index(after: queryIndex)...])
        }
        guard path.hasPrefix("/") else { return nil }
        path.removeFirst()
        path = path.replacingOccurrences(of: " ", with: "%20")
        query = query.replacingOccurrences(of: " ", with: "%20")
        if query.isEmpty {
            return path
        }
        return path + "?" + query
    }

    static func splitOutsideQuotes(_ input: String, _ op: String) -> [String] {
        var out: [String] = []
        var buffer = ""
        var inSingle = false
        var inDouble = false
        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            if character == "'", !inDouble {
                inSingle.toggle()
                buffer.append(character)
                index = input.index(after: index)
                continue
            }
            if character == "\"", !inSingle {
                inDouble.toggle()
                buffer.append(character)
                index = input.index(after: index)
                continue
            }
            if !inSingle, !inDouble, input[index...].hasPrefix(op) {
                out.append(buffer)
                buffer = ""
                index = input.index(index, offsetBy: op.count)
                continue
            }
            buffer.append(character)
            index = input.index(after: index)
        }
        out.append(buffer)
        return out
    }

    static func parseContainsExpr(_ expr: String) -> [[String]] {
        let orParts = splitOutsideQuotes(expr, "||")
        var groups: [[String]] = []
        for orPart in orParts {
            let andParts = splitOutsideQuotes(orPart, "&&")
            var needles: [String] = []
            for part in andParts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                let match = firstMatch(singleQuoteRegExp, trimmed)
                    ?? firstMatch(doubleQuoteRegExp, trimmed)
                if let match {
                    let value = (groupText(match, 1, trimmed) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        needles.append(value)
                    }
                }
            }
            if !needles.isEmpty {
                groups.append(needles)
            }
        }
        return groups
    }

    static func normalizeContainsText(_ text: String) -> String {
        collapseWhitespace(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func collapseWhitespace(_ string: String) -> String {
        var result = ""
        var inWhitespace = false
        for character in string {
            if character.isWhitespace {
                if !inWhitespace {
                    result.append(" ")
                    inWhitespace = true
                }
            } else {
                result.append(character)
                inWhitespace = false
            }
        }
        return result
    }

    static func dartText(_ node: Node) -> String? {
        if let element = node as? Element {
            return collectRawText(element)
        }
        if let text = node as? TextNode {
            return text.getWholeText()
        }
        if let comment = node as? Comment {
            return comment.getData()
        }
        if let data = node as? DataNode {
            return data.getWholeData()
        }
        return nil
    }

    private static func collectRawText(_ node: Node) -> String {
        var result = ""
        var stack: [Node] = Array(node.getChildNodes().reversed())
        while let current = stack.popLast() {
            if let text = current as? TextNode {
                result += text.getWholeText()
            } else if let data = current as? DataNode {
                result += data.getWholeData()
            } else if current is Comment {
                continue
            } else if current is Element {
                stack.append(contentsOf: current.getChildNodes().reversed())
            }
        }
        return result
    }
}
