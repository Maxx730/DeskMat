import Testing
import Foundation
@testable import DeskMat

// MARK: - Initial State

struct StockTickerInitialStateTests {

    @Test func initialStateIsEmpty() {
        let service = StockTickerService()
        #expect(service.quotes.isEmpty)
        #expect(service.isLoading == false)
        #expect(service.errorMessage == nil)
    }
}

// MARK: - Decode

struct StockTickerDecodeTests {

    private func makeService() -> StockTickerService { StockTickerService() }

    // MARK: Valid responses

    @Test func decodesSymbolPriceAndChange() throws {
        let json = """
        {
          "quoteResponse": {
            "result": [{
              "symbol": "AAPL",
              "regularMarketPrice": 185.20,
              "regularMarketChange": 2.35,
              "regularMarketChangePercent": 1.285,
              "currency": "USD",
              "marketState": "REGULAR"
            }]
          }
        }
        """.data(using: .utf8)!

        let quotes = try makeService().decode(json)
        #expect(quotes.count == 1)
        let q = try #require(quotes.first)
        #expect(q.symbol == "AAPL")
        #expect(q.price == 185.20)
        #expect(q.change == 2.35)
        #expect(q.changePercent == 1.285)
        #expect(q.currency == "USD")
        #expect(q.isMarketOpen == true)
    }

    @Test func decodesMultipleSymbols() throws {
        let json = """
        {
          "quoteResponse": {
            "result": [
              { "symbol": "AAPL", "regularMarketPrice": 185.0, "regularMarketChange": 1.0,
                "regularMarketChangePercent": 0.5, "currency": "USD", "marketState": "REGULAR" },
              { "symbol": "MSFT", "regularMarketPrice": 420.0, "regularMarketChange": -3.0,
                "regularMarketChangePercent": -0.7, "currency": "USD", "marketState": "CLOSED" }
            ]
          }
        }
        """.data(using: .utf8)!

        let quotes = try makeService().decode(json)
        #expect(quotes.count == 2)
        #expect(quotes[0].symbol == "AAPL")
        #expect(quotes[1].symbol == "MSFT")
    }

    // MARK: Market state

    @Test func regularMarketStateIsOpen() throws {
        let json = makeJSON(symbol: "TSLA", marketState: "REGULAR")
        let quotes = try makeService().decode(json)
        #expect(quotes.first?.isMarketOpen == true)
    }

    @Test func closedMarketStateIsNotOpen() throws {
        let json = makeJSON(symbol: "TSLA", marketState: "CLOSED")
        let quotes = try makeService().decode(json)
        #expect(quotes.first?.isMarketOpen == false)
    }

    @Test func preMarketStateIsNotOpen() throws {
        let json = makeJSON(symbol: "TSLA", marketState: "PRE")
        let quotes = try makeService().decode(json)
        #expect(quotes.first?.isMarketOpen == false)
    }

    @Test func postMarketStateIsNotOpen() throws {
        let json = makeJSON(symbol: "TSLA", marketState: "POST")
        let quotes = try makeService().decode(json)
        #expect(quotes.first?.isMarketOpen == false)
    }

    // MARK: Optional fields

    @Test func missingChangeDefaultsToZero() throws {
        let json = """
        {
          "quoteResponse": {
            "result": [{
              "symbol": "GOOG",
              "regularMarketPrice": 175.0,
              "currency": "USD",
              "marketState": "CLOSED"
            }]
          }
        }
        """.data(using: .utf8)!

        let quotes = try makeService().decode(json)
        let q = try #require(quotes.first)
        #expect(q.change == 0)
        #expect(q.changePercent == 0)
    }

    @Test func missingCurrencyDefaultsToUSD() throws {
        let json = """
        {
          "quoteResponse": {
            "result": [{
              "symbol": "GOOG",
              "regularMarketPrice": 175.0,
              "marketState": "CLOSED"
            }]
          }
        }
        """.data(using: .utf8)!

        let quotes = try makeService().decode(json)
        #expect(quotes.first?.currency == "USD")
    }

    @Test func missingPriceSkipsQuote() throws {
        let json = """
        {
          "quoteResponse": {
            "result": [{
              "symbol": "UNKNOWN",
              "currency": "USD",
              "marketState": "CLOSED"
            }]
          }
        }
        """.data(using: .utf8)!

        let quotes = try makeService().decode(json)
        #expect(quotes.isEmpty)
    }

    // MARK: Edge cases

    @Test func emptyResultArrayReturnsEmptyQuotes() throws {
        let json = """
        { "quoteResponse": { "result": [] } }
        """.data(using: .utf8)!

        let quotes = try makeService().decode(json)
        #expect(quotes.isEmpty)
    }

    @Test func malformedJSONThrows() {
        let bad = "not json at all".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try makeService().decode(bad)
        }
    }

    @Test func negativeChangeDecodedCorrectly() throws {
        let json = makeJSON(symbol: "META", price: 500.0, change: -12.5, changePercent: -2.4)
        let quotes = try makeService().decode(json)
        let q = try #require(quotes.first)
        #expect(q.change == -12.5)
        #expect(q.changePercent == -2.4)
    }

    // MARK: - Helpers

    private func makeJSON(
        symbol: String,
        price: Double = 100.0,
        change: Double = 0.0,
        changePercent: Double = 0.0,
        currency: String = "USD",
        marketState: String = "CLOSED"
    ) -> Data {
        """
        {
          "quoteResponse": {
            "result": [{
              "symbol": "\(symbol)",
              "regularMarketPrice": \(price),
              "regularMarketChange": \(change),
              "regularMarketChangePercent": \(changePercent),
              "currency": "\(currency)",
              "marketState": "\(marketState)"
            }]
          }
        }
        """.data(using: .utf8)!
    }
}

// MARK: - CSV Symbol Parsing

struct StockTickerSymbolParsingTests {

    @Test func splitsCommaSeparatedSymbols() {
        let result = StockTickerService.symbols(from: "AAPL,MSFT,TSLA")
        #expect(result == ["AAPL", "MSFT", "TSLA"])
    }

    @Test func trimsWhitespaceAroundSymbols() {
        let result = StockTickerService.symbols(from: " AAPL , MSFT , TSLA ")
        #expect(result == ["AAPL", "MSFT", "TSLA"])
    }

    @Test func uppercasesSymbols() {
        let result = StockTickerService.symbols(from: "aapl,msft")
        #expect(result == ["AAPL", "MSFT"])
    }

    @Test func emptyStringReturnsEmptyArray() {
        let result = StockTickerService.symbols(from: "")
        #expect(result.isEmpty)
    }

    @Test func filtersEmptyTokensFromTrailingComma() {
        let result = StockTickerService.symbols(from: "AAPL,MSFT,")
        #expect(result == ["AAPL", "MSFT"])
    }

    @Test func singleSymbolReturnsOneElement() {
        let result = StockTickerService.symbols(from: "GOOG")
        #expect(result == ["GOOG"])
    }
}

// MARK: - StockQuote Model

struct StockQuoteModelTests {

    @Test func idEqualsSymbol() {
        let q = StockQuote(symbol: "AAPL", price: 185, change: 1, changePercent: 0.5,
                           currency: "USD", isMarketOpen: true)
        #expect(q.id == "AAPL")
    }
}
