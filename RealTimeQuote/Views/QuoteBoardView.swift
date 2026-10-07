import SwiftUI

enum QuoteBoardTheme {
    static let backgroundGradient = LinearGradient(
        colors: [
            Color.black,
            Color(red: 0.08, green: 0.08, blue: 0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardFill = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let cardStroke = Color.white.opacity(0.10)
    static let cardShadow = Color.black.opacity(0.35)
    static let panelFill = Color.white.opacity(0.045)
    static let panelStroke = Color.white.opacity(0.08)
    static let badgeFill = Color.white.opacity(0.05)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.45)
    static let primaryText = Color.white.opacity(0.92)
    static let errorText = Color(red: 1.0, green: 0.52, blue: 0.52)
    static let positive = Color(red: 0.25, green: 0.88, blue: 0.56)
    static let caution = Color(red: 1.0, green: 0.76, blue: 0.24)
    static let negative = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let neutral = Color.white.opacity(0.72)

    static let cardCornerRadius: CGFloat = 28
    static let panelCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 12
    static let outerPadding: CGFloat = 18
    static let contentHorizontalPadding: CGFloat = 28
    static let contentVerticalPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 22
    static let controlSpacing: CGFloat = 14
    static let compactSpacing: CGFloat = 8

    static func regularFont(size: CGFloat) -> Font {
        .custom("Helvetica Neue", size: size)
    }

    static func semiboldFont(size: CGFloat) -> Font {
        .custom("Helvetica Neue", size: size)
    }

    static func boldFont(size: CGFloat) -> Font {
        .custom("Helvetica Neue Bold", size: size)
    }

    static func heavyFont(size: CGFloat) -> Font {
        .custom("Helvetica Neue Heavy", size: size)
    }
}

struct QuoteBoardPresentationState: Equatable {
    let header: PriceHeaderView.Content
    let stats: [StatsGridView.Item]
    let connectionState: ConnectionState
    let lastSelectionError: String?

    init(
        snapshot: QuoteSnapshot,
        marketDetails: MarketDetailsSnapshot,
        referenceStats: ReferenceStatsSnapshot,
        lastSelectionError: String?
    ) {
        header = PriceHeaderView.Content(
            symbol: snapshot.displaySymbol,
            exchangeName: snapshot.exchange.displayName,
            priceText: Self.currencyText(snapshot.lastPrice),
            changeAmountText: Self.changeAmountText(snapshot.absoluteChange),
            changePercentText: Self.changePercentText(snapshot.percentChange),
            secondaryLineText: Self.secondaryLineText(snapshot.updatedAt),
            changeTone: Self.changeTone(snapshot.absoluteChange)
        )
        stats = [
            StatsGridView.Item(
                label: "Open",
                value: Self.currencyText(marketDetails.open),
                valueColor: .white
            ),
            StatsGridView.Item(
                label: "High",
                value: Self.currencyText(snapshot.high24h),
                valueColor: QuoteBoardTheme.positive
            ),
            StatsGridView.Item(
                label: "Low",
                value: Self.currencyText(snapshot.low24h),
                valueColor: QuoteBoardTheme.negative
            ),
            StatsGridView.Item(
                label: "Prev Close",
                value: Self.currencyText(marketDetails.prevClose),
                valueColor: .white
            ),
            StatsGridView.Item(
                label: "52 Wk High",
                value: Self.currencyText(referenceStats.week52High),
                valueColor: .white
            ),
            StatsGridView.Item(
                label: "52 Wk Low",
                value: Self.currencyText(referenceStats.week52Low),
                valueColor: .white
            ),
            StatsGridView.Item(
                label: "24H Volume",
                value: Self.volumeText(snapshot.volume24h),
                valueColor: .white
            ),
            StatsGridView.Item(
                label: "Market Cap",
                value: Self.marketCapText(referenceStats.marketCap),
                valueColor: .white
            )
        ]
        self.connectionState = snapshot.connectionState
        self.lastSelectionError = lastSelectionError
    }

    private static func changeTone(_ absoluteChange: Decimal?) -> PriceHeaderView.ChangeTone {
        guard let absoluteChange else { return .neutral }
        if absoluteChange > 0 { return .positive }
        if absoluteChange < 0 { return .negative }
        return .neutral
    }

    private static func currencyText(_ value: Decimal?) -> String {
        QuotePriceFormatter.currencyText(value)
    }

    private static func volumeText(_ value: Decimal?) -> String {
        guard let value else { return "--" }
        return volumeFormatter.string(from: value as NSDecimalNumber) ?? "--"
    }

    private static func marketCapText(_ value: Decimal?) -> String {
        guard let value else { return "--" }

        let trillion = Decimal(string: "1000000000000")!
        let billion = Decimal(string: "1000000000")!
        let million = Decimal(string: "1000000")!
        let thousand = Decimal(string: "1000")!

        switch value {
        case let value where value >= trillion:
            return abbreviatedText(value / trillion, suffix: "T")
        case let value where value >= billion:
            return abbreviatedText(value / billion, suffix: "B")
        case let value where value >= million:
            return abbreviatedText(value / million, suffix: "M")
        case let value where value >= thousand:
            return abbreviatedText(value / thousand, suffix: "K")
        default:
            return QuotePriceFormatter.currencyText(value)
        }
    }

    private static func changeAmountText(_ absolute: Decimal?) -> String {
        QuotePriceFormatter.signedAmountText(absolute)
    }

    private static func changePercentText(_ percent: Decimal?) -> String {
        guard let percent else { return "--" }
        return percentFormatter.string(from: percent as NSDecimalNumber) ?? "--"
    }

    private static func secondaryLineText(_ updatedAt: Date?) -> String {
        guard let updatedAt else { return "Open, Mid Price --" }
        return "Open, Mid Price \(secondaryLineFormatter.string(from: updatedAt))"
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positiveSuffix = "%"
        formatter.negativeSuffix = "%"
        return formatter
    }()

    private static let volumeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let secondaryLineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd HH:mm z"
        return formatter
    }()

    private static func abbreviatedText(_ value: Decimal, suffix: String) -> String {
        let number = NSDecimalNumber(decimal: value)
        let text = abbreviatedNumberFormatter.string(from: number) ?? "--"
        return "\(text)\(suffix)"
    }

    private static let abbreviatedNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter
    }()
}

private struct QuoteBoardLayoutMetrics {
    let contentHorizontalPadding: CGFloat
    let contentVerticalPadding: CGFloat
    let topChromeInset: CGFloat
    let sectionSpacing: CGFloat
    let controlSpacing: CGFloat
    let statsSpacing: CGFloat
    let heroPriceFontSize: CGFloat
    let statsColumnWidth: CGFloat
    let statsColumnCount: Int

    static func make(for size: CGSize) -> QuoteBoardLayoutMetrics {
        let width = max(size.width, WindowStyler.minimumSize.width)
        let height = max(size.height, WindowStyler.minimumSize.height)
        let widthProgress = min(max((width - WindowStyler.minimumSize.width) / 130, 0), 1)
        let heightProgress = min(max((height - WindowStyler.minimumSize.height) / 90, 0), 1)
        let progress = max(widthProgress, heightProgress)

        return QuoteBoardLayoutMetrics(
            contentHorizontalPadding: 20 + (10 * progress),
            contentVerticalPadding: 12 + (8 * progress),
            topChromeInset: 0,
            sectionSpacing: 16 + (8 * progress),
            controlSpacing: 12 + (6 * progress),
            statsSpacing: 8 + (4 * progress),
            heroPriceFontSize: 42 + (22 * progress),
            statsColumnWidth: 300 + (72 * progress),
            statsColumnCount: 2
        )
    }
}

struct QuoteBoardView: View {
    @ObservedObject var viewModel: QuoteBoardViewModel
    @State private var isPriceAlertEditorPresented = false

    var body: some View {
        let presentation = QuoteBoardPresentationState(
            snapshot: viewModel.snapshot,
            marketDetails: viewModel.marketDetails,
            referenceStats: viewModel.referenceStats,
            lastSelectionError: viewModel.lastSelectionError
        )

        GeometryReader { geometry in
            let metrics = QuoteBoardLayoutMetrics.make(for: geometry.size)

            ZStack {
                QuoteBoardTheme.cardFill
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    HStack(alignment: .top, spacing: metrics.controlSpacing) {
                        ExchangePickerView(selection: exchangeSelection)
                        TradingPairPickerView(selection: pairSelection)
                        Spacer(minLength: 0)
                        priceAlertButton
                        ConnectionBadgeView(state: presentation.connectionState)
                    }

                    terminalBody(
                        presentation: presentation,
                        metrics: metrics
                    )
                }
                .padding(.leading, metrics.contentHorizontalPadding)
                .padding(.trailing, metrics.contentHorizontalPadding)
                .padding(.bottom, metrics.contentVerticalPadding)
                .padding(.top, metrics.topChromeInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isPriceAlertEditorPresented) {
            PriceAlertEditorView(
                exchange: viewModel.selectedExchange,
                pair: viewModel.selectedPair,
                currentPrice: viewModel.snapshot.lastPrice,
                existingAlert: viewModel.priceAlert,
                onSave: { targetPrice, direction in
                    viewModel.savePriceAlert(targetPrice: targetPrice, direction: direction)
                },
                onClear: {
                    viewModel.clearPriceAlert()
                }
            )
        }
    }

    private var exchangeSelection: Binding<ExchangeID> {
        Binding(
            get: { viewModel.selectedExchange },
            set: { viewModel.selectExchange($0) }
        )
    }

    private var pairSelection: Binding<TradingPair> {
        Binding(
            get: { viewModel.selectedPair },
            set: { viewModel.selectPair($0) }
        )
    }

    private var priceAlertButton: some View {
        Button {
            isPriceAlertEditorPresented = true
        } label: {
            Label(
                viewModel.priceAlert == nil ? "Alert" : "Alert Set",
                systemImage: viewModel.priceAlert == nil ? "bell" : "bell.fill"
            )
            .font(QuoteBoardTheme.regularFont(size: 12))
            .foregroundStyle(viewModel.priceAlert == nil ? QuoteBoardTheme.primaryText : QuoteBoardTheme.caution)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(viewModel.priceAlert == nil ? QuoteBoardTheme.badgeFill : QuoteBoardTheme.caution.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(viewModel.priceAlert == nil ? QuoteBoardTheme.cardStroke : QuoteBoardTheme.caution.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Configure price alert")
    }

    @ViewBuilder
    private func terminalQuoteColumn(
        presentation: QuoteBoardPresentationState,
        metrics: QuoteBoardLayoutMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            PriceHeaderView(
                content: presentation.header,
                heroPriceFontSize: metrics.heroPriceFontSize
            )

            PriceSparklineView(history: viewModel.priceHistory)
        }
    }

    @ViewBuilder
    private func terminalFieldsColumn(
        presentation: QuoteBoardPresentationState,
        metrics: QuoteBoardLayoutMetrics
    ) -> some View {
        StatsGridView(
            items: presentation.stats,
            spacing: metrics.statsSpacing,
            numberOfColumns: metrics.statsColumnCount
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func terminalBody(
        presentation: QuoteBoardPresentationState,
        metrics: QuoteBoardLayoutMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .top, spacing: metrics.sectionSpacing) {
                terminalQuoteColumn(
                    presentation: presentation,
                    metrics: metrics
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                terminalFieldsColumn(
                    presentation: presentation,
                    metrics: metrics
                )
                .frame(width: metrics.statsColumnWidth, alignment: .topLeading)
            }
        }
    }
}

private struct PriceAlertEditorView: View {
    let exchange: ExchangeID
    let pair: TradingPair
    let currentPrice: Decimal?
    let existingAlert: PriceAlert?
    let onSave: (Decimal, PriceAlertDirection) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var targetText: String
    @State private var direction: PriceAlertDirection

    init(
        exchange: ExchangeID,
        pair: TradingPair,
        currentPrice: Decimal?,
        existingAlert: PriceAlert?,
        onSave: @escaping (Decimal, PriceAlertDirection) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.exchange = exchange
        self.pair = pair
        self.currentPrice = currentPrice
        self.existingAlert = existingAlert
        self.onSave = onSave
        self.onClear = onClear
        _targetText = State(initialValue: Self.targetText(existingAlert?.targetPrice ?? currentPrice))
        _direction = State(initialValue: existingAlert?.direction ?? .above)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Set price alert")
                    .font(QuoteBoardTheme.boldFont(size: 20))
                Text("\(pair.displaySymbol(for: exchange)) on \(exchange.displayName)")
                    .font(QuoteBoardTheme.regularFont(size: 13))
                    .foregroundStyle(QuoteBoardTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger when price is")
                    .font(QuoteBoardTheme.regularFont(size: 12))
                    .foregroundStyle(QuoteBoardTheme.secondaryText)

                Picker("Direction", selection: $direction) {
                    ForEach(PriceAlertDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Target price (USD)")
                    .font(QuoteBoardTheme.regularFont(size: 12))
                    .foregroundStyle(QuoteBoardTheme.secondaryText)

                TextField("Target price", text: $targetText)
                    .textFieldStyle(.roundedBorder)
                    .font(QuoteBoardTheme.regularFont(size: 15))
            }

            if let currentPrice {
                Text("Current price: \(Self.currencyText(currentPrice))")
                    .font(QuoteBoardTheme.regularFont(size: 12))
                    .foregroundStyle(QuoteBoardTheme.tertiaryText)
            }

            HStack {
                if existingAlert != nil {
                    Button("Clear") {
                        onClear()
                        dismiss()
                    }
                    .foregroundStyle(QuoteBoardTheme.errorText)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save alert") {
                    guard let targetPrice else { return }
                    onSave(targetPrice, direction)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(targetPrice == nil)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(QuoteBoardTheme.cardFill)
    }

    private var targetPrice: Decimal? {
        let normalizedTarget = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = Decimal(string: normalizedTarget, locale: Locale(identifier: "en_US_POSIX")), target > 0 else {
            return nil
        }
        return target
    }

    private static func targetText(_ price: Decimal?) -> String {
        guard let price else { return "" }
        return NSDecimalNumber(decimal: price).stringValue
    }

    private static func currencyText(_ value: Decimal) -> String {
        QuotePriceFormatter.currencyText(value)
    }
}
