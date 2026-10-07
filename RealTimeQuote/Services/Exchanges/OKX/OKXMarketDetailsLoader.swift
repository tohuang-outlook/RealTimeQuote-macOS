import Foundation

final class OKXMarketDetailsLoader: ExchangeMarketDetailsLoading {
    private let session: URLSession
    private let calendar: Calendar

    init(session: URLSession = .shared, calendar: Calendar = MarketDetailsCalendar.utc) {
        self.session = session
        self.calendar = calendar
    }

    func loadDetails(for exchange: ExchangeID, pair: TradingPair) async throws -> MarketDetailsSnapshot {
        guard exchange == .okx else { return .empty }

        async let ticker = loadTicker(for: pair)
        async let candles = loadDailyCandles(for: pair)

        let (tickerPayload, candlePayload) = try await (ticker, candles)
        let startOfToday = calendar.startOfDay(for: Date())
        let previousCandle = candlePayload
            .filter { candle in
                Date(timeIntervalSince1970: TimeInterval(candle.timestampMilliseconds) / 1_000) < startOfToday
            }
            .sorted { $0.timestampMilliseconds > $1.timestampMilliseconds }
            .first

        return MarketDetailsSnapshot(
            open: tickerPayload.sodUtc0,
            prevClose: previousCandle?.close,
            week52High: nil,
            week52Low: nil,
            marketCap: nil
        )
    }

    func load24HourHistory(for pair: TradingPair) async throws -> PriceHistorySnapshot {
        var components = URLComponents(string: "https://openapi.okx.com/api/v5/market/candles")
        components?.queryItems = [
            URLQueryItem(name: "instId", value: pair.okxInstrumentID),
            URLQueryItem(name: "bar", value: "1H"),
            URLQueryItem(name: "limit", value: "24")
        ]

        guard let url = components?.url else {
            throw MarketDetailsLoaderError.invalidRequest
        }

        let (data, response) = try await session.data(from: url)
        try validate(response: response)
        let payload = try JSONDecoder().decode(OKXCandlesResponse.self, from: data)
        let points = payload.data
            .map {
                PriceHistoryPoint(
                    timestamp: Date(timeIntervalSince1970: TimeInterval($0.timestampMilliseconds) / 1_000),
                    price: $0.close
                )
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard points.count > 1 else {
            throw MarketDetailsLoaderError.missingData
        }

        return PriceHistorySnapshot(exchange: .okx, pair: pair, points: points)
    }

    private func loadTicker(for pair: TradingPair) async throws -> OKXMarketTicker {
        var components = URLComponents(string: "https://openapi.okx.com/api/v5/market/ticker")
        components?.queryItems = [
            URLQueryItem(name: "instId", value: pair.okxInstrumentID)
        ]

        guard let url = components?.url else {
            throw MarketDetailsLoaderError.invalidRequest
        }

        let (data, response) = try await session.data(from: url)
        try validate(response: response)
        let payload = try JSONDecoder().decode(OKXTickerResponse.self, from: data)
        guard let ticker = payload.data.first else {
            throw MarketDetailsLoaderError.missingData
        }
        return ticker
    }

    private func loadDailyCandles(for pair: TradingPair) async throws -> [OKXDailyCandle] {
        var components = URLComponents(string: "https://openapi.okx.com/api/v5/market/candles")
        components?.queryItems = [
            URLQueryItem(name: "instId", value: pair.okxInstrumentID),
            URLQueryItem(name: "bar", value: "1Dutc"),
            URLQueryItem(name: "limit", value: "3")
        ]

        guard let url = components?.url else {
            throw MarketDetailsLoaderError.invalidRequest
        }

        let (data, response) = try await session.data(from: url)
        try validate(response: response)
        let payload = try JSONDecoder().decode(OKXCandlesResponse.self, from: data)
        return payload.data
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw MarketDetailsLoaderError.invalidResponse
        }
    }
}

private struct OKXTickerResponse: Decodable {
    let data: [OKXMarketTicker]
}

private struct OKXMarketTicker: Decodable {
    let sodUtc0: Decimal?

    private enum CodingKeys: String, CodingKey {
        case sodUtc0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sodUtc0 = try container.decodeOptionalDecimal(forKey: .sodUtc0)
    }
}

private struct OKXCandlesResponse: Decodable {
    let data: [OKXDailyCandle]
}

private struct OKXDailyCandle: Decodable {
    let timestampMilliseconds: Int
    let open: Decimal
    let high: Decimal
    let low: Decimal
    let close: Decimal

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        timestampMilliseconds = try OKXDailyCandle.decodeInt(from: &container)
        open = try OKXDailyCandle.decodeDecimal(from: &container)
        high = try OKXDailyCandle.decodeDecimal(from: &container)
        low = try OKXDailyCandle.decodeDecimal(from: &container)
        close = try OKXDailyCandle.decodeDecimal(from: &container)
    }

    private static func decodeInt(from container: inout UnkeyedDecodingContainer) throws -> Int {
        if let stringValue = try? container.decode(String.self),
           let intValue = Int(stringValue) {
            return intValue
        }

        if let intValue = try? container.decode(Int.self) {
            return intValue
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported integer value in OKX candle payload"
        )
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
            debugDescription: "Unsupported decimal value in OKX candle payload"
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeOptionalDecimal(forKey key: Key) throws -> Decimal? {
        guard let stringValue = try decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return Decimal(string: stringValue)
    }
}
