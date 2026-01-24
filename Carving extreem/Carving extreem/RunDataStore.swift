import Combine
import Foundation

@MainActor
final class RunDataStore: ObservableObject {
    @Published private(set) var runs: [RunRecord] = []

    private let folderName = "CarvingRuns"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601FallbackFormatter = ISO8601DateFormatter()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = RunDataStore.iso8601Formatter.date(from: dateString) {
                return date
            }
            if let date = RunDataStore.iso8601FallbackFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date string.")
        }
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RunDataStore.iso8601Formatter.string(from: date))
        }
        loadRuns()
    }

    func loadRuns() {
        let urls = runFiles()
        var loaded: [RunRecord] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let run = try? decoder.decode(RunRecord.self, from: data)
            else { continue }
            loaded.append(run)
        }
        runs = loaded.sorted { $0.date > $1.date }
    }

    func save(run: RunRecord) throws {
        let url = runFileURL(for: run)
        let data = try encoder.encode(run)
        try FileManager.default.createDirectory(at: runsFolderURL(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        loadRuns()
    }

    func runNumber(for date: Date) -> Int {
        let sameDayRuns = runs.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        return (sameDayRuns.map { $0.runNumber }.max() ?? 0) + 1
    }

    private func runFiles() -> [URL] {
        let folder = runsFolderURL()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
    }

    private func runsFolderURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent(folderName, isDirectory: true)
    }

    private func runFileURL(for run: RunRecord) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: run.date)
        let filename = "\(dateString)_run_\(run.runNumber).json"
        return runsFolderURL().appendingPathComponent(filename)
    }
}
