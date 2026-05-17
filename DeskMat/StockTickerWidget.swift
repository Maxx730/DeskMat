import SwiftUI

struct StockTickerWidget: View {
    static let cellCount = 2
    private let refreshInterval: TimeInterval = 5 * 60

    @State private var service = StockTickerService()
    @AppStorage("showLabels")                 private var showLabels = true
    @AppStorage("stockTickerSymbols")         private var symbolsCSV = "AAPL,MSFT,GOOGL"
    @AppStorage("stockTickerCycleInterval")   private var cycleInterval = 5.0

    private var symbols: [String] {
        StockTickerService.symbols(from: symbolsCSV)
    }

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(
                cells: Self.cellCount,
                isLoading: service.isLoading,
                onRefresh: { await service.fetch(symbols: symbols) }
            ) {
                if service.quotes.isEmpty {
                    QuotePlaceholderView()
                } else {
                    TimelineView(.periodic(from: .now, by: cycleInterval)) { ctx in
                        QuoteView(quote: service.quotes[cycleIndex(for: ctx.date)])
                    }
                }
            }
            .task(id: symbolsCSV) {
                while !Task.isCancelled {
                    await service.fetch(symbols: symbols)
                    try? await Task.sleep(for: .seconds(refreshInterval))
                }
            }
            .onTapGesture { openCurrentQuote() }

            if showLabels {
                Text(Strings.Widgets.stockTicker)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
                    .truncationMode(.tail)
            }
        }
    }

    // Derives the visible index purely from wall-clock time so there is no
    // extra @State to synchronise — the TimelineView drives everything.
    private func cycleIndex(for date: Date) -> Int {
        guard service.quotes.count > 1 else { return 0 }
        let slot = Int(date.timeIntervalSinceReferenceDate / cycleInterval)
        return slot % service.quotes.count
    }

    private func openCurrentQuote() {
        let idx = cycleIndex(for: .now)
        let symbol = service.quotes.indices.contains(idx) ? service.quotes[idx].symbol
                   : symbols.first ?? "AAPL"
        guard let url = URL(string: "https://finance.yahoo.com/quote/\(symbol)") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Quote display

private struct QuoteView: View {
    let quote: StockQuote

    private var changeColor: Color {
        if quote.changePercent > 0 { return .green }
        if quote.changePercent < 0 { return .red }
        return .white.opacity(0.5)
    }

    private var arrow: String {
        if quote.changePercent > 0 { return "arrow.up" }
        if quote.changePercent < 0 { return "arrow.down" }
        return "minus"
    }

    private var priceFormatted: String {
        let prefix = currencyPrefix(quote.currency)
        return String(format: "\(prefix)%.2f", quote.price)
    }

    private var changeFormatted: String {
        let sign = quote.change >= 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", quote.changePercent)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(quote.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(priceFormatted)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: arrow)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(changeColor)

                Text(changeFormatted)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(changeColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Circle()
                    .fill(quote.isMarketOpen ? Color.green : Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 10)
    }

    private func currencyPrefix(_ code: String) -> String {
        switch code {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "CAD": return "CA$"
        case "AUD": return "A$"
        default:    return "\(code) "
        }
    }
}

// MARK: - Placeholder (before first fetch)

private struct QuotePlaceholderView: View {
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.Widgets.StockTicker.symbolPlaceholder)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                Text(Strings.Widgets.StockTicker.pricePlaceholder)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: "minus")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                Text(Strings.Widgets.StockTicker.changePlaceholder)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 10)
    }
}
