# Real Time Quote

Real Time Quote is a native macOS menu-style window for live cryptocurrency
prices from Coinbase and OKX. It supports BTC, ETH, ADA, SOL, XRP, and DOGE.

## Install

1. Download `RealTimeQuote-1.2.1-macos.dmg` and open it.
2. Drag `RealTimeQuote.app` onto the included `Applications` shortcut.
3. Open the app. If macOS warns because the app is not notarized yet, use
   Control-click, choose **Open**, then confirm **Open**.

The app needs an internet connection. Public Coinbase and OKX price feeds work
without API credentials.

## Price alerts

Use the **Alert** button beside the connection badge to set one price alert per
exchange and trading pair. Choose whether to trigger when the price moves
above or below a USD target. Alerts are stored locally, notify once, and then
clear automatically. macOS asks for notification permission when you save your
first alert.

## 24-hour price chart

The compact chart below the main price shows the most recent 24 one-hour
candles for the selected exchange and coin. Its final point follows the live
price feed, and the line is green or red according to the period's direction.

## Price precision

Prices below $10 display four decimal places so low-priced assets such as DOGE,
ADA, and XRP retain meaningful precision. Higher-priced assets continue to use
two decimal places.

## Exchange symbols

Coinbase uses USD pairs, such as `BTC-USD` and `ETH-USD`.

OKX spot markets use USDT pairs, so the app intentionally displays
`BTC-USDT`, `ETH-USDT`, `ADA-USDT`, `SOL-USDT`, `XRP-USDT`, or `DOGE-USDT` while OKX is
selected. This avoids requesting non-existent `*-USD` markets from OKX.

## Optional configuration

For a packaged app, create the configuration directory and copy the sample:

```bash
mkdir -p ~/.real-time-quote
cp Config/local.sample.json ~/.real-time-quote/config.json
```

Edit `~/.real-time-quote/config.json` with your keys only if you need an
authenticated exchange feed or CoinGecko reference statistics. Do not commit
this file; it contains secrets. The app remains usable without it.

`Config/local.json` is intended only for launching from the Xcode project
directory during development.

## Build from source

Requires Xcode and macOS 13 or later:

```bash
xcodebuild -project RealTimeQuote.xcodeproj -scheme RealTimeQuote \
  -configuration Release -destination 'platform=macOS' build
```

## Release signing

The checked-in project has no Apple Developer Team ID. Release bundles are
ad-hoc signed for local use. To distribute outside your own Mac without the
first-launch Gatekeeper prompt, configure a Developer ID Application
certificate and notarize the archive with Apple.
