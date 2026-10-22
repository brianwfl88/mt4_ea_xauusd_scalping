# Quantitative MT4 Trading Suite for Gold (XAUUSD)

This repository contains institutional-grade automated trading systems built for MetaTrader 4, designed specifically to scale micro accounts on **XAUUSD (Gold)** with **1:500 leverage**, strict capital preservation, session risk profiling, daily gap protection, and MACD + Price Action confluence.

---

## Expert Advisors in this Repository

| Expert Advisor | Trading Style | Timeframe | Best For |
| :--- | :--- | :--- | :--- |
| **[XAUUSD_SwingMaster.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_SwingMaster.mq4) (v2.40)** | **MACD + S/R Reversals & Trend Pullbacks** | **H1** | **$100 $\rightarrow$ $500$ Growth with High-Confidence Price Action & S/R Entries** |
| **[XAUUSD_BreakoutPyramid.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_BreakoutPyramid.mq4)** | London Open Volatility Breakout & Runner | M15 / M5 | High-momentum intra-day sessions |
| **[XAUUSD_MicroScalper.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_MicroScalper.mq4)** | High-Frequency Micro-Scalper | M1 / M5 | Ultra-tight micro profit taking |

---

## Strategy Focus: `XAUUSD_SwingMaster.mq4` (v2.40 MACD & S/R Engine)

### 1. Dual Entry Logic (MACD + Price Action)
1. **High-Confidence Reversal at Support/Resistance (Without Moving Average Filter)**:
   - Tracks **Previous Day High/Low (PDH/PDL)** and **Today's Session High/Low**.
   - When price reaches Support with a bullish rejection wick and MACD histogram turns up from extreme oversold territory, the EA executes a **BUY reversal without requiring price to be above the 200 EMA**.
   - When price reaches Resistance with a bearish rejection wick and MACD histogram turns down from extreme overbought territory, the EA executes a **SELL reversal without requiring price to be below the 200 EMA**.
2. **Gaining Momentum Trend Pullback (With Moving Average Filter)**:
   - In a confirmed trend (Price > 200 EMA), price pulls back into the dynamic 20/50 EMA value zone.
   - When MACD shows expanding directional momentum (`MACD Main > Signal` and `MACD Histogram Bar 1 > Bar 2 > 0`), the EA enters a **high-confidence trend continuation swing**.

### 2. Capital Preservation & Session Rules
- **Mathematical Lot Sizing**: Lot size calculated from current equity and Stop Loss distance ($) so no single trade can exceed 4% risk.
- **Session Risk Clamping**: London-US overlap (12:00–16:00 UTC) and post-London (16:00–17:00 UTC) force minimum `0.01` lot.
- **Hard Cutoff**: Order placement stops at **17:00 UTC**.
- **Daily Rollover Liquidation**: Closes open trades at **20:45 UTC** to eliminate overnight gap risk.
- **Safe Recovery Mode**: Interactive on-chart button to resume trading in 0.01 lot recovery mode.
