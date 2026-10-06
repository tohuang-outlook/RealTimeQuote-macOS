import Combine
import Foundation
import UserNotifications

@MainActor
final class QuoteBoardViewModel: ObservableObject {
    @Published private(set) var snapshot: QuoteSnapshot
    @Published private(set) var marketDetails: MarketDetailsSnapshot
    @Published private(set) var referenceStats: ReferenceStatsSnapshot
    @Published private(set) var selectedExchange: ExchangeID
    @Published private(set) var selectedPair: TradingPair
    @Published private(set) var lastSelectionError: String?
    @Published private(set) var priceAlert: PriceAlert?

    private let quoteEngine: QuoteEngine
    private let marketDetailsLoader: ExchangeMarketDetailsLoading
    private let referenceStatsLoader: ReferenceStatsLoading
    private let settingsStore: AppSettingsStore
    private let priceAlertStore: PriceAlertStoring
    private let notificationScheduler: PriceAlertNotificationScheduling
    private let startupRetryAttempts: Int
    private let startupRetryDelayNanoseconds: UInt64
    private var cancellables = Set<AnyCancellable>()
    private var selectionAttempt: UInt64 = 0
    private var marketDetailsTask: Task<Void, Never>?
    private var referenceStatsTask: Task<Void, Never>?

    static let preview = QuoteBoardViewModel(
        snapshot: QuoteSnapshot.placeholder(for: .btcUSD, exchange: .coinbase)
    )

    init(
        initialSelection: AppBootstrapSelection,
        settingsStore: AppSettingsStore,
        quoteEngine: QuoteEngine,
        marketDetailsLoader: ExchangeMarketDetailsLoading = NoOpExchangeMarketDetailsLoader(),
        referenceStatsLoader: ReferenceStatsLoading = NoOpReferenceStatsLoader(),
        priceAlertStore: PriceAlertStoring = UserDefaultsPriceAlertStore(),
        notificationScheduler: PriceAlertNotificationScheduling = UserNotificationPriceAlertScheduler(),
        startupRetryAttempts: Int = 3,
        startupRetryDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        let selectedExchange = initialSelection.exchange
        let selectedPair = initialSelection.pair

        self.quoteEngine = quoteEngine
        self.marketDetailsLoader = marketDetailsLoader
        self.referenceStatsLoader = referenceStatsLoader
        self.settingsStore = settingsStore
        self.priceAlertStore = priceAlertStore
        self.notificationScheduler = notificationScheduler
        self.startupRetryAttempts = startupRetryAttempts
        self.startupRetryDelayNanoseconds = startupRetryDelayNanoseconds
        self.selectedExchange = selectedExchange
        self.selectedPair = selectedPair
        self.snapshot = quoteEngine.snapshot
        self.marketDetails = .empty
        self.referenceStats = .empty
        self.priceAlert = priceAlertStore.alert(for: selectedExchange, pair: selectedPair)

        quoteEngine.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.handleSnapshot(snapshot)
            }
            .store(in: &cancellables)

        let attempt = selectionAttempt
        Task {
            do {
                try await self.startupConnect(exchange: selectedExchange, pair: selectedPair)
                self.refreshMarketDetails(exchange: selectedExchange, pair: selectedPair)
                self.refreshReferenceStats(pair: selectedPair)
            } catch {
                guard attempt == self.selectionAttempt else { return }
                guard !(error is CancellationError) else { return }
                self.lastSelectionError = error.localizedDescription
            }
        }
    }

    init(snapshot: QuoteSnapshot) {
        self.quoteEngine = QuoteEngine(initialSnapshot: snapshot, streamFactory: { _, _ in PreviewExchangeQuoteStream() })
        self.marketDetailsLoader = NoOpExchangeMarketDetailsLoader()
        self.referenceStatsLoader = NoOpReferenceStatsLoader()
        self.settingsStore = Self.makePreviewSettingsStore()
        self.priceAlertStore = UserDefaultsPriceAlertStore(defaults: UserDefaults(suiteName: "RealTimeQuote.QuoteBoardViewModel.preview.alerts") ?? .standard)
        self.notificationScheduler = NoOpPriceAlertNotificationScheduler()
        self.startupRetryAttempts = 1
        self.startupRetryDelayNanoseconds = 0
        self.selectedExchange = snapshot.exchange
        self.selectedPair = snapshot.pair
        self.snapshot = snapshot
        self.marketDetails = .empty
        self.referenceStats = .empty
        self.priceAlert = nil

        quoteEngine.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.handleSnapshot(snapshot)
            }
            .store(in: &cancellables)
    }

    func selectExchange(_ exchange: ExchangeID) {
        guard exchange != selectedExchange else { return }

        let previousExchange = selectedExchange
        let previousPair = selectedPair
        let previousMarketDetails = marketDetails
        let previousReferenceStats = referenceStats
        let previousPriceAlert = priceAlert
        selectionAttempt &+= 1
        let attempt = selectionAttempt

        selectedExchange = exchange
        marketDetails = .empty
        referenceStats = .empty
        priceAlert = priceAlertStore.alert(for: exchange, pair: previousPair)
        lastSelectionError = nil

        Task {
            do {
                try await quoteEngine.updateSelection(exchange: exchange, pair: previousPair)
                guard attempt == self.selectionAttempt else { return }
                self.settingsStore.setSelection(exchange: exchange, pair: previousPair)
                self.refreshMarketDetails(exchange: exchange, pair: previousPair)
                self.refreshReferenceStats(pair: previousPair)
            } catch {
                guard attempt == self.selectionAttempt else { return }
                self.selectedExchange = previousExchange
                self.selectedPair = previousPair
                self.marketDetails = previousMarketDetails
                self.referenceStats = previousReferenceStats
                self.priceAlert = previousPriceAlert
                self.lastSelectionError = error.localizedDescription
            }
        }
    }

    func selectPair(_ pair: TradingPair) {
        guard pair != selectedPair else { return }

        let previousExchange = selectedExchange
        let previousPair = selectedPair
        let previousMarketDetails = marketDetails
        let previousReferenceStats = referenceStats
        let previousPriceAlert = priceAlert
        selectionAttempt &+= 1
        let attempt = selectionAttempt

        selectedPair = pair
        marketDetails = .empty
        referenceStats = .empty
        priceAlert = priceAlertStore.alert(for: previousExchange, pair: pair)
        lastSelectionError = nil

        Task {
            do {
                try await quoteEngine.updateSelection(exchange: previousExchange, pair: pair)
                guard attempt == self.selectionAttempt else { return }
                self.settingsStore.setSelection(exchange: previousExchange, pair: pair)
                self.refreshMarketDetails(exchange: previousExchange, pair: pair)
                self.refreshReferenceStats(pair: pair)
            } catch {
                guard attempt == self.selectionAttempt else { return }
                self.selectedExchange = previousExchange
                self.selectedPair = previousPair
                self.marketDetails = previousMarketDetails
                self.referenceStats = previousReferenceStats
                self.priceAlert = previousPriceAlert
                self.lastSelectionError = error.localizedDescription
            }
        }
    }

    func savePriceAlert(targetPrice: Decimal, direction: PriceAlertDirection) {
        let alert = PriceAlert(
            exchange: selectedExchange,
            pair: selectedPair,
            targetPrice: targetPrice,
            direction: direction
        )
        priceAlertStore.save(alert)
        priceAlert = alert
        Task {
            await notificationScheduler.requestAuthorization()
        }
    }

    func clearPriceAlert() {
        priceAlertStore.clear(for: selectedExchange, pair: selectedPair)
        priceAlert = nil
    }

    private func handleSnapshot(_ snapshot: QuoteSnapshot) {
        self.snapshot = snapshot
        evaluatePriceAlert(for: snapshot)
    }

    private func evaluatePriceAlert(for snapshot: QuoteSnapshot) {
        guard
            let priceAlert,
            snapshot.connectionState == .live,
            snapshot.exchange == priceAlert.exchange,
            snapshot.pair == priceAlert.pair,
            let currentPrice = snapshot.lastPrice,
            priceAlert.isTriggered(by: currentPrice)
        else {
            return
        }

        priceAlertStore.clear(for: priceAlert.exchange, pair: priceAlert.pair)
        self.priceAlert = nil

        Task {
            await notificationScheduler.scheduleNotification(for: priceAlert, currentPrice: currentPrice)
        }
    }

    private func refreshMarketDetails(exchange: ExchangeID, pair: TradingPair) {
        marketDetailsTask?.cancel()
        marketDetailsTask = Task { [weak self] in
            guard let self else { return }

            do {
                let details = try await self.marketDetailsLoader.loadDetails(for: exchange, pair: pair)
                guard !Task.isCancelled else { return }
                guard self.selectedExchange == exchange, self.selectedPair == pair else { return }
                self.marketDetails = details
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                guard self.selectedExchange == exchange, self.selectedPair == pair else { return }
                self.marketDetails = .empty
            }
        }
    }

    private func refreshReferenceStats(pair: TradingPair) {
        referenceStatsTask?.cancel()
        referenceStatsTask = Task { [weak self] in
            guard let self else { return }

            do {
                let stats = try await self.referenceStatsLoader.loadStats(for: pair)
                guard !Task.isCancelled else { return }
                guard self.selectedPair == pair else { return }
                self.referenceStats = stats
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                guard self.selectedPair == pair else { return }
                self.referenceStats = .empty
            }
        }
    }

    private static func makePreviewSettingsStore() -> AppSettingsStore {
        let defaults = UserDefaults(suiteName: "RealTimeQuote.QuoteBoardViewModel.preview") ?? .standard
        defaults.removePersistentDomain(forName: "RealTimeQuote.QuoteBoardViewModel.preview")
        return UserDefaultsAppSettingsStore(defaults: defaults)
    }

    private func startupConnect(exchange: ExchangeID, pair: TradingPair) async throws {
        let attempts = max(1, startupRetryAttempts)
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                try await quoteEngine.start(exchange: exchange, pair: pair)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < attempts else { break }
                if startupRetryDelayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: startupRetryDelayNanoseconds)
                } else {
                    await Task.yield()
                }
            }
        }

        throw lastError ?? StartupConnectError.unknown
    }
}

private enum StartupConnectError: LocalizedError {
    case unknown
}

private final class PreviewExchangeQuoteStream: ExchangeQuoteStreaming {
    let events = AsyncStream<ExchangeStreamEvent> { _ in }

    func start(exchange: ExchangeID, pair: TradingPair) async throws {}

    func stop() {}
}

protocol PriceAlertNotificationScheduling {
    func requestAuthorization() async
    func scheduleNotification(for alert: PriceAlert, currentPrice: Decimal) async
}

final class UserNotificationPriceAlertScheduler: PriceAlertNotificationScheduling {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func requestAuthorization() async {
        _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound])
    }

    func scheduleNotification(for alert: PriceAlert, currentPrice: Decimal) async {
        do {
            let content = UNMutableNotificationContent()
            content.title = "\(alert.pair.displaySymbol(for: alert.exchange)) price alert"
            content.body = "Price is now \(alert.direction.title.lowercased()) \(Self.currencyText(alert.targetPrice)): \(Self.currencyText(currentPrice))"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: alert.id.uuidString,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            try await notificationCenter.add(request)
        } catch {
            return
        }
    }

    private static func currencyText(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? value.description
    }
}

private final class NoOpPriceAlertNotificationScheduler: PriceAlertNotificationScheduling {
    func requestAuthorization() async {}

    func scheduleNotification(for alert: PriceAlert, currentPrice: Decimal) async {}
}
