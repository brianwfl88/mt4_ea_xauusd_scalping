//+------------------------------------------------------------------+
//|                                       XAUUSD_IntradayMaster.mq4  |
//|               Institutional Intraday Liquidity & FVG Engine      |
//|                    Engineered for Gold (XAUUSD) on M15 Chart     |
//|                    Zero Overnight Risk | 1:500 Leverage Ready    |
//+------------------------------------------------------------------+
#property copyright "Quantitative Trading Engine"
#property link      "https://github.com"
#property version   "1.00"
#property strict

//--- Inputs: Capital Preservation & Mathematical Risk Sizing
input string   _Section1               = "=== Capital Preservation & Risk ===";
input double   InpRiskPercentPerTrade  = 3.5;      // Max Risk % per trade in London Prime (3.0% - 4.0%)
input double   InpMaxDrawdownFromPeak  = 15.0;     // Max Drawdown % from Peak Equity before emergency halt
input bool     InpEnableProfitRatchet  = true;     // Ratchet Profit Floor (Locks in gains at $200, $300, etc.)
input double   InpRewardRatioTP1       = 2.0;      // Risk-to-Reward ratio for TP1 (1:2 R:R)
input double   InpPartialClosePercent  = 50.0;     // Percentage of position to close at TP1 (50%)
input double   InpBreakEvenBufferUSD   = 0.40;     // Profit locked when moving to Break-Even ($0.40)

//--- Inputs: Session Clock & Daily Gap Guard
input string   _Section2               = "=== Session Clock & Daily Gap Guard ===";
input int      InpBrokerUtcOffset      = 2;        // Broker Server UTC/GMT Offset (e.g. +2 or +3)
input int      InpAsianStartHourUTC    = 0;        // Asian Range Start Hour (00:00 UTC)
input int      InpAsianEndHourUTC      = 6;        // Asian Range End Hour (06:00 UTC)
input int      InpAsianEndMinuteUTC    = 45;       // Asian Range End Minute (06:45 UTC)
input int      InpLondonStartHourUTC   = 7;        // London Open (07:00 UTC) - Prime Execution
input int      InpOverlapStartHourUTC  = 12;       // London-US Overlap (12:00 UTC) - Min Risk (0.01 lot)
input int      InpLondonEndHourUTC     = 16;       // London Session End (16:00 UTC) - Post-London Min Risk
input int      InpHardStopTradingUTC   = 17;       // Hard Cutoff (17:00 UTC) - STOP all order placement
input bool     InpForceCloseDaily      = true;     // Unconditionally close all trades before daily rollover
input int      InpDailyCloseHourUTC    = 20;       // Daily close hour (20:00 UTC)
input int      InpDailyCloseMinuteUTC  = 45;       // Daily close minute (20:45 UTC) - Liquidate to 100% Cash

//--- Inputs: Safe Recovery & Restart Mode
input string   _Section3               = "=== Safe Recovery & Restart Mode ===";
input bool     InpAutoResumeAfterHalt  = true;     // Automatically resume trading after cooldown
input int      InpHaltCooldownHours    = 8;        // Cooldown hours before auto-resuming (8 hours)
input bool     InpEnableRecoveryMode   = true;     // Re-enter market in Safe Recovery Mode (Smallest lot first)
input double   InpRecoveryTargetUSD    = 15.00;    // Profit needed ($) to graduate from Recovery to Normal Mode
input double   InpRecoveryMinLot       = 0.01;     // Stage 1 Lot: Smallest lot size (0.01)
input double   InpRecoveryStepLot      = 0.02;     // Stage 2 Lot: Stepped-up lot size (0.02)

//--- Inputs: Intraday Setups & Technical Indicators
input string   _Section4               = "=== Setups & Indicator Parameters ===";
input bool     InpEnableSweepReversals = true;     // Enable Setup A: Asian Liquidity Sweeps
input bool     InpEnableFVGRetest      = true;     // Enable Setup B: Momentum Break & FVG Retest
input double   InpSweepBufferUSD       = 2.00;     // Max allowable sweep penetration outside Asian box ($2.00)
input int      InpTrendEMA_Slow        = 200;      // Primary Trend Filter EMA (200 EMA)
input int      InpPullbackEMA_Fast     = 20;       // Pullback Dynamic EMA (20 EMA)
input int      InpPullbackEMA_Slow     = 50;       // Pullback Dynamic EMA (50 EMA)
input int      InpMACDFast             = 12;       // MACD Fast EMA
input int      InpMACDSlow             = 26;       // MACD Slow EMA
input int      InpMACDSignal           = 9;        // MACD Signal SMA
input int      InpATRPeriod            = 14;       // ATR Period for Stop Loss and Trailing
input double   InpATRFactorSL          = 1.3;      // ATR Multiplier for Stop Loss
input double   InpATRFactorTrail       = 1.8;      // ATR Multiplier for Trailing Stop
input bool     InpUseTrailingStop      = true;     // Enable ATR Trailing Stop on Runner

//--- Inputs: Friday Volatility & Weekend Risk Filter
input string   _Section5               = "=== Friday Volatility & Weekend Guard ===";
input bool     InpEnableFridayFilter   = true;     // Enable Friday Late Session Volatility Check
input int      InpFridayCheckHourUTC   = 19;       // Friday UTC Hour to begin checking volatility (19:00 UTC)
input int      InpFridayCloseHourUTC   = 21;       // Friday UTC Hour to close if volatility is low (21:00 UTC)
input double   InpFridayVolThreshold   = 0.70;     // Low Volatility Threshold (Current ATR < 70% of 24-hr ATR)

//--- Inputs: Execution & Filters
input string   _Section6               = "=== Execution & Filters ===";
input double   InpMaxSpreadUSD         = 0.60;     // Max Allowable Spread in Gold $ ($0.60 = 60 pips)
input int      InpMagicNumber          = 777300;   // Unique Magic Number for Intraday Trades
input int      InpSlippage             = 40;       // Max Slippage in Points
input bool     InpVerboseLogging       = true;     // Verbose logging in Journal

//--- Global Variables
double    g_ContractSize          = 100.0;
double    g_InitialBalance        = 0.0;
double    g_PeakEquity            = 0.0;
double    g_ProfitFloor           = 0.0;
bool      g_PartialClosed         = false;
bool      g_CircuitBreakerTripped = false;
bool      g_FridayClosedForLowVol = false;
bool      g_DailyClosedForGapRisk = false;
int       g_LastResetDay          = -1;
datetime  g_HaltTimestamp         = 0;
bool      g_InRecoveryMode        = false;
int       g_RecoveryStage         = 1;
double    g_RecoveryStartEquity   = 0.0;
datetime  g_LastBarTime           = 0;

// Key Structure Levels
double    g_AsianHigh             = 0.0;
double    g_AsianLow              = 0.0;
bool      g_AsianBoxFormed        = false;
double    g_PDH                   = 0.0;
double    g_PDL                   = 0.0;

string    g_BtnName               = "btn_IntradayResume";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   string sym = Symbol();
   if (StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
   {
      Print("[WARNING] Symbol is ", sym, ". This EA is engineered specifically for XAUUSD / GOLD.");
   }

   g_ContractSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   if (g_ContractSize <= 0) g_ContractSize = 100.0;

   g_InitialBalance        = AccountBalance();
   g_PeakEquity            = MathMax(g_InitialBalance, AccountEquity());
   g_ProfitFloor           = 0.0;
   g_PartialClosed         = false;
   g_CircuitBreakerTripped = false;
   g_FridayClosedForLowVol = false;
   g_DailyClosedForGapRisk = false;
   g_LastResetDay          = Day();
   g_HaltTimestamp         = 0;
   g_InRecoveryMode        = false;
   g_RecoveryStage         = 1;
   g_RecoveryStartEquity   = g_InitialBalance;
   g_LastBarTime           = 0;

   // Calculate initial Asian & Daily Levels
   CalculateAsianAndDailyLevels();

   // Create on-chart interactive resume button
   CreateResumeButton();

   Print("==================================================================");
   Print("[INIT] XAUUSD Intraday Master Engine v1.00 Initialized (M15).");
   Print("[INIT] Asian High: $", DoubleToStr(g_AsianHigh, 2), " | Asian Low: $", DoubleToStr(g_AsianLow, 2),
         " | PDH: $", DoubleToStr(g_PDH, 2), " | PDL: $", DoubleToStr(g_PDL, 2));
   Print("[INIT] Daily Cash Liquidation at: ", InpDailyCloseHourUTC, ":", InpDailyCloseMinuteUTC, " UTC");
   Print("==================================================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   ObjectDelete(0, g_BtnName);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Daily Reset Check
   CheckDailyReset();

   // 2. Check Auto-Resume timer if halted
   if (g_CircuitBreakerTripped)
   {
      CheckAutoResumeTimer();
   }

   // 3. Maintain Peak Equity and Ratchet Profit Floors
   if (!g_CircuitBreakerTripped)
   {
      MaintainCapitalProtection();
   }

   // 4. Daily Gap & Rollover Risk Liquidation (20:45 UTC -> 100% Cash)
   if (InpForceCloseDaily)
   {
      CheckDailyGapRisk();
   }

   // 5. Friday Volatility & Weekend Risk Manager
   if (InpEnableFridayFilter)
   {
      CheckFridayWeekendRisk();
   }

   // 6. Update Asian Box Levels dynamically
   CalculateAsianAndDailyLevels();

   // 7. Update On-Chart HUD & Button
   UpdateHUD();

   // 8. If halted, block execution until resumed
   if (g_CircuitBreakerTripped) return;

   // 9. Manage Active Open Intraday Positions (TP1 Partial Close, Break-Even, ATR Trail)
   ManageOpenIntradayTrades();

   // 10. Entry Time Window & Session Checks
   if (!IsOrderPlacementAllowed()) return;
   if (g_DailyClosedForGapRisk) return;
   if (g_FridayClosedForLowVol) return;
   if (CountOpenIntradayTrades() > 0) return; // Strictly 1 high-conviction trade at a time
   if (!IsSpreadOk()) return;

   // 11. Check Intraday Entry Signals
   CheckAndExecuteIntradayEntry();
}

//+------------------------------------------------------------------+
//| Reset daily flags at new trading day                             |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   int currentDay = Day();
   if (currentDay != g_LastResetDay)
   {
      g_LastResetDay = currentDay;
      g_DailyClosedForGapRisk = false;
      g_FridayClosedForLowVol = false;
      g_AsianBoxFormed = false;
      g_AsianHigh = 0.0;
      g_AsianLow  = 0.0;
      Print("[NEW DAY] Daily session reset. Recalibrating Asian Range and Daily Gap guard.");
      CalculateAsianAndDailyLevels();
   }
}

//+------------------------------------------------------------------+
//| Calculate Asian Session (00:00 - 06:45 UTC) & Daily PDH/PDL      |
//+------------------------------------------------------------------+
void CalculateAsianAndDailyLevels()
{
   g_PDH = iHigh(Symbol(), PERIOD_D1, 1);
   g_PDL = iLow(Symbol(), PERIOD_D1, 1);

   int utcHour = GetCurrentUtcHour();
   int utcMin  = TimeMinute(TimeCurrent());

   // Lock Asian box once London session begins
   if (g_AsianBoxFormed && utcHour >= InpLondonStartHourUTC) return;

   datetime serverNow = TimeCurrent();
   int sYear  = TimeYear(serverNow);
   int sMonth = TimeMonth(serverNow);
   int sDay   = TimeDay(serverNow);

   double highest = -1.0;
   double lowest  = 999999.0;
   int matchedBars = 0;

   // Scan bars on M15 chart for today's Asian window
   for (int i = 0; i < Bars && i < 150; i++)
   {
      datetime barTime = Time[i];
      if (TimeYear(barTime) == sYear && TimeMonth(barTime) == sMonth && TimeDay(barTime) == sDay)
      {
         int barUtcHour = GetUtcHourFromTime(barTime);
         int barUtcMin  = TimeMinute(barTime);

         // Include bars between 00:00 and 06:45 UTC
         if ((barUtcHour >= InpAsianStartHourUTC) &&
             (barUtcHour < InpAsianEndHourUTC || (barUtcHour == InpAsianEndHourUTC && barUtcMin <= InpAsianEndMinuteUTC)))
         {
            if (High[i] > highest) highest = High[i];
            if (Low[i] < lowest)   lowest  = Low[i];
            matchedBars++;
         }
      }
      else if (matchedBars > 0)
      {
         break;
      }
   }

   if (matchedBars > 0 && highest > 0 && lowest < 999998.0)
   {
      g_AsianHigh = highest;
      g_AsianLow  = lowest;
      g_AsianBoxFormed = true;
   }
}

//+------------------------------------------------------------------+
//| Daily Gap & Rollover Risk Guard: Liquidate before Daily Close    |
//+------------------------------------------------------------------+
void CheckDailyGapRisk()
{
   int utcHour = GetCurrentUtcHour();
   int utcMin  = TimeMinute(TimeCurrent());

   if (utcHour > InpDailyCloseHourUTC || (utcHour == InpDailyCloseHourUTC && utcMin >= InpDailyCloseMinuteUTC))
   {
      if (CountOpenIntradayTrades() > 0)
      {
         Print("[DAILY GAP GUARD] Reached daily cutoff time (", InpDailyCloseHourUTC, ":", InpDailyCloseMinuteUTC,
               " UTC). Liquidating all intraday positions to 100% CASH to eliminate overnight gap risk.");
         CloseAllIntradayPositions();
         g_DailyClosedForGapRisk = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if New Orders are Allowed based on Session Hours           |
//+------------------------------------------------------------------+
bool IsOrderPlacementAllowed()
{
   int utcHour = GetCurrentUtcHour();

   // 1. Outside trading sessions (Before London 07:00 UTC)
   if (utcHour < InpLondonStartHourUTC) return false;

   // 2. User Requirement: Hard stop after London hours (17:00 UTC)
   if (utcHour >= InpHardStopTradingUTC) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Determine Current Session Name for HUD & Logging                 |
//+------------------------------------------------------------------+
string GetCurrentSessionPhase()
{
   int utcHour = GetCurrentUtcHour();

   if (utcHour < InpLondonStartHourUTC)
      return "Asian Consolidation (Mapping High/Low)";
   if (utcHour >= InpLondonStartHourUTC && utcHour < InpOverlapStartHourUTC)
      return "London Prime Session (Normal Dynamic Risk: 3.5%)";
   if (utcHour >= InpOverlapStartHourUTC && utcHour < InpLondonEndHourUTC)
      return "London-US Overlap (MINIMUM RISK: 0.01 Lot)";
   if (utcHour >= InpLondonEndHourUTC && utcHour < InpHardStopTradingUTC)
      return "Post-London Final (MINIMUM RISK: 0.01 Lot)";
   if (utcHour >= InpHardStopTradingUTC && utcHour < InpDailyCloseHourUTC)
      return "TRADING STOPPED (Post-London Cutoff)";
   
   return "Daily Rollover Liquidation (100% Cash Overnight)";
}

//+------------------------------------------------------------------+
//| OnChartEvent: Handle Button Click to Resume Trading              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if (id == CHARTEVENT_OBJECT_CLICK)
   {
      if (sparam == g_BtnName)
      {
         if (g_CircuitBreakerTripped)
         {
            Print("[MANUAL OVERRIDE] User clicked Resume Button on chart.");
            ResumeTradingFromHalt();
         }
         else
         {
            Print("[BUTTON CLICKED] Trading is active. Current Session: ", GetCurrentSessionPhase());
         }
         ObjectSetInteger(0, g_BtnName, OBJPROP_STATE, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Trigger Circuit Breaker & Start Halt Cooldown                    |
//+------------------------------------------------------------------+
void TriggerHalt(string reason)
{
   CloseAllIntradayPositions();
   g_CircuitBreakerTripped = true;
   g_HaltTimestamp         = TimeCurrent();
   g_InRecoveryMode        = InpEnableRecoveryMode;
   g_RecoveryStage         = 1;
   g_RecoveryStartEquity   = AccountEquity();

   Print("------------------------------------------------------------------");
   Print("[CIRCUIT BREAKER HALT] ", reason);
   Print("[HALT TIMED] Trading halted at: ", TimeToStr(g_HaltTimestamp, TIME_DATE|TIME_MINUTES),
         " | Current Equity: $", DoubleToStr(AccountEquity(), 2),
         " | Auto-Resume in: ", InpHaltCooldownHours, " hours (Safe Recovery Mode)");
   Print("------------------------------------------------------------------");
}

//+------------------------------------------------------------------+
//| Resume Trading from Halt and initialize Safe Recovery Mode       |
//+------------------------------------------------------------------+
void ResumeTradingFromHalt()
{
   g_CircuitBreakerTripped = false;
   g_HaltTimestamp         = 0;
   g_PeakEquity            = MathMax(AccountBalance(), AccountEquity());
   g_ProfitFloor           = 0.0;
   g_InRecoveryMode        = InpEnableRecoveryMode;
   g_RecoveryStage         = 1;
   g_RecoveryStartEquity   = AccountEquity();

   Print("==================================================================");
   Print("[RESUME TRADING] System woke up! Safe Recovery Mode: ACTIVE.");
   Print("[RECOVERY MODE] Stage 1 initialized: Starting with smallest lot (", DoubleToStr(InpRecoveryMinLot, 2), " lot).");
   Print("[RECOVERY GOAL] Gain +$", DoubleToStr(InpRecoveryTargetUSD, 2), " to safely restore normal dynamic risk sizing.");
   Print("==================================================================");
}

//+------------------------------------------------------------------+
//| Check if Cooldown Timer expired to auto-resume trading           |
//+------------------------------------------------------------------+
void CheckAutoResumeTimer()
{
   if (!InpAutoResumeAfterHalt) return;
   if (g_HaltTimestamp <= 0) return;

   datetime now = TimeCurrent();
   int elapsedSec = int(now - g_HaltTimestamp);
   int targetSec  = InpHaltCooldownHours * 3600;

   if (elapsedSec >= targetSec)
   {
      Print("[AUTO-RESUME COOLDOWN EXPIRED] ", InpHaltCooldownHours, " hours have elapsed since halt. Automatically restarting in Safe Recovery Mode!");
      ResumeTradingFromHalt();
   }
}

//+------------------------------------------------------------------+
//| Capital Protection: Peak Equity Tracking & Profit Floor Ratchet  |
//+------------------------------------------------------------------+
void MaintainCapitalProtection()
{
   double curEquity = AccountEquity();
   if (curEquity > g_PeakEquity)
   {
      g_PeakEquity = curEquity;

      if (InpEnableProfitRatchet && !g_InRecoveryMode)
      {
         if (g_PeakEquity >= 400.0)      g_ProfitFloor = MathMax(g_ProfitFloor, 330.0);
         else if (g_PeakEquity >= 300.0) g_ProfitFloor = MathMax(g_ProfitFloor, 240.0);
         else if (g_PeakEquity >= 200.0) g_ProfitFloor = MathMax(g_ProfitFloor, 150.0);
      }
   }

   double ddFromPeak = 0.0;
   if (g_PeakEquity > 0)
   {
      ddFromPeak = ((g_PeakEquity - curEquity) / g_PeakEquity) * 100.0;
   }

   if (ddFromPeak >= InpMaxDrawdownFromPeak)
   {
      TriggerHalt(StringConcatenate("Drawdown reached ", DoubleToStr(ddFromPeak, 1), "% from peak ($", DoubleToStr(g_PeakEquity, 2), ")"));
      return;
   }

   if (InpEnableProfitRatchet && !g_InRecoveryMode && g_ProfitFloor > 0 && curEquity <= g_ProfitFloor)
   {
      TriggerHalt(StringConcatenate("Equity dropped to locked profit floor of $", DoubleToStr(g_ProfitFloor, 2)));
      return;
   }
}

//+------------------------------------------------------------------+
//| Check Friday Volatility and Close Before Weekend if Low          |
//+------------------------------------------------------------------+
void CheckFridayWeekendRisk()
{
   datetime now = TimeCurrent();
   int dayOfWeek = TimeDayOfWeek(now);

   if (dayOfWeek == 5)
   {
      int utcHour = GetCurrentUtcHour();

      if (utcHour >= InpFridayCheckHourUTC && utcHour <= InpFridayCloseHourUTC)
      {
         double currentATR = iATR(Symbol(), PERIOD_CURRENT, InpATRPeriod, 1);
         double sumATR = 0.0;
         int lookback = MathMin(Bars - 1, 24);
         if (lookback > 0)
         {
            for (int i = 1; i <= lookback; i++)
            {
               sumATR += iATR(Symbol(), PERIOD_CURRENT, InpATRPeriod, i);
            }
            double avgATR = sumATR / lookback;

            if (avgATR > 0 && (currentATR < (avgATR * InpFridayVolThreshold)))
            {
               if (CountOpenIntradayTrades() > 0)
               {
                  Print("[FRIDAY WEEKEND GUARD] Low volatility detected on Friday late session. Current ATR: $",
                        DoubleToStr(currentATR, 2), " < ", DoubleToStr(InpFridayVolThreshold * 100.0, 0),
                        "% of Average ATR ($", DoubleToStr(avgATR, 2), "). Closing positions to eliminate weekend gap risk.");
                  CloseAllIntradayPositions();
                  g_FridayClosedForLowVol = true;
               }
            }
         }
      }
   }
   else
   {
      g_FridayClosedForLowVol = false;
   }
}

//+------------------------------------------------------------------+
//| Count active intraday positions for this EA                      |
//+------------------------------------------------------------------+
int CountOpenIntradayTrades()
{
   int count = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber)
         {
            if (OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| DYNAMIC RISK SIZING: Mathematical Capital Defense                |
//+------------------------------------------------------------------+
double CalculateDynamicRiskLot(double slDistanceUSD)
{
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   int utcHour = GetCurrentUtcHour();

   // In London-US overlap (12:00-16:00 UTC) & post-London (16:00-17:00 UTC), force minimum 0.01 lot
   if (utcHour >= InpOverlapStartHourUTC && utcHour < InpHardStopTradingUTC)
   {
      return minLot;
   }

   // Safe Recovery Mode
   double equity = AccountEquity();
   if (equity <= 0) equity = AccountBalance();

   if (g_InRecoveryMode)
   {
      double recoveryGain = equity - g_RecoveryStartEquity;

      if (recoveryGain >= InpRecoveryTargetUSD)
      {
         Print("==================================================================");
         Print("[RECOVERY COMPLETE] Account gained +$", DoubleToStr(recoveryGain, 2),
               " during recovery. Graduating to Normal Dynamic Risk Sizing!");
         Print("==================================================================");
         g_InRecoveryMode = false;
         g_PeakEquity     = MathMax(g_PeakEquity, equity);
      }
      else if (recoveryGain >= (InpRecoveryTargetUSD * 0.50))
      {
         g_RecoveryStage = 2;
         return InpRecoveryStepLot;
      }
      else
      {
         g_RecoveryStage = 1;
         return InpRecoveryMinLot;
      }
   }

   // Normal Dynamic Sizing (London Prime 07:00 - 12:00 UTC)
   double maxRiskDollars = equity * (InpRiskPercentPerTrade / 100.0);
   double lossPerStandardLot = slDistanceUSD * g_ContractSize;

   double lot = minLot;
   if (lossPerStandardLot > 0)
   {
      lot = maxRiskDollars / lossPerStandardLot;
   }

   lot = MathFloor(lot / lotStep) * lotStep;
   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;

   double marginReq = (Ask * lot * g_ContractSize) / MathMax(AccountLeverage(), 1);
   if (marginReq > (AccountFreeMargin() * 0.70) && lot > minLot)
   {
      lot = minLot;
   }

   return lot;
}

//+------------------------------------------------------------------+
//| Check Intraday Signals: Sweep Reversal & FVG Retest on M15       |
//+------------------------------------------------------------------+
void CheckAndExecuteIntradayEntry()
{
   datetime currentBarTime = Time[0];
   if (currentBarTime == g_LastBarTime) return;

   // 1. Bar Metrics on M15
   double close1 = Close[1];
   double low1   = Low[1];
   double high1  = High[1];
   double open1  = Open[1];

   // 2. Moving Averages on M15
   double ema200 = iMA(Symbol(), PERIOD_M15, InpTrendEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema50  = iMA(Symbol(), PERIOD_M15, InpPullbackEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema20  = iMA(Symbol(), PERIOD_M15, InpPullbackEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);

   // 3. MACD Momentum
   double macdMain_1 = iMACD(Symbol(), PERIOD_M15, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, 1);
   double macdSig_1  = iMACD(Symbol(), PERIOD_M15, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, 1);
   double macdMain_2 = iMACD(Symbol(), PERIOD_M15, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, 2);
   double macdSig_2  = iMACD(Symbol(), PERIOD_M15, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, 2);

   double macdHist_1 = macdMain_1 - macdSig_1;
   double macdHist_2 = macdMain_2 - macdSig_2;

   // 4. Dynamic ATR Stop Loss Calculation
   double atr = iATR(Symbol(), PERIOD_M15, InpATRPeriod, 1);
   if (atr <= 0) atr = 2.00;
   double slDistUSD = atr * InpATRFactorSL;

   double minStopUSD = (MarketInfo(Symbol(), MODE_STOPLEVEL) * Point) + (10 * Point);
   if (slDistUSD < minStopUSD) slDistUSD = minStopUSD;
   if (slDistUSD < 2.00) slDistUSD = 2.00; // Minimum $2.00 buffer on Gold

   double tp1DistUSD = slDistUSD * InpRewardRatioTP1;
   double lot = CalculateDynamicRiskLot(slDistUSD);

   RefreshRates();

   // ====================================================================
   // SETUP A: ASIAN LIQUIDITY SWEEP & REVERSAL (SMART MONEY CONCEPT)
   // ====================================================================
   if (InpEnableSweepReversals && g_AsianBoxFormed)
   {
      // BUY SETUP: Price swept below Asian Low (or PDL) and closed back above with lower wick rejection
      bool sweptLow = (low1 < g_AsianLow || low1 < g_PDL);
      bool closedAboveSweep = (close1 > g_AsianLow) && (close1 > open1);
      bool lowerWickRejection = (close1 - low1) >= (high1 - close1);
      bool macdTurningBullish = (macdHist_1 > macdHist_2);

      if (sweptLow && closedAboveSweep && lowerWickRejection && macdTurningBullish)
      {
         double price = Ask;
         // Place SL right below the sweep wick tip with small buffer
         double sweepSLDist = (price - low1) + 0.80;
         if (sweepSLDist < minStopUSD) sweepSLDist = minStopUSD;
         if (sweepSLDist < slDistUSD)  sweepSLDist = slDistUSD;

         double sl  = NormalizeDouble(price - sweepSLDist, Digits);
         double tp1 = NormalizeDouble(price + (sweepSLDist * InpRewardRatioTP1), Digits);

         string comment = "Intraday Sweep Buy";
         int ticket = OrderSend(Symbol(), OP_BUY, lot, price, InpSlippage, sl, tp1, comment, InpMagicNumber, 0, clrDodgerBlue);
         if (ticket > 0)
         {
            Print("[SWEEP BUY EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
                  " | Reason: Asian/PDL Liquidity Sweep Reversal",
                  " | Asian Low: $", DoubleToStr(g_AsianLow, 2), " | Sweep Low: $", DoubleToStr(low1, 2),
                  " | SL: ", sl, " | TP1: ", tp1);
            g_PartialClosed = false;
            g_LastBarTime = currentBarTime;
            return;
         }
      }

      // SELL SETUP: Price swept above Asian High (or PDH) and closed back below with upper wick rejection
      bool sweptHigh = (high1 > g_AsianHigh || high1 > g_PDH);
      bool closedBelowSweep = (close1 < g_AsianHigh) && (close1 < open1);
      bool upperWickRejection = (high1 - close1) >= (close1 - low1);
      bool macdTurningBearish = (macdHist_1 < macdHist_2);

      if (sweptHigh && closedBelowSweep && upperWickRejection && macdTurningBearish)
      {
         double price = Bid;
         // Place SL right above the sweep wick tip with small buffer
         double sweepSLDist = (high1 - price) + 0.80;
         if (sweepSLDist < minStopUSD) sweepSLDist = minStopUSD;
         if (sweepSLDist < slDistUSD)  sweepSLDist = slDistUSD;

         double sl  = NormalizeDouble(price + sweepSLDist, Digits);
         double tp1 = NormalizeDouble(price - (sweepSLDist * InpRewardRatioTP1), Digits);

         string comment = "Intraday Sweep Sell";
         int ticket = OrderSend(Symbol(), OP_SELL, lot, price, InpSlippage, sl, tp1, comment, InpMagicNumber, 0, clrCrimson);
         if (ticket > 0)
         {
            Print("[SWEEP SELL EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
                  " | Reason: Asian/PDH Liquidity Sweep Reversal",
                  " | Asian High: $", DoubleToStr(g_AsianHigh, 2), " | Sweep High: $", DoubleToStr(high1, 2),
                  " | SL: ", sl, " | TP1: ", tp1);
            g_PartialClosed = false;
            g_LastBarTime = currentBarTime;
            return;
         }
      }
   }

   // ====================================================================
   // SETUP B: LONDON MOMENTUM BREAKOUT & FVG / EMA RETEST
   // ====================================================================
   if (InpEnableFVGRetest)
   {
      bool trendBullish = (close1 > ema200 && ema50 > ema200);
      bool trendBearish = (close1 < ema200 && ema50 < ema200);

      // BUY PULLBACK RETEST: Low dipped into EMA20 zone + Close rejected up + MACD Gaining Momentum
      bool pulledBackBuy = (Low[1] <= ema20 || Low[2] <= ema20);
      bool rejectedUpBuy = (close1 >= ema20 && close1 > open1);
      bool macdBullishExpanding = (macdMain_1 > macdSig_1) && (macdHist_1 > macdHist_2 && macdHist_1 > 0);

      if (trendBullish && pulledBackBuy && rejectedUpBuy && macdBullishExpanding)
      {
         double price = Ask;
         double sl    = NormalizeDouble(price - slDistUSD, Digits);
         double tp1   = NormalizeDouble(price + tp1DistUSD, Digits);

         string comment = "Intraday Retest Buy";
         int ticket = OrderSend(Symbol(), OP_BUY, lot, price, InpSlippage, sl, tp1, comment, InpMagicNumber, 0, clrDodgerBlue);
         if (ticket > 0)
         {
            Print("[RETEST BUY EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
                  " | Reason: Momentum Break & EMA20 Retest",
                  " | MACD Hist: ", DoubleToStr(macdHist_1, 3), " > ", DoubleToStr(macdHist_2, 3),
                  " | SL: ", sl, " | TP1: ", tp1);
            g_PartialClosed = false;
            g_LastBarTime = currentBarTime;
            return;
         }
      }

      // SELL PULLBACK RETEST: High tested into EMA20 zone + Close rejected down + MACD Gaining Momentum
      bool pulledBackSell = (High[1] >= ema20 || High[2] >= ema20);
      bool rejectedDownSell = (close1 <= ema20 && close1 < open1);
      bool macdBearishExpanding = (macdMain_1 < macdSig_1) && (macdHist_1 < macdHist_2 && macdHist_1 < 0);

      if (trendBearish && pulledBackSell && rejectedDownSell && macdBearishExpanding)
      {
         double price = Bid;
         double sl    = NormalizeDouble(price + slDistUSD, Digits);
         double tp1   = NormalizeDouble(price - tp1DistUSD, Digits);

         string comment = "Intraday Retest Sell";
         int ticket = OrderSend(Symbol(), OP_SELL, lot, price, InpSlippage, sl, tp1, comment, InpMagicNumber, 0, clrCrimson);
         if (ticket > 0)
         {
            Print("[RETEST SELL EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
                  " | Reason: Momentum Break & EMA20 Retest",
                  " | MACD Hist: ", DoubleToStr(macdHist_1, 3), " < ", DoubleToStr(macdHist_2, 3),
                  " | SL: ", sl, " | TP1: ", tp1);
            g_PartialClosed = false;
            g_LastBarTime = currentBarTime;
            return;
         }
      }
   }

   g_LastBarTime = currentBarTime;
}

//+------------------------------------------------------------------+
//| Manage Open Intraday Trades: Partial Close at TP1 & ATR Trailing |
//+------------------------------------------------------------------+
void ManageOpenIntradayTrades()
{
   double atr = iATR(Symbol(), PERIOD_M15, InpATRPeriod, 1);
   if (atr <= 0) atr = 2.00;

   double minStopUSD = (MarketInfo(Symbol(), MODE_STOPLEVEL) * Point) + (10 * Point);

   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber)
         {
            int    ticket    = OrderTicket();
            double openPrice = OrderOpenPrice();
            double curLots   = OrderLots();
            double stopLoss  = OrderStopLoss();
            double takeProfit= OrderTakeProfit();
            double curPrice  = (OrderType() == OP_BUY) ? Bid : Ask;

            // 1. Partial Close at TP1 and Move SL to Break-Even
            if (takeProfit > 0)
            {
               bool tpReached = (OrderType() == OP_BUY) ? (curPrice >= takeProfit) : (curPrice <= takeProfit);

               if (tpReached && !g_PartialClosed)
               {
                  double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
                  double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
                  double closeLot = MathFloor((curLots * (InpPartialClosePercent / 100.0)) / lotStep) * lotStep;

                  if (closeLot >= minLot && (curLots - closeLot) >= minLot)
                  {
                     bool closed = OrderClose(ticket, closeLot, curPrice, InpSlippage, clrGold);
                     if (closed)
                     {
                        Print("[PARTIAL TP1 HIT] Closed ", DoubleToStr(closeLot, 2), " lots of #", ticket,
                              " at price ", curPrice, ". Moving SL to Break-Even for Runner!");
                        g_PartialClosed = true;

                        double beSL = (OrderType() == OP_BUY) ? NormalizeDouble(openPrice + InpBreakEvenBufferUSD, Digits)
                                                              : NormalizeDouble(openPrice - InpBreakEvenBufferUSD, Digits);
                        OrderModify(ticket, openPrice, beSL, 0, 0, clrGreen);
                        continue;
                     }
                  }
                  else
                  {
                     double beSL = (OrderType() == OP_BUY) ? NormalizeDouble(openPrice + InpBreakEvenBufferUSD, Digits)
                                                           : NormalizeDouble(openPrice - InpBreakEvenBufferUSD, Digits);
                     OrderModify(ticket, openPrice, beSL, 0, 0, clrGreen);
                     g_PartialClosed = true;
                  }
               }
            }

            // 2. Trailing Stop for the remaining Runner using M15 ATR
            if (InpUseTrailingStop && g_PartialClosed)
            {
               double trailDistUSD = atr * InpATRFactorTrail;
               if (trailDistUSD < minStopUSD) trailDistUSD = minStopUSD;

               if (OrderType() == OP_BUY)
               {
                  double newSL = NormalizeDouble(Bid - trailDistUSD, Digits);
                  if (newSL > stopLoss && newSL > openPrice)
                  {
                     OrderModify(ticket, openPrice, newSL, 0, 0, clrAqua);
                     Print("[TRAILING STOP UPDATED] BUY #", ticket, " SL trailed up to ", newSL);
                  }
               }
               else if (OrderType() == OP_SELL)
               {
                  double newSL = NormalizeDouble(Ask + trailDistUSD, Digits);
                  if ((newSL < stopLoss || stopLoss == 0) && newSL < openPrice)
                  {
                     OrderModify(ticket, openPrice, newSL, 0, 0, clrMagenta);
                     Print("[TRAILING STOP UPDATED] SELL #", ticket, " SL trailed down to ", newSL);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all intraday positions for this EA                         |
//+------------------------------------------------------------------+
void CloseAllIntradayPositions()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber)
         {
            double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
            OrderClose(OrderTicket(), OrderLots(), closePrice, InpSlippage, clrDarkKhaki);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check Spread against limit                                       |
//+------------------------------------------------------------------+
bool IsSpreadOk()
{
   double spreadUSD = Ask - Bid;
   double maxSpread = IsTesting() ? MathMax(InpMaxSpreadUSD, 0.80) : InpMaxSpreadUSD;
   return (spreadUSD <= maxSpread);
}

//+------------------------------------------------------------------+
//| Time Utilities                                                   |
//+------------------------------------------------------------------+
int GetCurrentUtcHour()
{
   int serverHour = TimeHour(TimeCurrent());
   int utc = serverHour - InpBrokerUtcOffset;
   if (utc < 0)  utc += 24;
   if (utc >= 24) utc -= 24;
   return utc;
}

int GetUtcHourFromTime(datetime t)
{
   int h = TimeHour(t);
   int utc = h - InpBrokerUtcOffset;
   if (utc < 0)  utc += 24;
   if (utc >= 24) utc -= 24;
   return utc;
}

//+------------------------------------------------------------------+
//| Interactive On-Chart Button Creation                             |
//+------------------------------------------------------------------+
void CreateResumeButton()
{
   if (ObjectFind(0, g_BtnName) < 0)
   {
      ObjectCreate(0, g_BtnName, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, g_BtnName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, g_BtnName, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, g_BtnName, OBJPROP_YDISTANCE, 290);
      ObjectSetInteger(0, g_BtnName, OBJPROP_XSIZE, 340);
      ObjectSetInteger(0, g_BtnName, OBJPROP_YSIZE, 30);
      ObjectSetInteger(0, g_BtnName, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, g_BtnName, OBJPROP_FONT, "Arial Bold");
   }
}

//+------------------------------------------------------------------+
//| On-Chart Heads-Up Dashboard Display & Button State               |
//+------------------------------------------------------------------+
void UpdateHUD()
{
   double bal = AccountBalance();
   double eq  = AccountEquity();
   double pnl = eq - g_InitialBalance;
   double pct = (g_InitialBalance > 0) ? (pnl / g_InitialBalance) * 100.0 : 0.0;
   double ddFromPeak = (g_PeakEquity > 0) ? ((g_PeakEquity - eq) / g_PeakEquity) * 100.0 : 0.0;

   double ema200 = iMA(Symbol(), PERIOD_M15, InpTrendEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   string trend = (Close[1] > ema200) ? "BULLISH (M15 > 200 EMA)" : "BEARISH (M15 < 200 EMA)";

   string sessionPhase = GetCurrentSessionPhase();

   // Update Button label & color
   CreateResumeButton();
   if (g_CircuitBreakerTripped)
   {
      ObjectSetString(0, g_BtnName, OBJPROP_TEXT, ">> CLICK TO RESUME TRADING NOW <<");
      ObjectSetInteger(0, g_BtnName, OBJPROP_BGCOLOR, clrOrangeRed);
      ObjectSetInteger(0, g_BtnName, OBJPROP_COLOR, clrWhite);
   }
   else if (g_DailyClosedForGapRisk)
   {
      ObjectSetString(0, g_BtnName, OBJPROP_TEXT, "100% CASH OVERNIGHT (Resumes Tomorrow)");
      ObjectSetInteger(0, g_BtnName, OBJPROP_BGCOLOR, clrDarkSlateGray);
      ObjectSetInteger(0, g_BtnName, OBJPROP_COLOR, clrSilver);
   }
   else if (g_InRecoveryMode)
   {
      ObjectSetString(0, g_BtnName, OBJPROP_TEXT, StringConcatenate("RECOVERY MODE ACTIVE (Stage ", g_RecoveryStage, ")"));
      ObjectSetInteger(0, g_BtnName, OBJPROP_BGCOLOR, clrGold);
      ObjectSetInteger(0, g_BtnName, OBJPROP_COLOR, clrBlack);
   }
   else
   {
      ObjectSetString(0, g_BtnName, OBJPROP_TEXT, "INTRADAY ACTIVE: " + sessionPhase);
      ObjectSetInteger(0, g_BtnName, OBJPROP_BGCOLOR, clrSeaGreen);
      ObjectSetInteger(0, g_BtnName, OBJPROP_COLOR, clrWhite);
   }

   string hud = "";
   hud += "====================================================\n";
   hud += "  XAUUSD INTRADAY MASTER EA (M15 PRECISION ENGINE)  \n";
   hud += "====================================================\n";
   hud += StringConcatenate("  Current Balance   : $", DoubleToStr(bal, 2), " (Initial: $", DoubleToStr(g_InitialBalance, 2), ")\n");
   hud += StringConcatenate("  Current Equity    : $", DoubleToStr(eq, 2), " | Total PnL: $", DoubleToStr(pnl, 2), " (", DoubleToStr(pct, 1), "%)\n");
   hud += StringConcatenate("  Peak Equity       : $", DoubleToStr(g_PeakEquity, 2), " | DD from Peak: ", DoubleToStr(ddFromPeak, 1), "% (Max: ", DoubleToStr(InpMaxDrawdownFromPeak, 1), "%)\n");
   hud += StringConcatenate("  Profit Floor      : $", DoubleToStr(g_ProfitFloor, 2), (g_ProfitFloor > 0 ? " [LOCKED CAPITAL]" : " [Not Set Yet]"), "\n");
   hud += "----------------------------------------------------\n";
   hud += StringConcatenate("  Asian Range (M15) : High: $", DoubleToStr(g_AsianHigh, 2), " | Low: $", DoubleToStr(g_AsianLow, 2), "\n");
   hud += StringConcatenate("  Daily Range (PDH) : High: $", DoubleToStr(g_PDH, 2), " | Low: $", DoubleToStr(g_PDL, 2), "\n");
   hud += StringConcatenate("  Session Phase     : ", sessionPhase, "\n");
   hud += StringConcatenate("  Daily Cash Target : Closes to 100% Cash at ", InpDailyCloseHourUTC, ":", InpDailyCloseMinuteUTC, " UTC\n");
   hud += StringConcatenate("  Trend Bias (M15)  : ", trend, "\n");
   hud += StringConcatenate("  Active Trades     : ", CountOpenIntradayTrades(), " trade(s)\n");
   hud += StringConcatenate("  Partial TP1 Status: ", (g_PartialClosed ? "TP1 BANKED (RUNNER TRAILING)" : "AWAITING TP1"), "\n");
   hud += StringConcatenate("  Current Gold Bid  : $", DoubleToStr(Bid, 2), " | Spread: $", DoubleToStr(Ask - Bid, 2), "\n");
   hud += "====================================================\n";

   Comment(hud);
}
