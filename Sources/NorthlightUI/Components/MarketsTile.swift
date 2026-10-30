import Charts
import NorthlightKit
import SwiftUI

/// Bitcoin and ether in dollars with the change since 00:00 UTC, what a dollar
/// buys, and at large size bitcoin's last week.
struct MarketsTile: View {
    let crypto: Loaded<CryptoMarket>
    let rates: Loaded<ExchangeRates>
    let now: Date
    @Environment(\.widgetSize) private var size

    var body: some View {
        Tile(label: "Markets", trailing: crypto.trailing(asOf: now)) {
            FeedBody(state: crypto.state(asOf: now)) { market in
                VStack(alignment: .leading, spacing: 18) {
                    if size == .small {
                        if let btc = market.quotes.first {
                            QuoteView(quote: btc, prominent: true)
                        }
                        ForEach(market.quotes.dropFirst()) { QuoteView(quote: $0, prominent: false) }
                    } else {
                        HStack(alignment: .top, spacing: 40) {
                            ForEach(market.quotes) { quote in
                                QuoteView(quote: quote, prominent: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if case .ready(let rates) = rates.state(asOf: now) {
                        RatesLine(rates: rates)
                    }
                    if size == .large, market.bitcoinHourly.count > 1 {
                        Sparkline(points: market.bitcoinHourly)
                    }
                }
            }
        }
    }
}

private struct QuoteView: View {
    let quote: CryptoQuote
    let prominent: Bool

    var body: some View {
        let up = quote.change >= 0
        let color = up ? Theme.Palette.green : Theme.Palette.red
        if prominent {
            VStack(alignment: .leading, spacing: 6) {
                Text(quote.symbol)
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.muted)
                Text(quote.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(Theme.Font.tileValue)
                    .foregroundStyle(Theme.Palette.bone)
                    .numericChange(quote.price)
                Label {
                    Text("\(quote.change, format: .percent.precision(.fractionLength(2)).sign(strategy: .always())) today")
                } icon: {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                }
                .font(Theme.Font.caption)
                .foregroundStyle(color)
            }
            .lineLimit(1)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(quote.symbol)
                    .foregroundStyle(Theme.Palette.muted)
                Text(quote.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .foregroundStyle(Theme.Palette.bone)
                    .numericChange(quote.price)
                Text(quote.change, format: .percent.precision(.fractionLength(1)).sign(strategy: .always()))
                    .foregroundStyle(color)
            }
            .font(Theme.Font.caption)
            .monospacedDigit()
            .lineLimit(1)
        }
    }
}

/// What one dollar buys, as the ECB set it on its last publishing day.
private struct RatesLine: View {
    let rates: ExchangeRates
    @Environment(\.widgetSize) private var size

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text("$1")
                .foregroundStyle(Theme.Palette.muted)
            ForEach(rates.perDollar.prefix(size == .small ? 1 : 3), id: \.code) { rate in
                Text("\(rate.rate, format: .number.precision(.significantDigits(4))) \(rate.code)")
                    .foregroundStyle(Theme.Palette.bone)
            }
        }
        .font(Theme.Font.caption)
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// Bitcoin's hourly closes, on a domain padded around the week's range.
private struct Sparkline: View {
    let points: [CryptoMarket.Point]
    @Environment(\.widgetKind) private var kind

    var body: some View {
        let prices = points.map(\.price)
        let low = prices.min() ?? 0, high = prices.max() ?? 1
        let pad = max((high - low) * 0.1, 1)
        let tint = kind.map(Theme.Kind.tint) ?? Theme.Palette.bone
        VStack(alignment: .leading, spacing: 10) {
            Chart(points, id: \.time) { point in
                AreaMark(x: .value("Time", point.time), yStart: .value("Low", low - pad), yEnd: .value("Price", point.price))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.time), y: .value("Price", point.price))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 3))
            }
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            Text("BTC, 7 days: low \(low, format: .currency(code: "USD").precision(.fractionLength(0))), high \(high, format: .currency(code: "USD").precision(.fractionLength(0)))")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.faint)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
