import Foundation
import Observation

@Observable
final class ProxyService {
    static let shared = ProxyService()

    var isProxyEnabled = false
    var proxyHost = ""
    var proxyPort = 7890
    var proxyUsername = ""
    var proxyPassword = ""
    var bypassLan = true
    var bypassRules: [String] = []

    private(set) var generation = 0

    private init() {}

    func applySettings() async {
        let storage = StorageService.shared
        isProxyEnabled = await storage.loadProxyEnabled()
        proxyHost = await storage.loadProxyHost()
        proxyPort = await storage.loadProxyPort()
        proxyUsername = await storage.loadProxyUsername()
        proxyPassword = (try? await storage.loadProxyPassword()) ?? ""
        bypassLan = await storage.loadProxyBypassLan()
        bypassRules = await storage.loadProxyBypassRules()
        generation += 1
    }

    var isActive: Bool {
        isProxyEnabled && !proxyHost.isEmpty && proxyPort > 0
    }

    func matchesBypassRule(host: String) -> Bool {
        guard bypassLan else { return false }
        let hostLower = host.lowercased()

        if hostLower == "localhost" || hostLower == "127.0.0.1" {
            return true
        }
        if hostLower.hasPrefix("192.168.") {
            return true
        }
        if hostLower.hasPrefix("10.") {
            return true
        }
        if hostLower.hasPrefix("172.") {
            let segments = hostLower.split(separator: ".")
            if segments.count >= 2, let second = Int(segments[1]), (16...31).contains(second) {
                return true
            }
        }

        for rule in bypassRules {
            if matchesRule(host: hostLower, rule: rule) {
                return true
            }
        }
        return false
    }

    private func matchesRule(host: String, rule: String) -> Bool {
        let cleanRule = rule.trimmingCharacters(in: .whitespaces).lowercased()
        let cleanHost = host
        if cleanRule.isEmpty { return false }

        if cleanRule.contains("*") {
            let escaped = NSRegularExpression.escapedPattern(for: cleanRule)
                .replacingOccurrences(of: "\\*", with: ".*")
            do {
                let regex = try NSRegularExpression(pattern: "^\(escaped)$")
                let range = NSRange(cleanHost.startIndex..., in: cleanHost)
                if regex.firstMatch(in: cleanHost, range: range) != nil {
                    return true
                }
            } catch {
                return cleanHost.hasSuffix(cleanRule.replacingOccurrences(of: "*", with: ""))
            }
            return false
        }
        return cleanHost == cleanRule
    }

    func makeProxyDictionary() -> [String: Any]? {
        guard isActive else { return nil }
        var dict: [String: Any] = [
            "HTTPEnable": true,
            "HTTPProxy": proxyHost,
            "HTTPPort": proxyPort,
            "HTTPSEnable": true,
            "HTTPSProxy": proxyHost,
            "HTTPSPort": proxyPort,
        ]
        var exceptions: [String] = []
        if bypassLan {
            exceptions.append(contentsOf: ["localhost", "127.0.0.1", "*.local", "192.168.*", "10.*", "<local>"])
            for second in 16...31 {
                exceptions.append("172.\(second).*")
            }
        }
        for rule in bypassRules {
            let trimmed = rule.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                exceptions.append(trimmed)
            }
        }
        if !exceptions.isEmpty {
            dict["ExceptionsList"] = exceptions
        }
        return dict
    }
}
