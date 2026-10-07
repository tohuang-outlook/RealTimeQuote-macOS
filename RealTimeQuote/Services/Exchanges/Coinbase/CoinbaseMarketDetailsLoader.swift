import Foundation

final class CoinbaseMarketDetailsLoader: ExchangeMarketDetailsLoading {
    private let session: URLSession
    private let calendar: Calendar

    init(session: URLSession = .shared, calendar: Calendar = MarketDetailsCalendar.utc) {
        self.session = session
        self.calendar = calendar
    }

    func loadDetails(for exchange: ExchangeID, pair: TradingPair) async throws -> MarketDetailsSnapshot {
        guard exchange == .coinbase else { return .empty }

        let candles = try await loadDailyCandles(for: pair)
        let startOfToday = calendar.startOfDay(for: Date())

        let todayCandle = candles.first(where: { candle in
            Date(timeIntervalSince1970: TimeInterval(candle.time)) >= startOfToday
        })
        let previousCandle = candles
            .filter { candle in
                Date(timeIntervalSince1970: TimeInterval(candle.time)) < startOfToday
            }
            .sorted { $0.time > $1.time }
            .first

        return MarketDetailsSnapshot(
            open: todayCandle?.open,
            prevClose: previousCandle?.close,
            week52High: nil,
            week52Low: nil,
            marketCap: nil
        )
    }

    func load24HourHistory(for pair: TradingPair) async throws -> PriceHistorySnapshot {
        let end = Date()
        let start = end.addingTimeInterval(-86_400)

        var components = URLComponents(string: "https://api.exchange.coinbase.com/products/\(pair.coinbaseProductID)/candles")
        components?.queryItems = [
            URLQueryItem(name: "granularity", value: "3600"),
            URLQueryItem(name: "start", value: iso8601Formatter.string(from: start)),
            URLQueryItem(name: "end", value: iso8601Formatter.string(from: end))
        ]

        guard let url = components?.url else {
            throw MarketDetailsLoaderError.invalidRequest
        }

        let (data, response) = try await session.data(from: url)
        try validate(response: response)
        let candles = try JSONDecoder().decode([CoinbaseCandle].self, from: data)
        let points = candles
            .map { PriceHistoryPoint(timestamp: Date(timeIntervalSince1970: TimeInterval($0.time)), price: $0.close) }
            .sorted { $0.timestamp < $1.timestamp }

        guard points.count > 1 else {
            throw MarketDetailsLoaderError.missingData
        }

        return PriceHistorySnapshot(exchange: .coinbase, pair: pair, points: points)
    }

    private func loadDailyCandles(for pair: TradingPair) async throws -> [CoinbaseCandle] {
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -3, to: end) ?? end.addingTimeInterval(-259_200)

        var components = URLComponents(string: "https://api.exchange.coinbase.com/products/\(pair.coinbaseProductID)/candles")
        components?.queryItems = [
            URLQueryItem(name: "granularity", value: "86400"),
            URLQueryItem(name: "start", value: iso8601Formatter.string(from: start)),
            URLQueryItem(name: "end", value: iso8601Formatter.string(from: end))
        ]

        guard let url = components?.url else {
            throw MarketDetailsLoaderError.invalidRequest
        }

        let (data, response) = try await session.data(from: url)
        try validate(response: response)
        return try JSONDecoder().decode([CoinbaseCandle].self, from: data)
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw MarketDetailsLoaderError.invalidResponse
        }
    }

    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

private struct CoinbaseCandle: Decodable {
    let time: Int
    let low: Decimal
    let high: Decimal
    let open: Decimal
    let close: Decimal
    let volume: Decimal

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        time = try container.decode(Int.self)
        low = try CoinbaseCandle.decodeDecimal(from: &container)
        high = try CoinbaseCandle.decodeDecimal(from: &container)
        open = try CoinbaseCandle.decodeDecimal(from: &container)
        close = try CoinbaseCandle.decodeDecimal(from: &container)
        volume = try CoinbaseCandle.decodeDecimal(from: &container)
    }

    private static func decodeDecimal(from container: inout UnkeyedDecodingContainer) throws -> Decimal {
        if let stringValue = try? container.decode(String.self),
           let decimalValue = Decimal(string: stringValue) {
            return decimalValue
        }

        if let doubleValue = try? container.decode(Double.self) {
            return Decimal(doubleValue)
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported decimal value in Coinbase candle payload"
        )
    }
}
