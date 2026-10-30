import Foundation
import Testing
@testable import NorthlightKit

/// Kraken's public ticker and hourly candles and Frankfurter's dollar rates,
/// saved on 20 Oct 2026. The candle fixture is cut to its last 48 hours.

@Test func theTickerReadsBitcoinAndEtherWithTodaysOpen() throws {
    let quotes = try MarketsParsing.quotes(from: fixture("kraken-ticker"))
    #expect(quotes.map(\.symbol) == ["BTC", "ETH"])
    #expect(quotes[0].price == 82_059.5)
    #expect(quotes[0].open == 81_843)
    #expect(abs(quotes[0].change - 0.0026453) < 0.0000001)
    #expect(quotes[1].price == 2_411.67)
    #expect(quotes[1].open == 2_405.43)
}

@Test func aKrakenErrorIsTheFeedsReason() {
    let json = #"{"error":["EQuery:Unknown asset pair"],"result":{}}"#
    #expect(throws: FeedError.refused("EQuery:Unknown asset pair")) {
        try MarketsParsing.quotes(from: Data(json.utf8))
    }
}

@Test func hourlyCandlesKeepTheirCloses() throws {
    let closes = try MarketsParsing.closes(from: fixture("kraken-ohlc"))
    #expect(closes.count == 48)
    #expect(closes.first == CryptoMarket.Point(time: Date(timeIntervalSince1970: 1_792_299_600), price: 81_629.1))
    #expect(closes.last == CryptoMarket.Point(time: Date(timeIntervalSince1970: 1_792_468_800), price: 82_059.5))
}

@Test func ratesComeInTheOrderAsked() throws {
    let rates = try MarketsParsing.rates(from: fixture("frankfurter"), order: ["EUR", "GBP", "JPY"])
    #expect(rates.day == "2026-10-19")
    #expect(rates.perDollar.map(\.code) == ["EUR", "GBP", "JPY"])
    #expect(rates.perDollar.map(\.rate) == [0.89087, 0.75016, 158.24])
}
