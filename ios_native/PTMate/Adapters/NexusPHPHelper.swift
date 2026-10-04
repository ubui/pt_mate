import Foundation

protocol NexusPHPHelper {
    var tagMapping: [String: String]? { get }

    var discountMapping: [String: String]? { get }

    func parseTagType(_ str: String?) -> TagType?

    func parseDiscountType(_ str: String?) -> DiscountType

    func getDownLoadHash(_ passkey: String, _ id: String, _ userid: String) -> String
}

extension NexusPHPHelper {
    func parseTagType(_ str: String?) -> TagType? {
        guard let str, !str.isEmpty else { return nil }

        let mapping = tagMapping ?? [:]
        guard let enumName = mapping[str] else { return nil }

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

    func parseDiscountType(_ str: String?) -> DiscountType {
        guard let str, !str.isEmpty else { return .normal }

        let mapping = discountMapping ?? [:]
        guard let enumValue = mapping[str] else { return .normal }

        if let type = DiscountType(rawValue: enumValue) {
            return type
        }

        return .normal
    }

    func getDownLoadHash(_ passkey: String, _ id: String, _ userid: String) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let dateStr = String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let keyString = passkey + dateStr + userid
        let key = NexusPHPCrypto.md5Hex(Array(keyString.utf8))
        let epoch = Int(floor(now.timeIntervalSince1970))
        let exp = epoch + 3600
        let header = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"
        let payload =
            "{\"id\":\(NexusPHPCrypto.jsonString(id)),\"exp\":\(exp),\"iat\":\(epoch)}"
        let body =
            NexusPHPCrypto.base64URLUnpadded(Array(header.utf8)) + "."
            + NexusPHPCrypto.base64URLUnpadded(Array(payload.utf8))
        let signature = NexusPHPCrypto.base64URLUnpadded(
            NexusPHPCrypto.hmacSHA256(
                key: Array(key.utf8),
                message: Array(body.utf8)
            )
        )
        return body + "." + signature
    }
}

private enum NexusPHPCrypto {
    static func md5Hex(_ input: [UInt8]) -> String {
        md5(input).map { String(format: "%02x", $0) }.joined()
    }

    static func md5(_ input: [UInt8]) -> [UInt8] {
        var message = input
        let bitLength = UInt64(input.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for shift in stride(from: 0, to: 64, by: 8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var a0: UInt32 = 0x67452301
        var b0: UInt32 = 0xefcdab89
        var c0: UInt32 = 0x98badcfe
        var d0: UInt32 = 0x10325476

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var m = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                m[i] = UInt32(message[offset])
                    | (UInt32(message[offset + 1]) << 8)
                    | (UInt32(message[offset + 2]) << 16)
                    | (UInt32(message[offset + 3]) << 24)
            }

            var a = a0
            var b = b0
            var c = c0
            var d = d0

            for i in 0..<64 {
                let f: UInt32
                let g: Int
                switch i / 16 {
                case 0:
                    f = (b & c) | (~b & d)
                    g = i
                case 1:
                    f = (d & b) | (~d & c)
                    g = (5 * i + 1) % 16
                case 2:
                    f = b ^ c ^ d
                    g = (3 * i + 5) % 16
                default:
                    f = c ^ (b | ~d)
                    g = (7 * i) % 16
                }
                let temp = d
                d = c
                c = b
                let sum = a &+ f &+ md5K[i] &+ m[g]
                let rotated = (sum << md5S[i]) | (sum >> (32 - md5S[i]))
                b = b &+ rotated
                a = temp
            }

            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
        }

        var output = [UInt8]()
        for value in [a0, b0, c0, d0] {
            output.append(UInt8(value & 0xff))
            output.append(UInt8((value >> 8) & 0xff))
            output.append(UInt8((value >> 16) & 0xff))
            output.append(UInt8((value >> 24) & 0xff))
        }
        return output
    }

    static func sha256(_ input: [UInt8]) -> [UInt8] {
        var message = input
        let bitLength = UInt64(input.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                w[i] = (UInt32(message[offset]) << 24)
                    | (UInt32(message[offset + 1]) << 16)
                    | (UInt32(message[offset + 2]) << 8)
                    | UInt32(message[offset + 3])
            }
            for i in 16..<64 {
                let s0 = rotateRight(w[i - 15], 7) ^ rotateRight(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotateRight(w[i - 2], 17) ^ rotateRight(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h[0]
            var b = h[1]
            var c = h[2]
            var d = h[3]
            var e = h[4]
            var f = h[5]
            var g = h[6]
            var last = h[7]

            for i in 0..<64 {
                let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = last &+ s1 &+ ch &+ sha256K[i] &+ w[i]
                let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                last = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            h[0] = h[0] &+ a
            h[1] = h[1] &+ b
            h[2] = h[2] &+ c
            h[3] = h[3] &+ d
            h[4] = h[4] &+ e
            h[5] = h[5] &+ f
            h[6] = h[6] &+ g
            h[7] = h[7] &+ last
        }

        var output = [UInt8]()
        for value in h {
            output.append(UInt8((value >> 24) & 0xff))
            output.append(UInt8((value >> 16) & 0xff))
            output.append(UInt8((value >> 8) & 0xff))
            output.append(UInt8(value & 0xff))
        }
        return output
    }

    static func hmacSHA256(key: [UInt8], message: [UInt8]) -> [UInt8] {
        var processedKey = key.count > 64 ? sha256(key) : key
        if processedKey.count < 64 {
            processedKey += [UInt8](repeating: 0, count: 64 - processedKey.count)
        }
        var outer = [UInt8](repeating: 0x5c, count: 64)
        var inner = [UInt8](repeating: 0x36, count: 64)
        for i in 0..<64 {
            outer[i] ^= processedKey[i]
            inner[i] ^= processedKey[i]
        }
        return sha256(outer + sha256(inner + message))
    }

    static func base64URLUnpadded(_ bytes: [UInt8]) -> String {
        Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func jsonString(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                output += "\\\""
            case "\\":
                output += "\\\\"
            case "\n":
                output += "\\n"
            case "\r":
                output += "\\r"
            case "\t":
                output += "\\t"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        output += "\""
        return output
    }

    private static func rotateRight(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }

    private static let md5S: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]

    private static let md5K: [UInt32] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ]

    private static let sha256K: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
}
