import Charts
import SwiftUI

enum QuotePriceFormatter {
    static func currencyText(_ value: Decimal?) -> String {
        guard let value else { return "--" }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = fractionDigits(for: value)
        formatter.maximumFractionDigits = fractionDigits(for: value)
        formatter.usesGroupingSeparator = true
        return formatter.string(from: value as NSDecimalNumber) ?? "--"
    }

    static func signedAmountText(_ value: Decimal?) -> String {
        guard let value else { return "--" }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        formatter.minimumFractionDigits = fractionDigits(for: value)
        formatter.maximumFractionDigits = fractionDigits(for: value)
        formatter.usesGroupingSeparator = true
        return formatter.string(from: value as NSDecimalNumber) ?? "--"
    }

    private static func fractionDigits(for value: Decimal) -> Int {
        let magnitude = value < 0 ? -value : value
        return magnitude < 10 ? 4 : 2
    }
}

struct PriceHeaderView: View {
    enum ChangeTone: Equatable {
        case positive
        case negative
        case neutral
    }

    struct Content: Equatable {
        let symbol: String
        let exchangeName: String
        let priceText: String
        let changeAmountText: String
        let changePercentText: String
        let secondaryLineText: String
        let changeTone: ChangeTone
    }

    let content: Content
    let heroPriceFontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(content.symbol)
                    .font(QuoteBoardTheme.regularFont(size: 14))
                    .foregroundStyle(QuoteBoardTheme.primaryText)

                Text(content.exchangeName)
                    .font(QuoteBoardTheme.regularFont(size: 14))
                    .foregroundStyle(QuoteBoardTheme.primaryText)
            }

            HStack(alignment: .top, spacing: 10) {
                Text(content.priceText)
                    .font(QuoteBoardTheme.heavyFont(size: heroPriceFontSize))
                    .foregroundStyle(trendColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                VStack(alignment: .leading, spacing: 2) {
                    Text(content.changeAmountText)
                        .font(QuoteBoardTheme.regularFont(size: 14))
                        .foregroundStyle(trendColor)

                    Text(content.changePercentText)
                        .font(QuoteBoardTheme.regularFont(size: 14))
                        .foregroundStyle(trendColor)
                }
                .padding(.top, 8)
            }

            Text(content.secondaryLineText)
                .font(QuoteBoardTheme.regularFont(size: 12))
                .foregroundStyle(QuoteBoardTheme.secondaryText)
        }
    }

    private var trendColor: Color {
        switch content.changeTone {
        case .positive:
            return QuoteBoardTheme.positive
        case .negative:
            return QuoteBoardTheme.negative
        case .neutral:
            return QuoteBoardTheme.neutral
        }
    }
}

struct PriceSparklineView: View {
    let history: PriceHistorySnapshot

    private var points: [PriceHistoryPoint] {
        history.points
    }

    private var trendColor: Color {
        guard let first = points.first?.price, let last = points.last?.price else {
            return QuoteBoardTheme.neutral
        }
        if last > first { return QuoteBoardTheme.positive }
        if last < first { return QuoteBoardTheme.negative }
        return QuoteBoardTheme.neutral
    }

    private var priceDomain: ClosedRange<Double> {
        let values = points.map { NSDecimalNumber(decimal: $0.price).doubleValue }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let spread = high - low
        let padding = max(spread * 0.12, max(abs(high) * 0.002, 0.0001))
        return (low - padding)...(high + padding)
    }

    var body: some View {
        if points.count > 1 {
            VStack(alignment: .leading, spacing: 3) {
                Text("24H PRICE")
                    .font(QuoteBoardTheme.boldFont(size: 10))
                    .foregroundStyle(QuoteBoardTheme.tertiaryText)

                Chart(points) { point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Price", NSDecimalNumber(decimal: point.price).doubleValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [trendColor.opacity(0.28), trendColor.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Price", NSDecimalNumber(decimal: point.price).doubleValue)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(trendColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartYScale(domain: priceDomain)
                .frame(height: 42)
                .accessibilityLabel("24-hour price chart")
                .accessibilityValue("\(QuotePriceFormatter.currencyText(points.first?.price)) to \(QuotePriceFormatter.currencyText(points.last?.price))")
            }
        }
    }
}
