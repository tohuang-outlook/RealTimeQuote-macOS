import Foundation

struct AppBootstrapSelection {
    let exchange: ExchangeID
    let pair: TradingPair
}

enum AppBootstrapSelectionResolver {
    static func resolve(
        settingsStore: AppSettingsStore,
        config: RuntimeConfig?
    ) -> AppBootstrapSelection {
        let fallback = AppBootstrapSelection(exchange: .coinbase, pair: .btcUSD)
        let enabledExchanges = config?.defaults?.enabledExchanges ?? ExchangeID.allCases

        let fallbackExchange = enabledExchanges.contains(.coinbase) ? .coinbase : (enabledExchanges.first ?? .coinbase)
        let fallbackSelection = AppBootstrapSelection(exchange: fallbackExchange, pair: fallback.pair)

        let configSelection = AppBootstrapSelection(
            exchange: config?.defaults?.exchange ?? fallbackSelection.exchange,
            pair: config?.defaults?.pair ?? fallbackSelection.pair
        )

        if let storedSelection = settingsStore.storedSelection, enabledExchanges.contains(storedSelection.exchange) {
            return AppBootstrapSelection(exchange: storedSelection.exchange, pair: storedSelection.pair)
        }

        if enabledExchanges.contains(configSelection.exchange) {
            return configSelection
        }

        return fallbackSelection
    }
}

@MainActor
final class AppDependencies: ObservableObject {
    private let settingsStore: AppSettingsStore
    private let config: RuntimeConfig?

    init(settingsStore: AppSettingsStore, config: RuntimeConfig?) {
        self.settingsStore = settingsStore
        self.config = config
    }

    func makeQuoteBoardViewModel() -> QuoteBoardViewModel {
        let selection = AppBootstrapSelectionResolver.resolve(
            settingsStore: settingsStore,
            config: config
        )
        let currentSelection = settingsStore.storedSelection

        if currentSelection?.exchange != selection.exchange || currentSelection?.pair != selection.pair {
            settingsStore.setSelection(exchange: selection.exchange, pair: selection.pair)
        }

        let quoteEngine = QuoteEngine(
            initialSnapshot: .placeholder(for: selection.pair, exchange: selection.exchange),
            streamFactory: { [config] exchange, _ in
                switch exchange {
                case .coinbase:
                    return CoinbaseQuoteStream(config: config?.coinbase)
                case .okx:
                    return OKXQuoteStream(config: config?.okx)
                }
            }
        )

        return QuoteBoardViewModel(
            initialSelection: selection,
            settingsStore: settingsStore,
            quoteEngine: quoteEngine,
            marketDetailsLoader: DefaultExchangeMarketDetailsLoader(),
            referenceStatsLoader: CoinGeckoReferenceStatsLoader(config: config?.coinGecko),
            priceHistoryLoader: DefaultPriceHistoryLoader()
        )
    }

    static func live() -> AppDependencies {
        let settingsStore = UserDefaultsAppSettingsStore()
        let config = try? RuntimeConfigLoader().load().config
        return AppDependencies(settingsStore: settingsStore, config: config)
    }
}
