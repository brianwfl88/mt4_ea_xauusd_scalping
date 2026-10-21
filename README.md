# Quantitative MT4 Trading Suite for Gold (XAUUSD)

This repository contains institutional-grade automated trading systems built for MetaTrader 4, designed specifically to scale micro accounts on **XAUUSD (Gold)** with **1:500 leverage**.

---

## Expert Advisors in this Repository

| Expert Advisor | Trading Style | Timeframe | Best For |
| :--- | :--- | :--- | :--- |
| **[XAUUSD_SwingMaster.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_SwingMaster.mq4)** | **Macro Trend & Value Pullback Swing** | **H1 (Macro: H4)** | **$100 $\rightarrow$ $500$ Growth with High Conviction & Low Noise** |
| **[XAUUSD_BreakoutPyramid.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_BreakoutPyramid.mq4)** | London Open Volatility Breakout & Runner | M15 / M5 | High-momentum intra-day sessions |
| **[XAUUSD_MicroScalper.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_MicroScalper.mq4)** | High-Frequency Micro-Scalper | M1 / M5 | Ultra-tight micro profit taking |

---

## Strategy Focus: `XAUUSD_SwingMaster.mq4` (Recommended)

### 1. Core Mechanics
Rather than fighting intraday chop, spreads, and execution slippage, the **Swing Master** captures high-conviction **$30 to $80 multi-day moves on Gold**:

1. **Macro Trend Filter (H4)**:
   - Evaluates H4 EMA(50) vs EMA(200).
   - Only enters **BUY** orders if Macro is Bullish.
   - Only enters **SELL** orders if Macro is Bearish.
2. **Value Retracement Entry (H1)**:
   - Waits for price to retrace into the dynamic value zone between H1 EMA(20) and EMA(50).
   - Confirmed by an **RSI(14) momentum hook** out of oversold/overbought extremes.
3. **Partial Scale-Out & Risk-Free Runner**:
   - **TP1 (50% position)**: Closes automatically at **1:2 Risk-to-Reward ratio** (e.g. +$15.00 to +$20.00 price move on Gold), banking immediate profits.
   - **Break-Even**: Shifts Stop Loss to entry price + buffer ($0.50), making the trade 100% immune to loss.
   - **TP2 (50% Runner)**: Trails with an **H4 ATR trailing stop** to ride the full multi-day wave.
4. **Friday Volatility & Weekend Risk Guard**:
   - At **19:00–21:00 UTC on Friday**, checks if current H1 ATR has dropped below 70% of the 24-hour average.
   - If volatility is low, automatically liquidates open positions before market close to avoid Sunday weekend gap risk.

---

### 2. Sizing & Compounding Tiers (at 1:500 Leverage)

At 1:500 leverage, a `0.02` lot trade requires only **$10.60 margin**, leaving over **$89.00 in free margin**.

| Account Balance Tier | Base Lot | Required Margin | Projected Gain per $40 Swing |
| :--- | :--- | :--- | :--- |
| **$100 – $149** | `0.02` lot | $10.60 | **+$80.00 (+80%)** |
| **$150 – $249** | `0.04` lot | $21.20 | **+$160.00 (+106%)** |
| **$250 – $379** | `0.07` lot | $37.10 | **+$280.00 (+112%)** |
| **$380 – $500+** | `0.10` lot | $53.00 | **+$400.00 (+105%)** |

*Just 2 to 3 successful multi-day swings can scale an account from $100 to $500.*

---

### 3. Quick Setup & Backtesting in MT4

1. Copy [XAUUSD_SwingMaster.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_SwingMaster.mq4) to your MT4 `MQL4/Experts/` folder.
2. Open a **XAUUSD H1** chart.
3. Attach the EA.
4. Set `InpBrokerUtcOffset` to your broker server's UTC offset (usually `2` or `3`).
5. Ensure **AutoTrading** is enabled.
