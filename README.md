# Quantitative MT4 Trading Suite for Gold (XAUUSD)

This repository contains institutional-grade automated trading systems built for MetaTrader 4, designed specifically to scale micro accounts on **XAUUSD (Gold)** with **1:500 leverage** and strict capital preservation.

---

## Expert Advisors in this Repository

| Expert Advisor | Trading Style | Timeframe | Best For |
| :--- | :--- | :--- | :--- |
| **[XAUUSD_SwingMaster.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_SwingMaster.mq4) (v2.00)** | **Macro Trend & Value Pullback Swing** | **H1** | **$100 $\rightarrow$ $500$ Growth with Strict Dynamic Capital Protection** |
| **[XAUUSD_BreakoutPyramid.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_BreakoutPyramid.mq4)** | London Open Volatility Breakout & Runner | M15 / M5 | High-momentum intra-day sessions |
| **[XAUUSD_MicroScalper.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_MicroScalper.mq4)** | High-Frequency Micro-Scalper | M1 / M5 | Ultra-tight micro profit taking |

---

## Strategy Focus: `XAUUSD_SwingMaster.mq4` (v2.00 Capital Guard)

### 1. Mathematical Risk-Based Sizing (No Single-Trade Wipouts)
In version 2.00, lot size is mathematically derived from the exact Stop Loss distance and current account balance:
$$
\text{Max Risk \$} = \text{Current Equity} \times \left(\frac{\text{InpRiskPercentPerTrade}}{100.0}\right)
$$
$$
\text{Lot Size} = \frac{\text{Max Risk \$}}{\text{Stop Loss Distance in Gold \$} \times 100}
$$

- If you have **$300 balance** and the Stop Loss is wide ($20.00 Gold swing), the lot size automatically drops to **0.01 lot**. If that trade hits SL, you only lose **$20.00** (account stays at $280, **never $0**).
- No single trade can ever wipe out more than your configured risk percentage (default `4.0%`).

---

### 2. High-Water Mark Circuit Breakers & Profit Floor Ratchet

To ensure profits (like reaching $300+) are permanently protected:

1. **Peak Drawdown Limit (`InpMaxDrawdownFromPeak = 15.0%`)**:
   - Continuously tracks highest equity. If equity drops 15% from its peak, the EA automatically closes all trades and locks in the gains.
2. **Profit Floor Ratchet (`InpEnableProfitRatchet = true`)**:
   - When balance crosses **$200**, capital floor locks at **$150**.
   - When balance crosses **$300**, capital floor locks at **$240**.
   - When balance crosses **$400**, capital floor locks at **$330**.
   - If equity drops to the floor, all trading halts, permanently banking the milestone profits.

---

### 3. Quick Setup & Backtesting

1. Copy [XAUUSD_SwingMaster.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_SwingMaster.mq4) to your MT4 `MQL4/Experts/` folder.
2. Open a **XAUUSD H1** chart.
3. Attach the EA.
4. Set `InpBrokerUtcOffset` to your broker's UTC offset (usually `2` or `3`).
5. Ensure **AutoTrading** is enabled.
