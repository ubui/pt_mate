import Foundation
#if canImport(UIKit)
import UIKit
#endif

actor DeviceIdService {
    static let shared = DeviceIdService()

    private let storage: StorageService

    private var cachedDeviceId: String?

    init(storage: StorageService = .shared) {
        self.storage = storage
    }

    func getDeviceId() async -> String {
        if let cachedDeviceId {
            return cachedDeviceId
        }

        do {
            if let storedDeviceId = try await storage.loadDeviceId(),
               !storedDeviceId.isEmpty {
                cachedDeviceId = storedDeviceId
                return storedDeviceId
            }

            let newDeviceId = generateDeviceId()

            try await storage.saveDeviceId(newDeviceId)

            cachedDeviceId = newDeviceId
            return newDeviceId
        } catch {
            return generateFallbackDeviceId()
        }
    }

    nonisolated func getPlatform() -> String {
        Self.platformName()
    }

    func resetDeviceId() async {
        do {
            try await storage.deleteDeviceId()
            cachedDeviceId = nil
        } catch {
        }
    }

    func hasStoredDeviceId() async -> Bool {
        do {
            guard let storedDeviceId = try await storage.loadDeviceId() else {
                return false
            }
            return !storedDeviceId.isEmpty
        } catch {
            return false
        }
    }

    private func generateDeviceId() -> String {
        "\(Self.platformName())_\(Self.newUuid())"
    }

    private func generateFallbackDeviceId() -> String {
        let platform = Self.platformName()
        if let deviceIdentifier = Self.fallbackDeviceIdentifier() {
            return "\(platform)_fallback_\(deviceIdentifier)"
        }
        return "\(platform)_emergency_\(Self.newUuid())"
    }

    private static func platformName() -> String {
        #if canImport(UIKit)
        return "ios"
        #else
        return "unknown"
        #endif
    }

    private static func newUuid() -> String {
        UUID().uuidString.lowercased()
    }

    private static func fallbackDeviceIdentifier() -> String? {
        #if canImport(UIKit)
        let device = UIDevice.current
        let identifierForVendor = device.identifierForVendor?.uuidString ?? ""
        let source = "\(device.model)_\(identifierForVendor)_\(device.systemVersion)"
        return stableHashValue(source)
        #else
        return nil
        #endif
    }

    private static func stableHashValue(_ input: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in Array(input.utf8) {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(hash & 0x3FFF_FFFF)
    }
}