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
