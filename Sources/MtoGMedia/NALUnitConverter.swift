import Foundation

public enum NALUnitError: Error {
    case malformedLengthPrefix
    case malformedAnnexB
}

public enum NALUnitConverter {
    private static let startCode = Data([0, 0, 0, 1])

    public static func annexB(fromLengthPrefixed data: Data, lengthBytes: Int = 4) throws -> Data {
        guard (1...4).contains(lengthBytes) else { throw NALUnitError.malformedLengthPrefix }
        var output = Data()
        var offset = 0
        while offset < data.count {
            guard offset + lengthBytes <= data.count else { throw NALUnitError.malformedLengthPrefix }
            var length = 0
            for index in 0..<lengthBytes {
                length = (length << 8) | Int(data[offset + index])
            }
            offset += lengthBytes
            guard length > 0, offset + length <= data.count else { throw NALUnitError.malformedLengthPrefix }
            output.append(startCode)
            output.append(data[offset..<(offset + length)])
            offset += length
        }
        return output
    }

    public static func lengthPrefixed(fromAnnexB data: Data) throws -> Data {
        let units = try nalUnits(fromAnnexB: data)
        var output = Data()
        for unit in units {
            guard unit.count <= Int(UInt32.max) else { throw NALUnitError.malformedAnnexB }
            let length = UInt32(unit.count)
            output.append(UInt8((length >> 24) & 0xFF))
            output.append(UInt8((length >> 16) & 0xFF))
            output.append(UInt8((length >> 8) & 0xFF))
            output.append(UInt8(length & 0xFF))
            output.append(unit)
        }
        return output
    }

    public static func nalUnits(fromAnnexB data: Data) throws -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(offset: Int, length: Int)] = []
        var index = 0
        while index + 3 <= bytes.count {
            if index + 4 <= bytes.count && bytes[index...index + 3] == [0, 0, 0, 1] {
                starts.append((index, 4))
                index += 4
            } else if bytes[index...index + 2] == [0, 0, 1] {
                starts.append((index, 3))
                index += 3
            } else {
                index += 1
            }
        }
        guard !starts.isEmpty, starts[0].offset == 0 else { throw NALUnitError.malformedAnnexB }
        return try starts.enumerated().map { position, start in
            let payloadStart = start.offset + start.length
            let payloadEnd = position + 1 < starts.count ? starts[position + 1].offset : bytes.count
            guard payloadEnd > payloadStart else { throw NALUnitError.malformedAnnexB }
            return Data(bytes[payloadStart..<payloadEnd])
        }
    }

    public static func annexB(parameterSets: [Data]) -> Data {
        parameterSets.reduce(into: Data()) { output, parameterSet in
            output.append(startCode)
            output.append(parameterSet)
        }
    }
}
