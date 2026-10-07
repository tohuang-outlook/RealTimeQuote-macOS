import Foundation

struct PriceHistoryPoint: Equatable, Identifiable {
    let timestamp: Date
    let price: Decimal

    var id: Date { timestamp }
}

struct PriceHistorySnapshot: Equatable {
    let exchange: ExchangeID?
    let pair: TradingPair?
    let points: [PriceHistoryPoint]

    static let empty = PriceHistorySnapshot(exchange: nil, pair: nil, points: [])

    func updatingLatest(price: Decimal?, at date: Date?) -> PriceHistorySnapshot {
        guard let price, let date, !points.isEmpty else { return self }

        var updatedPoints = points
        updatedPoints[updatedPoints.count - 1] = PriceHistoryPoint(timestamp: date, price: price)
        return PriceHistorySnapshot(exchange: exchange, pair: pair, points: updatedPoints)
    }
}

struct QuoteSnapshot: Equatable {
    let exchange: ExchangeID
    let pair: TradingPair
    let lastPrice: Decimal?
    let absoluteChange: Decimal?
    let percentChange: Decimal?
    let high24h: Decimal?
    let low24h: Decimal?
    let volume24h: Decimal?
    let updatedAt: Date?
    let connectionState: ConnectionState

    var displaySymbol: String {
        pair.displaySymbol(for: exchange)
    }

    static func placeholder(for pair: TradingPair, exchange: ExchangeID) -> QuoteSnapshot {
        QuoteSnapshot(
            exchange: exchange,
            pair: pair,
            lastPrice: nil,
            absoluteChange: nil,
            percentChange: nil,
            high24h: nil,
            low24h: nil,
            volume24h: nil,
            updatedAt: nil,
            connectionState: .connecting
        )
    }
}
