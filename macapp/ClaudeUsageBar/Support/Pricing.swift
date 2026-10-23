import Foundation

/// Per-million-token USD pricing for Claude model families, used to estimate spend
/// in the "System Verbose" dashboard style. Cache-write and cache-read tokens are
/// both billed at the one cache rate tracked per model here.
enum Pricing {
    private struct Rates {
        let input: Double
        let cache: Double
        let output: Double
    }

    private static let rates: [(match: String, rates: Rates)] = [
        ("haiku", Rates(input: 0.1, cache: 0.01, output: 0.5)),
        ("sonnet", Rates(input: 2, cache: 0.1, output: 10)),
        ("opus", Rates(input: 4, cache: 0.2, output: 20)),
        ("fable", Rates(input: 10, cache: 0.25, output: 50)),
    ]

    /// Estimated cost in USD, or 0 for a model name that matches none of the tiers above.
    static func cost(model: String?, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        guard let model = model?.lowercased(),
              let rates = rates.first(where: { model.contains($0.match) })?.rates else {
            return 0
        }
        let million = 1_000_000.0
        return Double(input) / million * rates.input
            + Double(output) / million * rates.output
            + Double(cacheWrite + cacheRead) / million * rates.cache
    }
}
