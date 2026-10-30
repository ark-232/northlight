import Foundation

/// A coin's last trade in US dollars against the day's opening price.
public struct CryptoQuote: Codable, Sendable, Equatable, Identifiable {
    public var symbol: String
    public var price: Double
    /// Kraken's opening price for the UTC day, so the change is since 00:00 UTC.
    public var open: Double

    public var id: String { symbol }
    public var change: Double { open > 0 ? (price - open) / open : 0 }

    public init(symbol: String, price: Double, open: Double) {
        self.symbol = symbol; self.price = price; self.open = open
    }
}

/// Bitcoin and Ether now, and bitcoin's hourly closes for the sparkline.
public struct CryptoMarket: Codable, Sendable, Equatable {
    public struct Point: Codable, Sendable, Equatable {
        public var time: Date
        public var price: Double
        public init(time: Date, price: Double) { self.time = time; self.price = price }
    }

    public var quotes: [CryptoQuote]
    /// The last week of bitcoin's hourly closes, oldest first.
    public var bitcoinHourly: [Point]

    public init(quotes: [CryptoQuote], bitcoinHourly: [Point]) { self.quotes = quotes; self.bitcoinHourly = bitcoinHourly }
}

/// What one US dollar buys, from the European Central Bank's daily reference rates.
public struct ExchangeRates: Codable, Sendable, Equatable {
    public struct Rate: Codable, Sendable, Equatable {
        public var code: String
        public var rate: Double
        public init(code: String, rate: Double) { self.code = code; self.rate = rate }
    }

    /// The ECB publishing day, as Frankfurter writes it.
    public var day: String
    public var perDollar: [Rate]

    public init(day: String, perDollar: [Rate]) { self.day = day; self.perDollar = perDollar }
}

public enum MarketsParsing {
    /// Kraken writes prices as strings and times as numbers in the same arrays.
    private enum Value: Decodable {
        case number(Double), text(String)
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { self = .number(d) } else { self = .text(try c.decode(String.self)) }
        }
        var double: Double? {
            switch self {
            case .number(let d): d
            case .text(let s): Double(s)
            }
        }
    }

    private struct Envelope<Result: Decodable>: Decodable {
        var error: [String]
        var result: Result?
    }

    private struct Ticker: Decodable {
        var c: [String]
        var o: String
    }

    /// Kraken's own names for the pairs asked for.
    static let pairs = [("XXBTZUSD", "BTC"), ("XETHZUSD", "ETH")]

    private static func result<R: Decodable>(_ type: R.Type, from data: Data) throws -> R {
        let envelope = try decodeFeed(Envelope<R>.self, from: data)
        if !envelope.error.isEmpty { throw FeedError.refused(envelope.error.joined(separator: ", ")) }
        guard let result = envelope.result else { throw FeedError.decode("no result") }
        return result
    }

    public static func quotes(from data: Data) throws -> [CryptoQuote] {
        let tickers = try result([String: Ticker].self, from: data)
        return pairs.compactMap { pair, symbol in
            guard let ticker = tickers[pair], let price = ticker.c.first.flatMap(Double.init), let open = Double(ticker.o) else { return nil }
            return CryptoQuote(symbol: symbol, price: price, open: open)
        }
    }

    /// Each candle is [time, open, high, low, close, vwap, volume, count].
    public static func closes(from data: Data) throws -> [CryptoMarket.Point] {
        let candles = try result([String: CandlesOrLast].self, from: data)
        return (candles[pairs[0].0]?.rows ?? []).compactMap { row in
            guard row.count > 4, let time = row[0].double, let close = row[4].double else { return nil }
            return CryptoMarket.Point(time: Date(timeIntervalSince1970: time), price: close)
        }
    }

    /// The OHLC result holds the pair's candles beside a "last" timestamp.
    private enum CandlesOrLast: Decodable {
        case candles([[Value]]), last
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            self = (try? c.decode([[Value]].self)).map(CandlesOrLast.candles) ?? .last
        }
        var rows: [[Value]]? { if case .candles(let rows) = self { rows } else { nil } }
    }

    private struct Frankfurter: Decodable {
        var date: String
        var rates: [String: Double]
    }

    public static func rates(from data: Data, order: [String]) throws -> ExchangeRates {
        let payload = try decodeFeed(Frankfurter.self, from: data)
        return ExchangeRates(day: payload.date, perDollar: order.compactMap { code in payload.rates[code].map { .init(code: code, rate: $0) } })
    }
}

extension HTTP {
    /// Kraken's public market data, keyless: the ticker for both coins, then a week
    /// of bitcoin's hourly candles.
    public func crypto() async throws -> CryptoMarket {
        let base = "https://api.kraken.com/0/public/"
        async let ticker = data(makeURL(base + "Ticker", ["pair": "XBTUSD,ETHUSD"]), accept: "application/json")
        async let candles = data(makeURL(base + "OHLC", ["pair": "XBTUSD", "interval": "60"]), accept: "application/json")
        return CryptoMarket(quotes: try MarketsParsing.quotes(from: try await ticker),
                            bitcoinHourly: Array(try MarketsParsing.closes(from: try await candles).suffix(7 * 24)))
    }

    /// Frankfurter's ECB reference rates against the dollar, keyless. The ECB has no
    /// lari rate, so GEL is not asked for.
    public func exchangeRates() async throws -> ExchangeRates {
        let codes = ["EUR", "GBP", "JPY"]
        return try MarketsParsing.rates(from: await data(makeURL("https://api.frankfurter.dev/v1/latest",
                                                                 ["base": "USD", "symbols": codes.joined(separator: ",")]),
                                                         accept: "application/json"),
                                        order: codes)
    }
}
