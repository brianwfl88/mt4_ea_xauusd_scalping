# Quantitative MT4 Trading Suite for Gold (XAUUSD)

This repository contains institutional-grade automated trading systems built for MetaTrader 4, designed specifically to scale micro accounts on **XAUUSD (Gold)** with **1:500 leverage**, strict capital preservation, and safe recovery mechanisms.

---

## Expert Advisors in this Repository

| Expert Advisor | Trading Style | Timeframe | Best For |
| :--- | :--- | :--- | :--- |
| **[XAUUSD_SwingMaster.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_SwingMaster.mq4) (v2.20)** | **Macro Trend Swing + Safe Recovery** | **H1** | **$100 $\rightarrow$ $500$ Growth with Progressive Lot Recovery Engine** |
| **[XAUUSD_BreakoutPyramid.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_BreakoutPyramid.mq4)** | London Open Volatility Breakout & Runner | M15 / M5 | High-momentum intra-day sessions |
| **[XAUUSD_MicroScalper.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_MicroScalper.mq4)** | High-Frequency Micro-Scalper | M1 / M5 | Ultra-tight micro profit taking |

---

## Strategy Focus: `XAUUSD_SwingMaster.mq4` (v2.20 Recovery Engine)

### 1. How to Resume After a Circuit Breaker Halt
When the circuit breaker halts execution to protect your balance, you can resume in two ways:
1. **Interactive On-Chart Button**: Simply click the bright orange button **`>> CLICK TO RESUME TRADING NOW <<`** directly on your MT4 chart.
2. **Automated Cooldown Timer (`InpAutoResumeAfterHalt = true`)**: The EA waits `8` hours (configurable via `InpHaltCooldownHours`) and automatically restarts unattended.

---

### 2. Progressive Lot Sizing (Recovery Mode)
When resuming after a halt, the EA activates **Safe Recovery Mode** with progressive lot sizing:
- **Stage 1 (Smallest Lot - `0.01`)**: Trades exclusively with `0.01` lot until 50% of the recovery goal is reached.
- **Stage 2 (Step-Up Lot - `0.02`)**: Once positive momentum is restored, lot size steps up slightly to `0.02`.
- **Graduation to Normal Mode**: Once account gains reach `InpRecoveryTargetUSD` (default: **+$15.00**), the EA graduates out of Recovery Mode and restores full dynamic risk sizing.

---

### 3. Key Parameters
- `InpRiskPercentPerTrade` (default: `4.0%`): Max risk % per trade in Normal Mode.
- `InpMaxDrawdownFromPeak` (default: `15.0%`): Max drawdown % allowed from peak equity before circuit breaker triggers.
- `InpAutoResumeAfterHalt` (default: `true`): Automatically resume after cooldown.
- `InpHaltCooldownHours` (default: `8`): Cooldown hours before auto-resuming.
- `InpRecoveryMinLot` (default: `0.01`): Starting lot size in Recovery Stage 1.
- `InpRecoveryStepLot` (default: `0.02`): Stepped-up lot size in Recovery Stage 2.
- `InpRecoveryTargetUSD` (default: `15.00`): Profit ($) required to graduate back to Normal Mode.
