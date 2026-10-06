import XCTest
@testable import RealTimeQuote

@MainActor
final class QuoteEngineTests: XCTestCase {
    func testStartRequestsSubscriptionForSelectedPairAndSeedsPlaceholderSnapshot() async throws {
        let stream = MockExchangeQuoteStream()
        let engine = QuoteEngine(streamFactory: { _, _ in stream })

        try await engine.start(exchange: .coinbase, pair: .btcUSD)

        XCTAssertEqual(stream.startCalls, [StartCall(exchange: .coinbase, pair: .btcUSD)])
        XCTAssertEqual(engine.snapshot.exchange, .coinbase)
        XCTAssertEqual(engine.snapshot.pair, .btcUSD)
        XCTAssertEqual(engine.snapshot.connectionState, .connecting)
    }

    func testSwitchSelectionStopsOldStreamBeforeStartingNewOne() async throws {
        let first = MockExchangeQuoteStream()
        let second = MockExchangeQuoteStream()
        let streams = [first, second]
        var factoryCalls = 0
        let engine = QuoteEngine(streamFactory: { _, _ in
            defer { factoryCalls += 1 }
            return streams[factoryCalls]
        })

        try await engine.start(exchange: .coinbase, pair: .btcUSD)
        try await engine.updateSelection(exchange: .okx, pair: .ethUSD)

        XCTAssertTrue(first.stopCalled)
        XCTAssertEqual(second.startCalls, [StartCall(exchange: .okx, pair: .ethUSD)])
        XCTAssertEqual(engine.snapshot.exchange, .okx)
        XCTAssertEqual(engine.snapshot.pair, .ethUSD)
        XCTAssertEqual(engine.snapshot.connectionState, .connecting)
    }

    func testLateEventsFromReplacedStreamDoNotOverwriteNewSelection() async throws {
        let first = MockExchangeQuoteStream()
        let second = MockExchangeQuoteStream()
        let streams = [first, second]
        var factoryCalls = 0
        let engine = QuoteEngine(streamFactory: { _, _ in
            defer { factoryCalls += 1 }
            return streams[factoryCalls]
        })

        try await engine.start(exchange: .coinbase, pair: .btcUSD)
        first.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 101)))
        await settle()

        try await engine.updateSelection(exchange: .okx, pair: .ethUSD)
        first.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 202)))
        await settle()

        XCTAssertEqual(engine.snapshot.exchange, .okx)
        XCTAssertEqual(engine.snapshot.pair, .ethUSD)
        XCTAssertNil(engine.snapshot.lastPrice)
        XCTAssertEqual(engine.snapshot.connectionState, .connecting)
    }

    func testFailedInitialStartCleansUpFailedStreamAndIgnoresItsLateEvents() async {
        let stream = MockExchangeQuoteStream(startError: MockStreamError.startFailed)
        let engine = QuoteEngine(streamFactory: { _, _ in stream })

        await XCTAssertThrowsErrorAsync(try await engine.start(exchange: .coinbase, pair: .btcUSD))

        stream.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 303)))
        await settle()

        XCTAssertEqual(stream.startCalls, [StartCall(exchange: .coinbase, pair: .btcUSD)])
        XCTAssertTrue(stream.stopCalled)
        XCTAssertEqual(engine.snapshot, .placeholder(for: .btcUSD, exchange: .coinbase))
    }

    func testFailedSelectionStartRestoresPreviousActiveStreamAndSnapshot() async throws {
        let first = MockExchangeQuoteStream()
        let second = MockExchangeQuoteStream(startError: MockStreamError.startFailed)
        let streams = [first, second]
        var factoryCalls = 0
        let engine = QuoteEngine(streamFactory: { _, _ in
            defer { factoryCalls += 1 }
            return streams[factoryCalls]
        })

        try await engine.start(exchange: .coinbase, pair: .btcUSD)
        first.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 404)))
        await waitUntil { engine.snapshot.lastPrice == 404 }

        await XCTAssertThrowsErrorAsync(try await engine.updateSelection(exchange: .okx, pair: .ethUSD))

        XCTAssertFalse(first.stopCalled)
        XCTAssertTrue(second.stopCalled)
        XCTAssertEqual(engine.snapshot, Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 404))

        first.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 505)))
        second.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .okx, pair: .ethUSD, price: 606)))
        await waitUntil { engine.snapshot.lastPrice == 505 }

        XCTAssertEqual(engine.snapshot, Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 505))
    }

    func testDisconnectMarksSnapshotAsReconnectingUntilNewDataArrives() async throws {
        let stream = MockExchangeQuoteStream()
        let engine = QuoteEngine(streamFactory: { _, _ in stream })

        try await engine.start(exchange: .coinbase, pair: .btcUSD)
        stream.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 111)))
        await waitUntil { engine.snapshot.lastPrice == 111 }

        stream.emit(.didDisconnect(.networkFailure))
        await waitUntil { engine.snapshot.connectionState == .reconnecting }

        XCTAssertEqual(engine.snapshot.exchange, .coinbase)
        XCTAssertEqual(engine.snapshot.pair, .btcUSD)
        XCTAssertEqual(engine.snapshot.lastPrice, 111)
        XCTAssertEqual(engine.snapshot.connectionState, .reconnecting)
    }

    func testReconnectConnectEventRestoresLiveStateWithoutDroppingLastQuote() async throws {
        let stream = MockExchangeQuoteStream()
        let engine = QuoteEngine(streamFactory: { _, _ in stream })

        try await engine.start(exchange: .coinbase, pair: .btcUSD)
        stream.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 222)))
        await waitUntil { engine.snapshot.lastPrice == 222 }

        stream.emit(.didDisconnect(.remoteClosed))
        await waitUntil { engine.snapshot.connectionState == .reconnecting }

        stream.emit(.didConnect)
        await waitUntil { engine.snapshot.connectionState == .live }

        XCTAssertEqual(engine.snapshot.lastPrice, 222)
        XCTAssertEqual(engine.snapshot.connectionState, .live)
    }

    func testViewModelRollsBackSelectionAndDoesNotPersistWhenEngineSwitchFails() async throws {
        let settingsStore = InMemoryAppSettingsStore()
        let first = MockExchangeQuoteStream()
        let second = MockExchangeQuoteStream(startError: MockStreamError.startFailed)
        let streams = [first, second]
        var factoryCalls = 0
        let engine = QuoteEngine(streamFactory: { _, _ in
            defer { factoryCalls += 1 }
            return streams[factoryCalls]
        })

        let viewModel = QuoteBoardViewModel(
            initialSelection: AppBootstrapSelection(exchange: .coinbase, pair: .btcUSD),
            settingsStore: settingsStore,
            quoteEngine: engine
        )
        await waitUntil { first.startCalls.count == 1 }

        viewModel.selectExchange(.okx)
        XCTAssertEqual(viewModel.selectedExchange, .okx)

        await waitUntil { second.startCalls.count == 1 }
        await waitUntil { viewModel.selectedExchange == .coinbase }

        XCTAssertEqual(viewModel.selectedExchange, .coinbase)
        XCTAssertEqual(viewModel.selectedPair, .btcUSD)
        XCTAssertEqual(settingsStore.selectedExchange, .coinbase)
        XCTAssertEqual(settingsStore.selectedPair, .btcUSD)
        XCTAssertEqual(viewModel.lastSelectionError, MockStreamError.startFailed.localizedDescription)
    }

    func testOlderStartCompletionCannotInstallAfterNewerSelectionWins() async throws {
        let first = MockExchangeQuoteStream(startBehavior: .suspended)
        let second = MockExchangeQuoteStream()
        let streams = [first, second]
        var factoryCalls = 0
        let engine = QuoteEngine(streamFactory: { _, _ in
            defer { factoryCalls += 1 }
            return streams[factoryCalls]
        })

        let firstTask = Task {
            try await engine.start(exchange: .coinbase, pair: .btcUSD)
        }
        await waitUntil { first.startCalls.count == 1 }

        try await engine.updateSelection(exchange: .okx, pair: .ethUSD)
        first.resumeStart()
        _ = await firstTask.result

        first.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 707)))
        second.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .okx, pair: .ethUSD, price: 808)))
        await waitUntil { engine.snapshot.lastPrice == 808 }

        XCTAssertTrue(first.stopCalled)
        XCTAssertEqual(engine.snapshot, Self.makeSnapshot(exchange: .okx, pair: .ethUSD, price: 808))
    }

    func testViewModelPersistsWholeSelectionTupleWhenOverlappingChangesResolve() async throws {
        let settingsStore = InMemoryAppSettingsStore()
        let initial = MockExchangeQuoteStream()
        let exchangeChange = MockExchangeQuoteStream(startBehavior: .suspended)
        let pairChange = MockExchangeQuoteStream()
        let streams = [initial, exchangeChange, pairChange]
        var factoryCalls = 0
        let engine = QuoteEngine(streamFactory: { _, _ in
            defer { factoryCalls += 1 }
            return streams[factoryCalls]
        })

        let viewModel = QuoteBoardViewModel(
            initialSelection: AppBootstrapSelection(exchange: .coinbase, pair: .btcUSD),
            settingsStore: settingsStore,
            quoteEngine: engine
        )
        await waitUntil { initial.startCalls.count == 1 }

        viewModel.selectExchange(.okx)
        await waitUntil { exchangeChange.startCalls.count == 1 }

        viewModel.selectPair(.ethUSD)
        await waitUntil { pairChange.startCalls.count == 1 }
        await waitUntil {
            settingsStore.selectedExchange == .okx && settingsStore.selectedPair == .ethUSD
        }

        XCTAssertEqual(viewModel.selectedExchange, .okx)
        XCTAssertEqual(viewModel.selectedPair, .ethUSD)
        XCTAssertEqual(settingsStore.selectedExchange, .okx)
        XCTAssertEqual(settingsStore.selectedPair, .ethUSD)
    }

    func testViewModelDoesNotSurfaceStaleInitialStartCancellationAfterNewerSelectionWins() async throws {
        let settingsStore = InMemoryAppSettingsStore()
        let initial = MockExchangeQuoteStream(startBehavior: .suspended)
        let replacement = MockExchangeQuoteStream()
        let streams = [initial, replacement]
        var factoryCalls = 0
        let engine = QuoteEngine(streamFactory: { _, _ in
            defer { factoryCalls += 1 }
            return streams[factoryCalls]
        })

        let viewModel = QuoteBoardViewModel(
            initialSelection: AppBootstrapSelection(exchange: .coinbase, pair: .btcUSD),
            settingsStore: settingsStore,
            quoteEngine: engine
        )
        await waitUntil { initial.startCalls.count == 1 }

        viewModel.selectExchange(.okx)
        await waitUntil { replacement.startCalls.count == 1 }
        initial.resumeStart()
        await waitUntil {
            viewModel.selectedExchange == .okx
                && settingsStore.selectedExchange == .okx
        }

        XCTAssertNil(viewModel.lastSelectionError)
        XCTAssertEqual(viewModel.selectedExchange, .okx)
        XCTAssertEqual(settingsStore.selectedExchange, .okx)
    }

    func testViewModelRetriesInitialStartBeforeSurfacingError() async throws {
        let settingsStore = InMemoryAppSettingsStore()
        let failing = MockExchangeQuoteStream(startError: MockStreamError.startFailed)
        let succeeding = MockExchangeQuoteStream()
        let streams = [failing, succeeding]
        var factoryCalls = 0
        let engine = QuoteEngine(streamFactory: { _, _ in
            defer { factoryCalls += 1 }
            return streams[factoryCalls]
        })

        let viewModel = QuoteBoardViewModel(
            initialSelection: AppBootstrapSelection(exchange: .coinbase, pair: .btcUSD),
            settingsStore: settingsStore,
            quoteEngine: engine,
            startupRetryAttempts: 2,
            startupRetryDelayNanoseconds: 0
        )

        await waitUntil { failing.startCalls.count == 1 }
        await waitUntil { succeeding.startCalls.count == 1 }

        XCTAssertEqual(viewModel.selectedExchange, .coinbase)
        XCTAssertEqual(viewModel.selectedPair, .btcUSD)
        XCTAssertNil(viewModel.lastSelectionError)
    }

    func testSettingsStorePersistsSelectionTupleWithoutLegacySplitKeys() {
        let suiteName = "RealTimeQuoteTests.QuoteEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let writer = UserDefaultsAppSettingsStore(defaults: defaults)
        writer.setSelection(exchange: .okx, pair: .ethUSD)

        let reader = UserDefaultsAppSettingsStore(defaults: defaults)

        XCTAssertEqual(reader.selectedExchange, .okx)
        XCTAssertEqual(reader.selectedPair, .ethUSD)
        XCTAssertNil(defaults.string(forKey: "selectedExchange"))
        XCTAssertNil(defaults.string(forKey: "selectedPair"))
        XCTAssertNotNil(defaults.data(forKey: "selection"))
    }

    func testViewModelTriggersMatchingPriceAlertOnlyOnce() async throws {
        let settingsStore = InMemoryAppSettingsStore()
        let alertStore = InMemoryPriceAlertStore()
        let notificationScheduler = RecordingPriceAlertNotificationScheduler()
        let stream = MockExchangeQuoteStream()
        let engine = QuoteEngine(streamFactory: { _, _ in stream })
        let viewModel = QuoteBoardViewModel(
            initialSelection: AppBootstrapSelection(exchange: .coinbase, pair: .btcUSD),
            settingsStore: settingsStore,
            quoteEngine: engine,
            priceAlertStore: alertStore,
            notificationScheduler: notificationScheduler
        )
        await waitUntil { stream.startCalls.count == 1 }

        viewModel.savePriceAlert(targetPrice: 100, direction: .below)
        stream.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 99)))

        await waitUntilAsync { await notificationScheduler.notificationCount() == 1 }

        XCTAssertNil(viewModel.priceAlert)
        XCTAssertNil(alertStore.alert(for: .coinbase, pair: .btcUSD))
        let firstNotification = await notificationScheduler.firstNotification()
        XCTAssertEqual(firstNotification?.currentPrice, 99)

        stream.emit(.didReceiveSnapshot(Self.makeSnapshot(exchange: .coinbase, pair: .btcUSD, price: 98)))
        await settle()

        let notificationCount = await notificationScheduler.notificationCount()
        XCTAssertEqual(notificationCount, 1)
    }

    private static func makeSnapshot(
        exchange: ExchangeID,
        pair: TradingPair,
        price: Decimal,
        absoluteChange: Decimal? = nil,
        percentChange: Decimal? = nil,
        updatedAt: Date? = nil
    ) -> QuoteSnapshot {
        QuoteSnapshot(
            exchange: exchange,
            pair: pair,
            lastPrice: price,
            absoluteChange: absoluteChange,
            percentChange: percentChange,
            high24h: nil,
            low24h: nil,
            volume24h: nil,
            updatedAt: updatedAt,
            connectionState: .live
        )
    }

    private func settle() async {
        await Task.yield()
        await Task.yield()
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition")
    }

    private func waitUntilAsync(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () async -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous condition")
    }
}

private final class MockExchangeQuoteStream: ExchangeQuoteStreaming {
    let events: AsyncStream<ExchangeStreamEvent>
    private let continuation: AsyncStream<ExchangeStreamEvent>.Continuation
    private(set) var startCalls: [StartCall] = []
    private(set) var stopCalled = false
    private let startBehavior: StartBehavior
    private var startContinuation: CheckedContinuation<Void, Never>?

    init(startError: Error? = nil, startBehavior: StartBehavior = .immediate) {
        if let startError {
            self.startBehavior = .failing(startError)
        } else {
            self.startBehavior = startBehavior
        }
        var continuation: AsyncStream<ExchangeStreamEvent>.Continuation!
        self.events = AsyncStream<ExchangeStreamEvent> {
            continuation = $0
        }
        self.continuation = continuation
    }

    func start(exchange: ExchangeID, pair: TradingPair) async throws {
        startCalls.append(StartCall(exchange: exchange, pair: pair))
        switch startBehavior {
        case .immediate:
            return
        case .failing(let error):
            throw error
        case .suspended:
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }
    }

    func stop() {
        stopCalled = true
    }

    func emit(_ event: ExchangeStreamEvent) {
        continuation.yield(event)
    }

    func resumeStart() {
        startContinuation?.resume()
        startContinuation = nil
    }
}

private struct StartCall: Equatable {
    let exchange: ExchangeID
    let pair: TradingPair
}

private final class InMemoryAppSettingsStore: AppSettingsStore {
    var storedSelection: AppSelection?

    var selectedExchange: ExchangeID {
        get { storedSelection?.exchange ?? .coinbase }
        set { storedSelection = AppSelection(exchange: newValue, pair: selectedPair) }
    }

    var selectedPair: TradingPair {
        get { storedSelection?.pair ?? .btcUSD }
        set { storedSelection = AppSelection(exchange: selectedExchange, pair: newValue) }
    }

    func setSelection(exchange: ExchangeID, pair: TradingPair) {
        storedSelection = AppSelection(exchange: exchange, pair: pair)
    }
}

private final class InMemoryPriceAlertStore: PriceAlertStoring {
    private var alerts: [PriceAlert] = []

    func alert(for exchange: ExchangeID, pair: TradingPair) -> PriceAlert? {
        alerts.first { $0.exchange == exchange && $0.pair == pair }
    }

    func save(_ alert: PriceAlert) {
        alerts.removeAll { $0.exchange == alert.exchange && $0.pair == alert.pair }
        alerts.append(alert)
    }

    func clear(for exchange: ExchangeID, pair: TradingPair) {
        alerts.removeAll { $0.exchange == exchange && $0.pair == pair }
    }
}

private actor RecordingPriceAlertNotificationScheduler: PriceAlertNotificationScheduling {
    struct Notification: Equatable {
        let alert: PriceAlert
        let currentPrice: Decimal
    }

    private(set) var notifications: [Notification] = []

    func requestAuthorization() async {}

    func firstNotification() -> Notification? {
        notifications.first
    }

    func notificationCount() -> Int {
        notifications.count
    }

    func scheduleNotification(for alert: PriceAlert, currentPrice: Decimal) async {
        notifications.append(Notification(alert: alert, currentPrice: currentPrice))
    }
}

private enum MockStreamError: LocalizedError {
    case startFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:
            return "Mock stream failed to start"
        }
    }
}

private enum StartBehavior {
    case immediate
    case suspended
    case failing(Error)
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {}
}
