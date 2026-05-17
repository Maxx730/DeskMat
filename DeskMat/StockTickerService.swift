import Foundation

// MARK: - Model

struct StockQuote: Identifiable {
    var id: String { symbol }
    let symbol: String
    let price: Double
    let change: Double          // absolute $ change from previous close
    let changePercent: Double   // e.g. 1.35 means +1.35%
    let currency: String
    let isMarketOpen: Bool
}

// MARK: - Yahoo Finance API Response

private struct YFQuoteResponse: Decodable {
    let quoteResponse: QuoteResponse

    struct QuoteResponse: Decodable {
        let result: [YFQuote]
    }

    struct YFQuote: Decodable {
        let symbol: String
        let regularMarketPrice: Double?
        let regularMarketChange: Double?
        let regularMarketChangePercent: Double?
        let currency: String?
        let marketState: String?
    }
}

// MARK: - Service

@Observable
final class StockTickerService {
    var quotes: [StockQuote] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    func fetch(symbols: [String]) async {
        let trimmed = symbols.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return }

        await MainActor.run { isLoading = true }

        let joined = trimmed.joined(separator: ",")
        guard let url = URL(string: "https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(joined)") else {
            await MainActor.run { isLoading = false }
            return
        }

        async let minimumDelay: Void = Task.sleep(for: .milliseconds(500))

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try decode(data)

            _ = try? await minimumDelay

            await MainActor.run {
                quotes = decoded
                errorMessage = nil
                isLoading = false
            }
        } catch {
            _ = try? await minimumDelay
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // Internal so unit tests can call it directly with fixture JSON.
    func decode(_ data: Data) throws -> [StockQuote] {
        let response = try JSONDecoder().decode(YFQuoteResponse.self, from: data)
        return response.quoteResponse.result.compactMap { q in
            guard let price = q.regularMarketPrice else { return nil }
            return StockQuote(
                symbol:        q.symbol,
                price:         price,
                change:        q.regularMarketChange ?? 0,
                changePercent: q.regularMarketChangePercent ?? 0,
                currency:      q.currency ?? "USD",
                isMarketOpen:  q.marketState == "REGULAR"
            )
        }
    }
}

// MARK: - Helpers

extension StockTickerService {
    /// Splits a comma-separated symbol string into a trimmed, non-empty array.
    static func symbols(from csv: String) -> [String] {
        csv.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }
}
