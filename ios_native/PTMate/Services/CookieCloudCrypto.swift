import Foundation

enum CookieCloudCryptoError: Error {
    case invalidBase64Payload
    case invalidCipherTextLength
    case invalidPadding
    case invalidPlainTextEncoding
    case unsupportedKeyLength(Int)
    case cryptoUnavailable
}

enum CookieCloudDigest {
    private static let shifts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]

    private static let constants: [UInt32] = [
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

    static func md5(_ input: [UInt8]) -> [UInt8] {
        var state: [UInt32] = [
            0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476,
        ]
        var message = input
        let bitLength = UInt64(input.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0x00)
        }
        for index in 0..<8 {
            let shift = UInt64(8 * index)
            message.append(UInt8(truncatingIfNeeded: bitLength >> shift))
        }

        var offset = 0
        while offset < message.count {
            var words = [UInt32](repeating: 0, count: 16)
            for index in 0..<16 {
                let base = offset + index * 4
                words[index] = UInt32(message[base])
                    | (UInt32(message[base + 1]) << 8)
                    | (UInt32(message[base + 2]) << 16)
                    | (UInt32(message[base + 3]) << 24)
            }
            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            for step in 0..<64 {
                var mixed: UInt32
                var wordIndex: Int
                switch step {
                case 0..<16:
                    mixed = (b & c) | (~b & d)
                    wordIndex = step
                case 16..<32:
                    mixed = (d & b) | (~d & c)
                    wordIndex = (5 * step + 1) % 16
                case 32..<48:
                    mixed = b ^ c ^ d
                    wordIndex = (3 * step + 5) % 16
                default:
                    mixed = c ^ (b | ~d)
                    wordIndex = (7 * step) % 16
                }
                mixed = mixed &+ a &+ constants[step] &+ words[wordIndex]
                a = d
                d = c
                c = b
                b = b &+ rotateLeft(mixed, shifts[step])
            }
            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
            offset += 64
        }

        var digest: [UInt8] = []
        digest.reserveCapacity(16)
        for word in state {
            digest.append(UInt8(truncatingIfNeeded: word))
            digest.append(UInt8(truncatingIfNeeded: word >> 8))
            digest.append(UInt8(truncatingIfNeeded: word >> 16))
            digest.append(UInt8(truncatingIfNeeded: word >> 24))
        }
        return digest
    }

    static func hex(_ bytes: [UInt8]) -> String {
        var result = ""
        result.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            result.append(String(format: "%02x", byte))
        }
        return result
    }

    private static func rotateLeft(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value << amount) | (value >> (32 - amount))
    }
}

enum CookieCloudAESCBC {
    private static let blockSize = 16

    static func decrypt(key: [UInt8], iv: [UInt8], data: [UInt8]) throws -> [UInt8] {
        let roundKeys = try expandKey(key)
        guard iv.count == blockSize else {
            throw CookieCloudCryptoError.invalidCipherTextLength
        }
        guard !data.isEmpty, data.count % blockSize == 0 else {
            throw CookieCloudCryptoError.invalidCipherTextLength
        }

        var previous = iv
        var plain: [UInt8] = []
        plain.reserveCapacity(data.count)
        var offset = 0
        while offset < data.count {
            let cipherBlock = Array(data[offset..<(offset + blockSize)])
            var block = cipherBlock
            decryptBlock(&block, roundKeys: roundKeys)
            for index in 0..<blockSize {
                block[index] ^= previous[index]
            }
            plain.append(contentsOf: block)
            previous = cipherBlock
            offset += blockSize
        }

        return try stripPKCS7(plain)
    }

    private static func stripPKCS7(_ data: [UInt8]) throws -> [UInt8] {
        guard let paddingLength = data.last else {
            throw CookieCloudCryptoError.invalidPadding
        }
        let length = Int(paddingLength)
        guard length >= 1, length <= blockSize, data.count >= length else {
            throw CookieCloudCryptoError.invalidPadding
        }
        let paddingStart = data.count - length
        for index in paddingStart..<data.count where data[index] != paddingLength {
            throw CookieCloudCryptoError.invalidPadding
        }
        return Array(data[0..<paddingStart])
    }

    private static let inverseTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        for value in 1..<256 {
            table[Int(value)] = invert(UInt8(value))
        }
        return table
    }()

    private static let forwardBox: [UInt8] = {
        var box = [UInt8](repeating: 0, count: 256)
        for value in 0..<256 {
            let inverted = inverseTable[value]
            box[value] = inverted
                ^ rotateByteLeft(inverted, 1)
                ^ rotateByteLeft(inverted, 2)
                ^ rotateByteLeft(inverted, 3)
                ^ rotateByteLeft(inverted, 4)
                ^ 0x63
        }
        return box
    }()

    private static let inverseBox: [UInt8] = {
        var box = [UInt8](repeating: 0, count: 256)
        for value in 0..<256 {
            box[Int(forwardBox[value])] = UInt8(value)
        }
        return box
    }()

    private static func multiplyTable(_ factor: UInt8) -> [UInt8] {
        var table = [UInt8](repeating: 0, count: 256)
        for value in 0..<256 {
            table[value] = gfMultiply(UInt8(value), factor)
        }
        return table
    }

    private static let mul9 = multiplyTable(9)
    private static let mul11 = multiplyTable(11)
    private static let mul13 = multiplyTable(13)
    private static let mul14 = multiplyTable(14)

    private static func rotateByteLeft(_ value: UInt8, _ amount: UInt8) -> UInt8 {
        (value << amount) | (value >> (8 - amount))
    }

    private static func gfMultiply(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var result: UInt8 = 0
        var x = a
        var y = b
        while y != 0 {
            if y & 0x01 != 0 {
                result ^= x
            }
            let high = x & 0x80
            x = x &<< 1
            if high != 0 {
                x ^= 0x1b
            }
            y >>= 1
        }
        return result
    }

    private static func invert(_ value: UInt8) -> UInt8 {
        if value == 0 {
            return 0
        }
        var result: UInt8 = 1
        var base = value
        var exponent = 254
        while exponent > 0 {
            if exponent & 0x01 != 0 {
                result = gfMultiply(result, base)
            }
            base = gfMultiply(base, base)
            exponent >>= 1
        }
        return result
    }

    private static func expandKey(_ key: [UInt8]) throws -> [[UInt8]] {
        let wordCount = key.count / 4
        let rounds: Int
        switch key.count {
        case 16:
            rounds = 10
        case 24:
            rounds = 12
        case 32:
            rounds = 14
        default:
            throw CookieCloudCryptoError.unsupportedKeyLength(key.count)
        }

        let totalWords = 4 * (rounds + 1)
        var words = [UInt8](repeating: 0, count: totalWords * 4)
        for index in 0..<wordCount * 4 {
            words[index] = key[index]
        }

        var roundConstant: UInt8 = 0x01
        for index in wordCount..<totalWords {
            var temp = Array(words[((index - 1) * 4)..<(index * 4)])
            if index % wordCount == 0 {
                temp = [
                    forwardBox[Int(temp[1])],
                    forwardBox[Int(temp[2])],
                    forwardBox[Int(temp[3])],
                    forwardBox[Int(temp[0])],
                ]
                temp[0] ^= roundConstant
                roundConstant = gfMultiply(roundConstant, 2)
            } else if wordCount > 6, index % wordCount == 4 {
                temp = temp.map { forwardBox[Int($0)] }
            }
            for byteIndex in 0..<4 {
                words[index * 4 + byteIndex] =
                    words[(index - wordCount) * 4 + byteIndex] ^ temp[byteIndex]
            }
        }

        var roundKeys: [[UInt8]] = []
        roundKeys.reserveCapacity(rounds + 1)
        for round in 0...(rounds) {
            roundKeys.append(Array(words[(round * 16)..<((round + 1) * 16)]))
        }
        return roundKeys
    }

    private static func addRoundKey(_ state: inout [UInt8], _ roundKey: [UInt8]) {
        for index in 0..<blockSize {
            state[index] ^= roundKey[index]
        }
    }

    private static func inverseShiftRows(_ state: inout [UInt8]) {
        var output = state
        for row in 1..<4 {
            for column in 0..<4 {
                let source = row + ((column + 4 - row) % 4) * 4
                output[row + column * 4] = state[source]
            }
        }
        state = output
    }

    private static func inverseMixColumns(_ state: inout [UInt8]) {
        for column in 0..<4 {
            let base = column * 4
            let a0 = state[base]
            let a1 = state[base + 1]
            let a2 = state[base + 2]
            let a3 = state[base + 3]
            state[base] = mul14[Int(a0)] ^ mul11[Int(a1)] ^ mul13[Int(a2)] ^ mul9[Int(a3)]
            state[base + 1] = mul9[Int(a0)] ^ mul14[Int(a1)] ^ mul11[Int(a2)] ^ mul13[Int(a3)]
            state[base + 2] = mul13[Int(a0)] ^ mul9[Int(a1)] ^ mul14[Int(a2)] ^ mul11[Int(a3)]
            state[base + 3] = mul11[Int(a0)] ^ mul13[Int(a1)] ^ mul9[Int(a2)] ^ mul14[Int(a3)]
        }
    }

    private static func decryptBlock(_ block: inout [UInt8], roundKeys: [[UInt8]]) {
        var state = block
        addRoundKey(&state, roundKeys[roundKeys.count - 1])
        var round = roundKeys.count - 2
        while round > 0 {
            inverseShiftRows(&state)
            for index in 0..<blockSize {
                state[index] = inverseBox[Int(state[index])]
            }
            addRoundKey(&state, roundKeys[round])
            inverseMixColumns(&state)
            round -= 1
        }
        inverseShiftRows(&state)
        for index in 0..<blockSize {
            state[index] = inverseBox[Int(state[index])]
        }
        addRoundKey(&state, roundKeys[0])
        block = state
    }
}
