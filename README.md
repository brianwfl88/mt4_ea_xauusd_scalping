# XAUUSD Micro-Scalper EA ($100 → $500 Account Growth Strategy)

An automated MQL4 Expert Advisor engineered for micro-account scaling on **XAUUSD (Gold)** with strict drawdown constraints (<5%), dynamic $\ge 1\%$ profit taking, session-based liquidity filters, and an automated equity circuit breaker.

---

## 1. Strategy Mathematical Framework

| Parameter | Value | Institutional Mechanism |
| :--- | :--- | :--- |
| **Initial Capital** | **$100.00** | Micro account starting base |
| **Contract Size** | 100 oz per lot | Standard MT4 Gold contract |
| **Base Lot Size** | **0.01 lot** | 1 troy ounce of gold |
| **Price Point Value** | $1.00 move = $1.00 PnL | Exactly 1.0% account gain per $1.00 price swing |
| **Profit Target per Trade** | **$\ge 1.0\%$ ($1.00+)** | Micro-scalp exit; eliminates greed and over-holding |
| **Per-Trade Stop Loss** | **2.0% ($2.00)** | Limits single-trade damage to safe buffer |
| **Break-Even Trigger** | **+0.5% profit ($0.50)** | Moves SL to entry + 2 pips to lock in risk-free trade |
| **Max Drawdown Limit** | **4.8% ($4.80 max loss)** | Emergency hard kill-switch halts all trading |

---

## 2. Market Timing & Liquidity Windows

Gold market dynamics dictate that low-liquidity periods (Asian session, rollover, market closing) suffer from wide spreads, whipsaws, and slippage. This EA trades **only during peak institutional liquidity**:

1. **London Open**: `07:00 – 11:00 UTC` (Directional breakout expansion).
2. **New York Open & Overlap**: `13:00 – 17:00 UTC` (Peak liquidity, highest volume, tightest spreads).
3. **Rollover & Night Cutoff**: Fully disabled during `21:00 – 23:00 UTC` when spreads widen by 300%–500%.

---

## 3. Indicator & Execution Rules

1. **Trend Filter (M5)**:
   - **Bullish Bias**: Price > EMA(50) > EMA(200). Only BUY orders permitted.
   - **Bearish Bias**: Price < EMA(50) < EMA(200). Only SELL orders permitted.
2. **Timing Trigger (M1)**:
   - Bollinger Bands (20, 2.0) squeeze & price expansion across the centerline.
   - RSI(14) momentum filter: RSI $\ge 52$ for BUY, RSI $\le 48$ for SELL.
3. **Spread Guard**:
   - Compares real-time broker spread to `InpMaxSpreadPips` (Default 35 pips = $0.35). If spread widens, orders are blocked to prevent negative expectancy.
4. **Drawdown Circuit Breaker**:
   - Constantly records `PeakEquity`. If `(PeakEquity - CurrentEquity) / PeakEquity` reaches `4.8%`, all trades are immediately closed and trading is permanently paused.

---

## 4. Installation & Setup Guide

### Step 1: Install in MetaTrader 4
1. Open your MT4 terminal.
2. Click **File** → **Open Data Folder**.
3. Navigate to `MQL4` → `Experts`.
4. Copy `XAUUSD_MicroScalper.mq4` into this `Experts` directory.
5. In MT4, open the **Navigator** window (`Ctrl + N`), right-click **Expert Advisors**, and click **Refresh**.
6. Double-click or drag `XAUUSD_MicroScalper` onto a **XAUUSD M1** (or M5) chart.

### Step 2: Configure Inputs & Settings
- **Allow Live Trading**: In the EA popup, go to the **Common** tab and check **"Allow live trading"** and **"Allow DLL imports"**.
- Ensure the **"AutoTrading"** button at the top toolbar of MT4 is turned ON (green).
- **InpBrokerUtcOffset**: Set this to your broker server's UTC offset.
  - *Example*: If your broker server is GMT+2 (winter) or GMT+3 (summer), set `InpBrokerUtcOffset = 2` or `3`.
- **InpFixedLot**: Keep at `0.01` for a $100 account.
- **InpUseCompounding**: Set to `true` if you want lot sizes to scale up dynamically as your account balance crosses $200, $300, etc.

---

## 5. Critical Broker Requirements

> [!IMPORTANT]
> - **ECN / Raw Spread Account Required**: High-spread standard retail accounts (charging 35–60 cents spread on gold) will severely hamper micro-scalping. Use a broker providing raw spreads of 10–20 cents ($0.10–$0.20).
> - **VPS Recommended**: A low-latency Forex VPS (Virtual Private Server) located in London or New York ensures 1–5ms execution speed and prevents disconnection during market opens.
> - **Demo Forward Testing First**: Always test on a $100 demo account for at least 1–2 days to calibrate your broker's server time offset and spread limits.
