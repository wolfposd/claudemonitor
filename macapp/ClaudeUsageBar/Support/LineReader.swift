import Foundation

/// Minimal buffered line reader so large `.jsonl` log files are never loaded fully into memory.
struct LineReader: Sequence, IteratorProtocol {
    private let handle: FileHandle
    private var buffer = Data()
    private let chunkSize = 1 << 16
    private var atEOF = false

    init?(path: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        self.handle = handle
    }

    mutating func next() -> String? {
        while true {
            if let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            if atEOF {
                if buffer.isEmpty { return nil }
                let lineData = buffer
                buffer = Data()
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                atEOF = true
            } else {
                buffer.append(chunk)
            }
        }
    }

    func close() {
        try? handle.close()
    }
}
