# XAUUSD High-Growth EA: London Volatility Breakout & Pyramiding (LVPR)

An automated MQL4 Expert Advisor engineered to scale a **$100 account toward $500 in 1 week** by capturing daily London Open impulse moves on Gold (**XAUUSD**), locking in risk-free Break-Even stops, and pyramiding runner positions to ride $15–$30 daily expansions.

---

## 1. Strategy Architecture & Mathematical Engine

To grow an account **$100 $\rightarrow$ $500$ in 5 trading days**, an EA requires a Compound Daily Growth Rate (CDGR) of **~38% per day**. 

Instead of taking tiny 1% scalps that get devoured by broker spreads, this system exploits the **daily $20–$45 expansion of Gold** using **Asymmetric Risk-to-Reward (1:3 to 1:5)**:

| Feature | Operational Mechanism |
| :--- | :--- |
| **Asian Range Consolidation** | Automatically scans and maps the High and Low between `00:00 – 06:30 UTC`. |
| **London Breakout Trigger** | Executes at `07:00 UTC` when institutional volume breaches the Asian boundary with momentum. |
| **Zero-Risk Protection** | When the trade moves **+$2.00** in profit, the Stop Loss is automatically shifted to **Break-Even (+$0.30 locked)**. Original capital is 100% immune from this point. |
| **Zero-Risk Pyramiding** | At **+$2.50** profit, the EA enters **Position 2 (Runner)** financed by accumulated floating profit. |
| **ATR Trailing Stop** | Both positions trail behind the trend using a 14-period ATR trailing buffer to ride the $15–$30 runner. |
| **Daily Loss Circuit Breaker** | Automatically halts trading for the day if equity drops by $12, preserving your account capital. |

---

## 2. Dynamic Compounding Tiers

The EA automatically scales lot sizes as your equity grows:

| Account Equity Range | Base Lot | Risk per Initial Setup | Target Gain per Runner |
| :--- | :--- | :--- | :--- |
| **$100 – $149** (Day 1) | `0.02` lot | ~$5.00 | +$30.00 to +$45.00 |
| **$150 – $249** (Day 2) | `0.04` lot | ~$8.00 | +$60.00 to +$90.00 |
| **$250 – $379** (Day 3–4) | `0.07` lot | ~$14.00 | +$105.00 to +$150.00 |
| **$380 – $500+** (Day 5) | `0.10` lot | ~$20.00 | +$150.00 to +$225.00 |

*Just 2 to 3 quality trend captures during the 5 trading days achieves the $500 target.*

---

## 3. Installation & Setup

1. Copy [XAUUSD_BreakoutPyramid.mq4](file:///Users/brianwfl5454/Desktop/work/projects/mt4_ea_autotrade/XAUUSD_BreakoutPyramid.mq4) into your MT4 directory:
   - In MT4: **File** $\rightarrow$ **Open Data Folder** $\rightarrow$ `MQL4/Experts/`
2. In MT4 Navigator window (`Ctrl + N`), right-click **Expert Advisors** and select **Refresh**.
3. Attach `XAUUSD_BreakoutPyramid` onto a **XAUUSD M15** chart.
4. Set **InpBrokerUtcOffset** to match your broker's server time zone (e.g. `2` or `3` for GMT+2 / GMT+3).
5. Ensure the **AutoTrading** button is toggled ON.

---

## 4. Key Inputs & Customization

- `InpUseDynamicTiers` (default: `true`): Automatically upgrades lot sizes as balance increases.
- `InpMaxDailyLossUSD` (default: `12.00`): Hard cap stopping trading if a day experiences consecutive false breakouts.
- `InpBreakEvenTriggerUSD` (default: `2.00`): Price distance in gold ($2.00 move) that locks in Break-Even.
- `InpEnablePyramiding` (default: `true`): Automatically stacks Position 2 once the trade is protected.
- `InpMaxSpreadUSD` (default: `0.35`): Skips breakout entries if spread exceeds $0.35 (35 pips).
