import Darwin
import Foundation
import LayoutSwitcherCore
import LayoutSwitcherLexicon

@main
enum LexiconBenchmarkMain {
    static func main() {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            let initialResidentBytes = residentBytes()
            let english = try MappedLexicon(url: options.englishURL, expectedLanguage: .english)
            let russian = try MappedLexicon(url: options.russianURL, expectedLanguage: .russian)
            let samples: [(MappedLexicon, Language, String)] = [
                (english, .english, "development"),
                (english, .english, "application"),
                (english, .english, "configuration"),
                (english, .english, "unfindable-layout-switcher-token"),
                (russian, .russian, "разработка"),
                (russian, .russian, "приложение"),
                (russian, .russian, "конфигурация"),
                (russian, .russian, "несуществующий-термин-layout-switcher"),
            ]

            for sample in samples {
                _ = sample.0.lookup(sample.2, language: sample.1)
            }

            var durations = [UInt64]()
            durations.reserveCapacity(options.lookups)
            var hits = 0
            let totalStart = DispatchTime.now().uptimeNanoseconds
            for index in 0..<options.lookups {
                let sample = samples[index % samples.count]
                let start = DispatchTime.now().uptimeNanoseconds
                let match = sample.0.lookup(sample.2, language: sample.1)
                durations.append(DispatchTime.now().uptimeNanoseconds - start)
                if match.score != nil { hits += 1 }
            }
            let totalNanoseconds = DispatchTime.now().uptimeNanoseconds - totalStart
            durations.sort()

            let mappedBytes = try fileSize(options.englishURL) + fileSize(options.russianURL)
            let finalResidentBytes = residentBytes()
            let residentDelta = finalResidentBytes > initialResidentBytes
                ? finalResidentBytes - initialResidentBytes
                : 0
            let median = percentile(durations, 0.50)
            let p99 = percentile(durations, 0.99)
            let totalMilliseconds = Double(totalNanoseconds) / 1_000_000
            let memoryAllowance = mappedBytes + 8 * 1_024 * 1_024

            print(String(format: "lookups=%d total=%.3fms median=%.3fµs p99=%.3fµs hits=%d misses=%d mapped=%lluB resident-delta=%lluB",
                         options.lookups,
                         totalMilliseconds,
                         Double(median) / 1_000,
                         Double(p99) / 1_000,
                         hits,
                         options.lookups - hits,
                         mappedBytes,
                         residentDelta))

            guard totalMilliseconds <= options.budgetMilliseconds else {
                throw BenchmarkError.timeBudgetExceeded(totalMilliseconds, options.budgetMilliseconds)
            }
            guard residentDelta <= memoryAllowance else {
                throw BenchmarkError.memoryBudgetExceeded(residentDelta, memoryAllowance)
            }
        } catch {
            FileHandle.standardError.write(Data("LexiconBenchmark: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func percentile(_ sorted: [UInt64], _ percentile: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * percentile).rounded(.up)))
        return sorted[index]
    }

    private static func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else { throw BenchmarkError.unreadableFile(url.path) }
        return UInt64(size)
    }

    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}

private struct Options {
    let englishURL: URL
    let russianURL: URL
    let lookups: Int
    let budgetMilliseconds: Double

    init(arguments: [String]) throws {
        guard arguments.count == 6,
              arguments[2] == "--lookups",
              let lookups = Int(arguments[3]),
              lookups > 0,
              arguments[4] == "--budget-ms",
              let budget = Double(arguments[5]),
              budget >= 0 else {
            throw BenchmarkError.usage
        }
        englishURL = URL(fileURLWithPath: arguments[0])
        russianURL = URL(fileURLWithPath: arguments[1])
        self.lookups = lookups
        budgetMilliseconds = budget
    }
}

private enum BenchmarkError: Error, CustomStringConvertible {
    case usage
    case unreadableFile(String)
    case timeBudgetExceeded(Double, Double)
    case memoryBudgetExceeded(UInt64, UInt64)

    var description: String {
        switch self {
        case .usage:
            return "usage: LexiconBenchmark <en-index> <ru-index> --lookups <count> --budget-ms <milliseconds>"
        case let .unreadableFile(path):
            return "unable to read file size: \(path)"
        case let .timeBudgetExceeded(actual, budget):
            return String(format: "time budget exceeded: %.3fms > %.3fms", actual, budget)
        case let .memoryBudgetExceeded(actual, budget):
            return "resident-memory budget exceeded: \(actual) > \(budget) bytes"
        }
    }
}
