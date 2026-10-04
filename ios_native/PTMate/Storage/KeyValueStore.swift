import Foundation
import CoreFoundation

final class KeyValueStore {
    static let standard = KeyValueStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var allKeys: Set<String> {
        Set(defaults.dictionaryRepresentation().keys)
    }

    func contains(_ key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }

    func string(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    func setString(_ value: String?, for key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func int(_ key: String) -> Int? {
        guard let number = defaults.object(forKey: key) as? NSNumber else {
            return nil
        }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number.intValue
    }

    func setInt(_ value: Int?, for key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func bool(_ key: String) -> Bool? {
        guard let number = defaults.object(forKey: key) as? NSNumber else {
            return nil
        }
        guard CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    func setBool(_ value: Bool?, for key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func double(_ key: String) -> Double? {
        guard let number = defaults.object(forKey: key) as? NSNumber else {
            return nil
        }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number.doubleValue
    }

    func setDouble(_ value: Double?, for key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func stringList(_ key: String) -> [String]? {
        defaults.stringArray(forKey: key)
    }

    func setStringList(_ value: [String]?, for key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func data(_ key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func setData(_ value: Data?, for key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func jsonValue<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let raw = defaults.string(forKey: key),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    func setJsonValue<T: Encodable>(_ value: T?, for key: String) throws {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw StorageError.invalidPayload("json_encoding_failed")
        }
        defaults.set(raw, forKey: key)
    }

    func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }
}
