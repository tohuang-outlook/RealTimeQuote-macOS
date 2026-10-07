import XCTest
@testable import RealTimeQuote

final class QuoteBoardPresentationStateTests: XCTestCase {
    func testPriceHistoryReplacesOnlyItsLiveEndpoint() {
        let hourAgo = Date(timeIntervalSince1970: 1_780_177_440)
        let now = Date(timeIntervalSince1970: 1_780_181_040)
        let history = PriceHistorySnapshot(
            exchange: .coinbase,
            pair: .dogeUSD,
            points: [
                PriceHistoryPoint(timestamp: hourAgo, price: Decimal(string: "0.1200")!),
                PriceHistoryPoint(timestamp: hourAgo.addingTimeInterval(1_800), price: Decimal(string: "0.1210")!)
            ]
        )

        let updated = history.updatingLatest(price: Decimal(string: "0.1234"), at: now)

        XCTAssertEqual(updated.points.count, 2)
        XCTAssertEqual(updated.points.first?.price, Decimal(string: "0.1200"))
        XCTAssertEqual(updated.points.last?.price, Decimal(string: "0.1234"))
        XCTAssertEqual(updated.points.last?.timestamp, now)
    }

    func testPriceHistoryDoesNotCreateDataWhenThereAreNoCandles() {
        let updated = PriceHistorySnapshot.empty.updatingLatest(
            price: Decimal(string: "73707.82"),
            at: Date()
        )

        XCTAssertEqual(updated, .empty)
    }

    func testPresentationStateUsesSingleSnapshotIdentityAndFormatsValues() {
        let snapshot = QuoteSnapshot(
            exchange: .coinbase,
            pair: .btcUSD,
            lastPrice: Decimal(string: "73707.82"),
            absoluteChange: Decimal(string: "273.09"),
            percentChange: Decimal(string: "0.37"),
            high24h: Decimal(string: "74172.05"),
            low24h: Decimal(string: "73127.08"),
            volume24h: Decimal(string: "4040.12"),
            updatedAt: Date(timeIntervalSince1970: 1_780_181_040),
            connectionState: .live
        )

        let presentation = QuoteBoardPresentationState(
            snapshot: snapshot,
            marketDetails: MarketDetailsSnapshot(
                open: Decimal(string: "70849.51"),
                prevClose: Decimal(string: "70851.01"),
                week52High: nil,
                week52Low: nil,
                marketCap: nil
            ),
            referenceStats: .empty,
            lastSelectionError: "ignored"
        )

        XCTAssertEqual(presentation.header.symbol, "BTC-USD")
        XCTAssertEqual(presentation.header.exchangeName, "Coinbase")
        XCTAssertEqual(presentation.header.priceText, "$73,707.82")
        XCTAssertEqual(presentation.header.changeAmountText, "+273.09")
        XCTAssertEqual(presentation.header.changePercentText, "+0.37%")
        XCTAssertEqual(presentation.header.changeTone, .positive)
        XCTAssertEqual(
            presentation.stats,
            [
                StatsGridView.Item(label: "Open", value: "$70,849.51", valueColor: .white),
                StatsGridView.Item(label: "High", value: "$74,172.05", valueColor: QuoteBoardTheme.positive),
                StatsGridView.Item(label: "Low", value: "$73,127.08", valueColor: QuoteBoardTheme.negative),
                StatsGridView.Item(label: "Prev Close", value: "$70,851.01", valueColor: .white),
                StatsGridView.Item(label: "52 Wk High", value: "--", valueColor: .white),
                StatsGridView.Item(label: "52 Wk Low", value: "--", valueColor: .white),
                StatsGridView.Item(label: "24H Volume", value: "4,040.12", valueColor: .white),
                StatsGridView.Item(label: "Market Cap", value: "--", valueColor: .white)
            ]
        )
        XCTAssertEqual(presentation.connectionState, .live)
        XCTAssertEqual(presentation.lastSelectionError, "ignored")
    }

    func testPresentationStateUsesFourFractionDigitsForLowPricedAssets() {
        let snapshot = QuoteSnapshot(
            exchange: .coinbase,
            pair: .dogeUSD,
            lastPrice: Decimal(string: "0.1234"),
            absoluteChange: Decimal(string: "0.0006"),
            percentChange: Decimal(string: "0.49"),
            high24h: Decimal(string: "0.1299"),
            low24h: Decimal(string: "0.1201"),
            volume24h: nil,
            updatedAt: nil,
            connectionState: .live
        )

        let presentation = QuoteBoardPresentationState(
            snapshot: snapshot,
            marketDetails: MarketDetailsSnapshot(
                open: Decimal(string: "0.1228"),
                prevClose: Decimal(string: "0.1220"),
                week52High: nil,
                week52Low: nil,
                marketCap: nil
            ),
            referenceStats: .empty,
            lastSelectionError: nil
        )

        XCTAssertEqual(presentation.header.priceText, "$0.1234")
        XCTAssertEqual(presentation.header.changeAmountText, "+0.0006")
        XCTAssertEqual(presentation.stats[0].value, "$0.1228")
        XCTAssertEqual(presentation.stats[1].value, "$0.1299")
        XCTAssertEqual(presentation.stats[2].value, "$0.1201")
        XCTAssertEqual(presentation.stats[3].value, "$0.1220")
    }
}
