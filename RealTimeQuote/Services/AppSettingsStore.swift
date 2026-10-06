import Foundation

struct AppSelection: Codable, Equatable {
    let exchange: ExchangeID
    let pair: TradingPair
}

protocol AppSettingsStore: AnyObject {
    var selectedExchange: ExchangeID { get set }
    var selectedPair: TradingPair { get set }
    var storedSelection: AppSelection? { get }

    func setSelection(exchange: ExchangeID, pair: TradingPair)
}

final class UserDefaultsAppSettingsStore: AppSettingsStore {
    private enum Keys {
        static let selection = "selection"
        static let legacySelectedExchange = "selectedExchange"
        static let legacySelectedPair = "selectedPair"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedExchange: ExchangeID {
        get {
            storedSelection?.exchange ?? .coinbase
        }
        set {
            setSelection(exchange: newValue, pair: selectedPair)
        }
    }

    var selectedPair: TradingPair {
        get {
            storedSelection?.pair ?? .btcUSD
        }
        set {
            setSelection(exchange: selectedExchange, pair: newValue)
        }
    }

    var storedSelection: AppSelection? {
        if
            let data = defaults.data(forKey: Keys.selection),
            let storedSelection = try? decoder.decode(AppSelection.self, from: data)
        {
            return storedSelection
        }

        let exchange = defaults.string(forKey: Keys.legacySelectedExchange).flatMap(ExchangeID.init(rawValue:))
        let pair = defaults.string(forKey: Keys.legacySelectedPair).flatMap(TradingPair.init(persistenceKey:))

        if let exchange, let pair {
            return AppSelection(exchange: exchange, pair: pair)
        }

        if let pair {
            return AppSelection(exchange: .coinbase, pair: pair)
        }

        return nil
    }

    func setSelection(exchange: ExchangeID, pair: TradingPair) {
        let storedSelection = AppSelection(exchange: exchange, pair: pair)
        if let data = try? encoder.encode(storedSelection) {
            defaults.set(data, forKey: Keys.selection)
            defaults.removeObject(forKey: Keys.legacySelectedExchange)
            defaults.removeObject(forKey: Keys.legacySelectedPair)
        }
    }
}

enum PriceAlertDirection: String, CaseIterable, Codable, Identifiable {
    case above
    case below

    var id: String { rawValue }

    var title: String {
        switch self {
        case .above:
            return "Above"
        case .below:
            return "Below"
        }
    }
}

struct PriceAlert: Codable, Equatable, Identifiable {
    let id: UUID
    let exchange: ExchangeID
    let pair: TradingPair
    let targetPrice: Decimal
    let direction: PriceAlertDirection

    init(
        id: UUID = UUID(),
        exchange: ExchangeID,
        pair: TradingPair,
        targetPrice: Decimal,
        direction: PriceAlertDirection
    ) {
        self.id = id
        self.exchange = exchange
        self.pair = pair
        self.targetPrice = targetPrice
        self.direction = direction
    }

    func isTriggered(by price: Decimal) -> Bool {
        switch direction {
        case .above:
            return price >= targetPrice
        case .below:
            return price <= targetPrice
        }
    }
}

protocol PriceAlertStoring: AnyObject {
    func alert(for exchange: ExchangeID, pair: TradingPair) -> PriceAlert?
    func save(_ alert: PriceAlert)
    func clear(for exchange: ExchangeID, pair: TradingPair)
}

final class UserDefaultsPriceAlertStore: PriceAlertStoring {
    private enum Keys {
        static let alerts = "priceAlerts"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func alert(for exchange: ExchangeID, pair: TradingPair) -> PriceAlert? {
        alerts.first { $0.exchange == exchange && $0.pair == pair }
    }

    func save(_ alert: PriceAlert) {
        var updatedAlerts = alerts.filter { $0.exchange != alert.exchange || $0.pair != alert.pair }
        updatedAlerts.append(alert)
        persist(updatedAlerts)
    }

    func clear(for exchange: ExchangeID, pair: TradingPair) {
        persist(alerts.filter { $0.exchange != exchange || $0.pair != pair })
    }

    private var alerts: [PriceAlert] {
        guard
            let data = defaults.data(forKey: Keys.alerts),
            let decodedAlerts = try? decoder.decode([PriceAlert].self, from: data)
        else {
            return []
        }
        return decodedAlerts
    }

    private func persist(_ alerts: [PriceAlert]) {
        guard let data = try? encoder.encode(alerts) else { return }
        defaults.set(data, forKey: Keys.alerts)
    }
}
