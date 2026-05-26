import Foundation

// Modern Messages.app stores the message body in `message.attributedBody` as an
// NSArchiver/typedstream-encoded NSAttributedString — *not* NSKeyedArchiver.
// NSKeyedUnarchiver therefore cannot decode it. We scan the blob for the first
// NSString payload and extract its UTF-8 bytes.
enum AttributedBody {
    static func extractText(from data: Data) -> String? {
        guard let range = data.range(of: Data("NSString".utf8)) else { return nil }
        var i = range.upperBound

        // After "NSString" the typedstream emits class metadata then a `+` (0x2B)
        // opcode followed by a variable-length integer giving the byte count.
        while i < data.endIndex {
            if data[i] == 0x2B {
                i += 1
                guard let (length, after) = readVarLength(data, at: i) else { return nil }
                guard after + length <= data.endIndex else { return nil }
                let bytes = data[after..<(after + length)]
                if let s = String(data: Data(bytes), encoding: .utf8) { return s }
                return String(data: Data(bytes), encoding: .isoLatin1)
            }
            i += 1
        }
        return nil
    }

    private static func readVarLength(_ data: Data, at start: Data.Index) -> (Int, Data.Index)? {
        guard start < data.endIndex else { return nil }
        let first = data[start]
        var idx = start + 1
        let value: Int
        switch first {
        case 0x81:
            guard idx + 2 <= data.endIndex else { return nil }
            value = Int(UInt16(data[idx]) | (UInt16(data[idx + 1]) << 8))
            idx += 2
        case 0x82:
            guard idx + 4 <= data.endIndex else { return nil }
            var v: UInt32 = 0
            for k in 0..<4 { v |= UInt32(data[idx + k]) << (8 * k) }
            value = Int(v)
            idx += 4
        case 0x83:
            guard idx + 8 <= data.endIndex else { return nil }
            var v: UInt64 = 0
            for k in 0..<8 { v |= UInt64(data[idx + k]) << (8 * k) }
            value = Int(v)
            idx += 8
        default:
            value = Int(first)
        }
        return (value, idx)
    }
}
