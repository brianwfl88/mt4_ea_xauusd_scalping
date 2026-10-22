# Quantitative MT4 Trading Suite for Gold (XAUUSD)

This repository contains institutional-grade automated trading systems built for MetaTrader 4, designed specifically to scale micro accounts on **XAUUSD (Gold)** with **1:500 leverage**, strict capital preservation, session risk profiling, daily gap protection, and precision execution.

---

## Expert Advisors in this Repository

| Expert Advisor | Trading Style | Timeframe | Best For |
| :--- | :--- | :--- | :--- |
| **[XAUUSD_IntradayMaster.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_IntradayMaster.mq4) (NEW)** | **Institutional Liquidity Sweeps & FVG Retest** | **M15** | **Zero Overnight Risk, Fast Intra-Day Compounding, 100% Cash by 20:45 UTC** |
| **[XAUUSD_SwingMaster.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_SwingMaster.mq4)** | Macro Trend Swing + MACD S/R Confluence | H1 | Multi-day structural swing waves |
| **[XAUUSD_BreakoutPyramid.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_BreakoutPyramid.mq4)** | London Open Volatility Breakout & Runner | M15 / M5 | High-momentum intra-day sessions |
| **[XAUUSD_MicroScalper.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_MicroScalper.mq4)** | High-Frequency Micro-Scalper | M1 / M5 | Ultra-tight micro profit taking |

---

## Strategy Focus: `XAUUSD_IntradayMaster.mq4` (M15 Precision Engine)

### 1. Dual High-Probability Setups
1. **Setup A: Asian Liquidity Sweep & Reversal (Smart Money Concept)**:
   - Identifies institutional liquidity sweeps above the Asian High or below the Asian Low.
   - When price rejects back inside the range with an aggressive candle wick and MACD momentum confirms, the EA enters a reversal trade with tight invalidation stops ($2.50 to $4.00 on Gold).
2. **Setup B: London Momentum Breakout & FVG / EMA Retest**:
   - In a trending market (M15 Price aligned with 200 EMA), the EA waits for a pullback into the EMA 20 / Fair Value Gap zone.
   - Confirmed by expanding directional MACD histogram momentum, executing a trend continuation swing.

---

### 2. Strict Session Clock & 100% Cash Overnight
- **00:00 – 06:45 UTC (Asian Session)**: Maps High and Low consolidation box.
- **07:00 – 12:00 UTC (London Prime)**: Normal dynamic risk sizing (`InpRiskPercentPerTrade = 3.5%`).
- **12:00 – 16:00 UTC (London-US Overlap)**: Sizing strictly clamped to **MINIMUM (`0.01` lot)**.
- **16:00 – 17:00 UTC (Post-London Final)**: Minimized risk profile (`0.01` lot).
- **17:00 UTC Onwards (Hard Stop)**: **Zero new order placement permitted**.
- **20:45 UTC (Daily Liquidation)**: **All remaining positions are unconditionally closed to 100% cash**. No overnight hold; zero daily gap risk.

---

### 3. Capital Defense & Safe Recovery Engine
- **Mathematical Sizing**: Lot size is dynamically computed from equity and exact Stop Loss distance so no single trade can ever lose more than 3.5% of your balance.
- **Profit Floor Ratchet**: Automatically locks in capital milestones ($200 $\rightarrow$ $150, $300 $\rightarrow$ $240, $400 $\rightarrow$ $330).
- **Safe Recovery Mode**: Interactive on-chart button (`>> CLICK TO RESUME TRADING NOW <<`) to easily restart in `0.01` lot recovery mode after halts.

---

### 4. Quick Start in MT4
1. Copy [XAUUSD_IntradayMaster.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_IntradayMaster.mq4) to your MT4 `MQL4/Experts/` folder.
2. Open a **XAUUSD M15** chart.
3. Attach the EA and verify `InpBrokerUtcOffset` matches your broker server time (typically `2` or `3`).
4. Enable **AutoTrading**.
