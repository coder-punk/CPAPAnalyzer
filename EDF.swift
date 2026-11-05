import Foundation

struct EDFSignal: Identifiable {
    let id = UUID()
    let label: String
    let unit: String
    let sampleRate: Double
    let samples: [Double]
}
struct EDFRecording: Identifiable {
    let id = UUID()
    let filename: String
    let start: Date?
    let duration: TimeInterval
    let signals: [EDFSignal]
}

enum EDFError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum EDFReader {
    static func parse(_ data: Data, filename: String) throws -> EDFRecording {
        func ascii(_ offset: Int, _ length: Int) throws -> String {
            guard offset >= 0, length >= 0, offset + length <= data.count else { throw EDFError.invalid("EDF-header is onvolledig") }
            return String(decoding: data[offset..<(offset + length)], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        }
        func integer(_ offset: Int, _ length: Int) throws -> Int {
            guard let n = Int(try ascii(offset, length)) else { throw EDFError.invalid("Ongeldig EDF-getal") }; return n
        }
        func decimal(_ offset: Int, _ length: Int) throws -> Double {
            guard let n = Double(try ascii(offset, length)), n.isFinite else { throw EDFError.invalid("Ongeldig EDF-getal") }; return n
        }
        guard data.count >= 256 else { throw EDFError.invalid("Bestand is te klein voor EDF") }
        let headerBytes = try integer(184, 8)
        let declaredRecords = try integer(236, 8)
        let secondsPerRecord = try decimal(244, 8)
        let signalCount = try integer(252, 4)
        guard signalCount > 0, signalCount <= 256, headerBytes >= 256 + signalCount * 256,
              headerBytes <= data.count, secondsPerRecord > 0 else { throw EDFError.invalid("Ongeldige EDF-header") }
        let n = signalCount
        func field(_ base: Int, _ width: Int, _ i: Int) throws -> String { try ascii(base + width * i, width) }
        var cursor = 256
        let labels = try (0..<n).map { try field(cursor, 16, $0) }; cursor += n * 16
        cursor += n * 80
        let units = try (0..<n).map { try field(cursor, 8, $0) }; cursor += n * 8
        let pMin = try (0..<n).map { try Double(field(cursor, 8, $0)) ?? 0 }; cursor += n * 8
        let pMax = try (0..<n).map { try Double(field(cursor, 8, $0)) ?? 0 }; cursor += n * 8
        let dMin = try (0..<n).map { try Double(field(cursor, 8, $0)) ?? 0 }; cursor += n * 8
        let dMax = try (0..<n).map { try Double(field(cursor, 8, $0)) ?? 0 }; cursor += n * 8
        cursor += n * 80
        let perRecord = try (0..<n).map { try Int(field(cursor, 8, $0)) ?? -1 }; cursor += n * 8
        guard perRecord.allSatisfy({ $0 >= 0 && $0 <= 100_000 }) else { throw EDFError.invalid("Ongeldige signaalgrootte") }
        let totalSamples = perRecord.reduce(0, +)
        guard totalSamples > 0, totalSamples <= 2_000_000 else { throw EDFError.invalid("Niet-ondersteunde EDF-recordgrootte") }
        let bytesPerRecord = totalSamples * 2
        let available = (data.count - headerBytes) / bytesPerRecord
        let records = declaredRecords == -1 ? available : min(declaredRecords, available)
        guard records > 0 else { throw EDFError.invalid("Geen complete EDF-records") }
        // Downsample during parsing to cap memory while preserving waveform trends.
        let maxPoints = 30_000
        var values = Array(repeating: [Double](), count: n)
        var seen = Array(repeating: 0, count: n)
        var offset = headerBytes
        for _ in 0..<records {
            for i in 0..<n {
                let count = perRecord[i]
                let strideSize = max(1, (records * count + maxPoints - 1) / maxPoints)
                let scale = dMax[i] == dMin[i] ? 1 : (pMax[i] - pMin[i]) / (dMax[i] - dMin[i])
                for j in 0..<count {
                    if (seen[i] + j) % strideSize == 0 {
                        let low = UInt16(data[offset + 2*j]); let high = UInt16(data[offset + 2*j + 1])
                        let digital = Double(Int16(bitPattern: low | (high << 8)))
                        values[i].append(pMin[i] + (digital - dMin[i]) * scale)
                    }
                }
                seen[i] += count
                offset += count * 2
            }
        }
        let duration = Double(records) * secondsPerRecord
        let signals = (0..<n).map { i in
            EDFSignal(label: labels[i], unit: units[i], sampleRate: Double(values[i].count) / duration, samples: values[i])
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let dateParts = try ascii(168, 8).split(separator: ".")
        let timeParts = try ascii(176, 8).split(separator: ".")
        var start: Date? = nil
        if dateParts.count == 3, timeParts.count == 3,
           let day = Int(dateParts[0]), let month = Int(dateParts[1]), let yy = Int(dateParts[2]),
           let hour = Int(timeParts[0]), let minute = Int(timeParts[1]), let second = Int(timeParts[2]) {
            let year = yy >= 85 ? 1900 + yy : 2000 + yy
            start = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
        }
        return EDFRecording(filename: filename, start: start, duration: duration, signals: signals)
    }
}
