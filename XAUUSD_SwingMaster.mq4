//+------------------------------------------------------------------+
//|                                         XAUUSD_SwingMaster.mq4   |
//|               Institutional Trend & Volatility Swing Engine      |
//|                    Engineered for Gold (XAUUSD) Swing Trading    |
//|                    Version 2.50: MACD & RSI Dual Confluence      |
//+------------------------------------------------------------------+
#property copyright "Quantitative Trading Engine"
#property link      "https://github.com"
#property version   "2.50"
#property strict

//--- Inputs: Strict Capital Protection & Mathematical Risk Sizing
input string   _Section1               = "=== Capital Preservation & Risk ===";
input double   InpRiskPercentPerTrade  = 4.0;      // Max Risk % per trade in London Prime (3.0% - 5.0%)
input double   InpMaxDrawdownFromPeak  = 15.0;     // Max Drawdown % from Peak Equity before emergency halt
input bool     InpEnableProfitRatchet  = true;     // Ratchet Profit Floor (Locks in gains at $200, $300, etc.)
input double   InpRewardRatioTP1       = 2.0;      // Risk-to-Reward ratio for TP1 (1:2 R:R)
input double   InpPartialClosePercent  = 50.0;     // Percentage of position to close at TP1 (50%)
input double   InpBreakEvenBufferUSD   = 0.50;     // Profit locked when moving to Break-Even ($0.50)

//--- Inputs: MACD & RSI Dual Confluence Settings
input string   _Section1b              = "=== MACD & RSI Dual Confluence Engine ===";
input bool     InpEnableMACDReversals  = true;     // Enable S/R + MACD & RSI Reversals (Without MA filter)
input bool     InpEnableMACDPullback   = true;     // Enable Trend Pullbacks with MACD & RSI Momentum
input bool     InpRequireRSITrendSync  = true;     // Require RSI Slope & Zone confirmation on entries
input int      InpMACDFast             = 12;       // MACD Fast EMA Period
input int      InpMACDSlow             = 26;       // MACD Slow EMA Period
input int      InpMACDSignal           = 9;        // MACD Signal SMA Period
input double   InpMACDExtremeUSD       = 0.80;     // MACD Extreme threshold for high-confidence reversal
input int      InpRSIPeriod            = 14;       // RSI Period
input double   InpRSIOversoldBuy       = 44.0;     // RSI Oversold threshold for Support Reversals
input double   InpRSIOverboughtSell    = 56.0;     // RSI Overbought threshold for Resistance Reversals
input double   InpSRZoneBufferUSD      = 3.00;     // S/R proximity zone buffer in Gold $ ($3.00)

//--- Inputs: Session Risk & Daily Gap Guard
input string   _Section1c              = "=== Session Risk & Daily Gap Guard ===";
input bool     InpEnableSessionRisk    = true;     // Enable Dynamic Session Risk & Daily Gap Protection
input int      InpLondonStartHourUTC   = 7;        // London Open (07:00 UTC) - Full Normal Risk
input int      InpOverlapStartHourUTC  = 12;       // London-US Overlap Start (12:00 UTC) - Min Risk Sizing
input int      InpLondonEndHourUTC     = 16;       // London Session End (16:00 UTC) - Post-London Min Risk
input int      InpHardStopTradingUTC   = 17;       // Hard Cutoff (17:00 UTC) - STOP all order placement
input bool     InpForceCloseDaily      = true;     // Close all trades before daily market close/rollover
input int      InpDailyCloseHourUTC    = 20;       // Daily close hour (20:00 UTC) to liquidate open trades
input int      InpDailyCloseMinuteUTC  = 45;       // Daily close minute (20:45 UTC) to liquidate open trades

//--- Inputs: Safe Recovery & Restart Mode
input string   _Section1d              = "=== Safe Recovery & Restart Mode ===";
input bool     InpAutoResumeAfterHalt  = true;     // Automatically resume trading after cooldown
input int      InpHaltCooldownHours    = 8;        // Cooldown hours before auto-resuming (e.g. 8 hours)
input bool     InpEnableRecoveryMode   = true;     // Re-enter market in Safe Recovery Mode (Smallest lot first)
input double   InpRecoveryTargetUSD    = 15.00;    // Profit needed ($) to graduate from Recovery to Normal Mode
input double   InpRecoveryMinLot       = 0.01;     // Stage 1 Lot: Smallest lot size (0.01)
input double   InpRecoveryStepLot      = 0.02;     // Stage 2 Lot: Stepped-up lot size (0.02)

//--- Inputs: Trend & Pullback Logic
input string   _Section2               = "=== Trend & Moving Averages ===";
input int      InpTrendEMA_Slow        = 200;      // Primary Trend Filter EMA (e.g. 200 EMA)
input int      InpPullbackEMA_Fast     = 20;       // Dynamic Support/Resistance Fast EMA (20)
input int      InpPullbackEMA_Slow     = 50;       // Dynamic Support/Resistance Slow EMA (50)

//--- Inputs: Dynamic Stop Loss & ATR Trailing Stop
input string   _Section3               = "=== Stop Loss & ATR Trailing ===";
input int      InpATRPeriod            = 14;       // ATR Period for Stop Loss and Trailing
input double   InpATRFactorSL          = 1.5;      // Initial SL Multiplier of ATR
input double   InpATRFactorTrail       = 2.0;      // Runner Trailing Stop Multiplier of ATR
input bool     InpUseTrailingStop      = true;     // Enable Trailing Stop on Runner

//--- Inputs: Friday Volatility & Weekend Risk Filter
input string   _Section4               = "=== Friday Volatility & Weekend Guard ===";
input bool     InpEnableFridayFilter   = true;     // Enable Friday Late Session Volatility Check
input int      InpFridayCheckHourUTC   = 19;       // Friday UTC Hour to begin checking volatility (19:00 UTC)
input int      InpFridayCloseHourUTC   = 21;       // Friday UTC Hour to close if volatility is low (21:00 UTC)
input double   InpFridayVolThreshold   = 0.70;     // Low Volatility Threshold (Current ATR < 70% of 24-hr ATR)
input int      InpBrokerUtcOffset      = 2;        // Broker Server UTC/GMT Offset (e.g. +2 or +3)

//--- Inputs: Execution & Filters
input string   _Section5               = "=== Execution & Filters ===";
input double   InpMaxSpreadUSD         = 0.60;     // Max Allowable Spread in Gold $ ($0.60 = 60 pips)
input int      InpMagicNumber          = 999100;   // Unique Magic Number for Swing Trades
input int      InpSlippage             = 50;       // Max Slippage in Points
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

// S/R Cache
double    g_PDH                   = 0.0;
double    g_PDL                   = 0.0;
double    g_TodayHigh             = 0.0;
double    g_TodayLow              = 0.0;

string    g_BtnName               = "btn_SwingResume";

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

   // Initial S/R calculation
   UpdateSupportResistance();

   // Create on-chart interactive resume button
   CreateResumeButton();

   Print("==================================================================");
   Print("[INIT] XAUUSD Swing Master Engine v2.50 Initialized.");
   Print("[INIT] MACD & RSI Dual Confluence Engine: ACTIVE");
   Print("[INIT] PDH: $", DoubleToStr(g_PDH, 2), " | PDL: $", DoubleToStr(g_PDL, 2),
         " | Today High: $", DoubleToStr(g_TodayHigh, 2), " | Today Low: $", DoubleToStr(g_TodayLow, 2));
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

   // 4. Daily Gap & Rollover Risk Liquidation Check
   if (InpForceCloseDaily)
   {
      CheckDailyGapRisk();
   }

   // 5. Friday Volatility & Weekend Risk Manager
   if (InpEnableFridayFilter)
   {
      CheckFridayWeekendRisk();
   }

   // 6. Update S/R Levels dynamically
   UpdateSupportResistance();

   // 7. Update HUD & Button status
   UpdateHUD();

   // 8. If halted, block execution until resumed
   if (g_CircuitBreakerTripped) return;

   // 9. Manage Active Open Swing Positions (TP1 Partial Close, Break-Even, ATR Trail)
   ManageOpenSwingTrades();

   // 10. Entry Guard Checks
   if (!IsOrderPlacementAllowed()) return;
   if (g_DailyClosedForGapRisk) return;
   if (g_FridayClosedForLowVol) return;
   if (CountOpenSwingTrades() > 0) return; // Strictly 1 swing setup at a time
   if (!IsSpreadOk()) return;

   // 11. Check Swing Entry Signal
   CheckAndExecuteSwingEntry();
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
      Print("[NEW DAY] Daily session reset. Recalibrating PDH/PDL and Daily Gap guard.");
      UpdateSupportResistance();
   }
}

//+------------------------------------------------------------------+
//| Calculate Support & Resistance: Previous Day & Current Day H/L   |
//+------------------------------------------------------------------+
void UpdateSupportResistance()
{
   g_PDH = iHigh(Symbol(), PERIOD_D1, 1);
   g_PDL = iLow(Symbol(), PERIOD_D1, 1);

   datetime serverNow = TimeCurrent();
   int sYear  = TimeYear(serverNow);
   int sMonth = TimeMonth(serverNow);
   int sDay   = TimeDay(serverNow);

   double tHigh = -1.0;
   double tLow  = 999999.0;
   int matchedBars = 0;

   for (int i = 0; i < Bars && i < 200; i++)
   {
      datetime bTime = Time[i];
      if (TimeYear(bTime) == sYear && TimeMonth(bTime) == sMonth && TimeDay(bTime) == sDay)
      {
         if (High[i] > tHigh) tHigh = High[i];
         if (Low[i] < tLow)   tLow  = Low[i];
         matchedBars++;
      }
      else if (matchedBars > 0)
      {
         break;
      }
   }

   if (tHigh > 0)       g_TodayHigh = tHigh;
   else if (g_PDH > 0)  g_TodayHigh = g_PDH;

   if (tLow < 999998.0) g_TodayLow  = tLow;
   else if (g_PDL > 0)  g_TodayLow  = g_PDL;
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
      if (CountOpenSwingTrades() > 0)
      {
         Print("[DAILY GAP GUARD] Reached daily cutoff time (", InpDailyCloseHourUTC, ":", InpDailyCloseMinuteUTC,
               " UTC). Closing all positions before rollover to eliminate overnight gap risk.");
         CloseAllSwingPositions();
         g_DailyClosedForGapRisk = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if New Orders are Allowed based on Session Hours           |
//+------------------------------------------------------------------+
bool IsOrderPlacementAllowed()
{
   if (!InpEnableSessionRisk) return true;

   int utcHour = GetCurrentUtcHour();

   if (utcHour < InpLondonStartHourUTC) return false;
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
      return "Asian / Pre-London (No Orders Placed)";
   if (utcHour >= InpLondonStartHourUTC && utcHour < InpOverlapStartHourUTC)
      return "London Prime Session (Normal Dynamic Risk)";
   if (utcHour >= InpOverlapStartHourUTC && utcHour < InpLondonEndHourUTC)
      return "London-US Overlap (MINIMUM RISK: 0.01 Lot)";
   if (utcHour >= InpLondonEndHourUTC && utcHour < InpHardStopTradingUTC)
      return "Post-London Final (MINIMUM RISK: 0.01 Lot)";
   if (utcHour >= InpHardStopTradingUTC && utcHour < InpDailyCloseHourUTC)
      return "TRADING STOPPED (Post-London Cutoff)";
   
   return "Daily Rollover / Gap Protection (No Trading)";
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
   CloseAllSwingPositions();
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
               if (CountOpenSwingTrades() > 0)
               {
                  Print("[FRIDAY WEEKEND GUARD] Low volatility detected on Friday late session. Current ATR: $",
                        DoubleToStr(currentATR, 2), " < ", DoubleToStr(InpFridayVolThreshold * 100.0, 0),
                        "% of Average ATR ($", DoubleToStr(avgATR, 2), "). Closing positions to eliminate weekend gap risk.");
                  CloseAllSwingPositions();
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
//| Count active swing positions for this EA                         |
//+------------------------------------------------------------------+
int CountOpenSwingTrades()
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
//| DYNAMIC RISK SIZING WITH SESSION RISK MINIMIZATION               |
//+------------------------------------------------------------------+
double CalculateDynamicRiskLot(double slDistanceUSD)
{
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   int utcHour = GetCurrentUtcHour();

   if (InpEnableSessionRisk && utcHour >= InpOverlapStartHourUTC && utcHour < InpHardStopTradingUTC)
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

   // Normal Dynamic Sizing
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
//| Check Entry Signals: MACD & RSI Dual Confluence                  |
//+------------------------------------------------------------------+
void CheckAndExecuteSwingEntry()
{
   datetime currentBarTime = Time[0];
   if (currentBarTime == g_LastBarTime) return;

   // 1. Moving Averages
   double ema200 = iMA(Symbol(), 0, InpTrendEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema50  = iMA(Symbol(), 0, InpPullbackEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema20  = iMA(Symbol(), 0, InpPullbackEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double close1 = Close[1];
   double low1   = Low[1];
   double high1  = High[1];
   double open1  = Open[1];

   // 2. MACD Calculations (Main, Signal, and Histogram for bar 1 and 2)
   double macdMain_1 = iMACD(Symbol(), 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, 1);
   double macdSig_1  = iMACD(Symbol(), 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, 1);
   double macdMain_2 = iMACD(Symbol(), 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, 2);
   double macdSig_2  = iMACD(Symbol(), 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, 2);

   double macdHist_1 = macdMain_1 - macdSig_1;
   double macdHist_2 = macdMain_2 - macdSig_2;

   // 3. RSI Calculations (Bar 1 and Bar 2)
   double rsi_1 = iRSI(Symbol(), 0, InpRSIPeriod, PRICE_CLOSE, 1);
   double rsi_2 = iRSI(Symbol(), 0, InpRSIPeriod, PRICE_CLOSE, 2);

   // 4. Dynamic ATR Stop Loss Calculation
   double atr = iATR(Symbol(), 0, InpATRPeriod, 1);
   if (atr <= 0) atr = 2.50;
   double slDistUSD = atr * InpATRFactorSL;

   double minStopUSD = (MarketInfo(Symbol(), MODE_STOPLEVEL) * Point) + (10 * Point);
   if (slDistUSD < minStopUSD) slDistUSD = minStopUSD;
   if (slDistUSD < 2.50) slDistUSD = 2.50;

   double tp1DistUSD = slDistUSD * InpRewardRatioTP1;
   double lot = CalculateDynamicRiskLot(slDistUSD);

   RefreshRates();

   // ====================================================================
   // SETUP TYPE 1: HIGH-CONFIDENCE MACD & RSI REVERSAL AT KEY S/R
   // (USER RULES: Entered WITHOUT regards to Moving Average)
   // ====================================================================
   if (InpEnableMACDReversals)
   {
      // A) BUY REVERSAL AT SUPPORT (PDL or Today's Low)
      bool nearSupport = (low1 <= (g_PDL + InpSRZoneBufferUSD) && close1 >= (g_PDL - InpSRZoneBufferUSD)) ||
                         (low1 <= (g_TodayLow + InpSRZoneBufferUSD));
      
      // Price action: Bullish rejection candle at support
      bool bullishRejectionAtSupport = (close1 > open1) && ((close1 - low1) >= (high1 - close1));

      // MACD high-confidence turning up from oversold territory
      bool macdHighConfBuy = (macdHist_1 > macdHist_2) && 
                             ((macdMain_1 < -InpMACDExtremeUSD) || (macdHist_2 < 0 && macdHist_1 >= 0));

      // RSI confirmation: Hooking up from oversold/low territory
      bool rsiConfBuy = (rsi_1 > rsi_2) && (rsi_2 <= InpRSIOversoldBuy || rsi_1 <= 48.0);
      if (!InpRequireRSITrendSync) rsiConfBuy = true;

      if (nearSupport && bullishRejectionAtSupport && macdHighConfBuy && rsiConfBuy)
      {
         double price = Ask;
         double sl    = NormalizeDouble(price - slDistUSD, Digits);
         double tp    = NormalizeDouble(price + tp1DistUSD, Digits);

         string comment = "MACD+RSI S/R Buy Rev";
         int ticket = OrderSend(Symbol(), OP_BUY, lot, price, InpSlippage, sl, tp, comment, InpMagicNumber, 0, clrDodgerBlue);
         if (ticket > 0)
         {
            Print("[MACD+RSI REVERSAL BUY] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
                  " | Reason: S/R Support Reversal ($", DoubleToStr(g_PDL, 2), " / $", DoubleToStr(g_TodayLow, 2), ")",
                  " | MACD Hist: ", DoubleToStr(macdHist_1, 3), " > ", DoubleToStr(macdHist_2, 3),
                  " | RSI: ", DoubleToStr(rsi_1, 1), " (Slope +)",
                  " | SL: ", sl, " | TP1: ", tp);
            g_PartialClosed = false;
            g_LastBarTime = currentBarTime;
            return;
         }
      }

      // B) SELL REVERSAL AT RESISTANCE (PDH or Today's High)
      bool nearResistance = (high1 >= (g_PDH - InpSRZoneBufferUSD) && close1 <= (g_PDH + InpSRZoneBufferUSD)) ||
                            (high1 >= (g_TodayHigh - InpSRZoneBufferUSD));

      // Price action: Bearish rejection candle at resistance
      bool bearishRejectionAtResistance = (close1 < open1) && ((high1 - close1) >= (close1 - low1));

      // MACD high-confidence turning down from overbought territory
      bool macdHighConfSell = (macdHist_1 < macdHist_2) && 
                              ((macdMain_1 > InpMACDExtremeUSD) || (macdHist_2 > 0 && macdHist_1 <= 0));

      // RSI confirmation: Hooking down from overbought/high territory
      bool rsiConfSell = (rsi_1 < rsi_2) && (rsi_2 >= InpRSIOverboughtSell || rsi_1 >= 52.0);
      if (!InpRequireRSITrendSync) rsiConfSell = true;

      if (nearResistance && bearishRejectionAtResistance && macdHighConfSell && rsiConfSell)
      {
         double price = Bid;
         double sl    = NormalizeDouble(price + slDistUSD, Digits);
         double tp    = NormalizeDouble(price - tp1DistUSD, Digits);

         string comment = "MACD+RSI S/R Sell Rev";
         int ticket = OrderSend(Symbol(), OP_SELL, lot, price, InpSlippage, sl, tp, comment, InpMagicNumber, 0, clrCrimson);
         if (ticket > 0)
         {
            Print("[MACD+RSI REVERSAL SELL] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
                  " | Reason: S/R Resistance Reversal ($", DoubleToStr(g_PDH, 2), " / $", DoubleToStr(g_TodayHigh, 2), ")",
                  " | MACD Hist: ", DoubleToStr(macdHist_1, 3), " < ", DoubleToStr(macdHist_2, 3),
                  " | RSI: ", DoubleToStr(rsi_1, 1), " (Slope -)",
                  " | SL: ", sl, " | TP1: ", tp);
            g_PartialClosed = false;
            g_LastBarTime = currentBarTime;
            return;
         }
      }
   }

   // ====================================================================
   // SETUP TYPE 2: MACD & RSI MOMENTUM + MOVING AVERAGE PULLBACK
   // (USER RULES: Trend Pullback into MA confirmed by MACD & RSI)
   // ====================================================================
   if (InpEnableMACDPullback)
   {
      bool trendBullish = (close1 > ema200 && ema50 > ema200);
      bool trendBearish = (close1 < ema200 && ema50 < ema200);

      // A) BUY PULLBACK: Price pulled back to EMA 20/50 zone + MACD & RSI Expanding Momentum
      bool touchedValueZoneBuy = (Low[1] <= ema20 || Low[2] <= ema20 || Low[3] <= ema20);
      bool priceRejectedZoneBuy = (close1 >= ema20 && close1 > open1);
      
      // MACD expanding momentum
      bool macdGainingBullish = (macdMain_1 > macdSig_1) && (macdHist_1 > macdHist_2 && macdHist_1 > 0);
      
      // RSI confirming trend resumption (above 45, hooking up, not overbought)
      bool rsiBullishResumption = (rsi_1 > rsi_2) && (rsi_1 >= 45.0 && rsi_1 <= 64.0);
      if (!InpRequireRSITrendSync) rsiBullishResumption = true;

      if (trendBullish && touchedValueZoneBuy && priceRejectedZoneBuy && macdGainingBullish && rsiBullishResumption)
      {
         double price = Ask;
         double sl    = NormalizeDouble(price - slDistUSD, Digits);
         double tp    = NormalizeDouble(price + tp1DistUSD, Digits);

         string comment = "MACD+RSI MA Pullback Buy";
         int ticket = OrderSend(Symbol(), OP_BUY, lot, price, InpSlippage, sl, tp, comment, InpMagicNumber, 0, clrDodgerBlue);
         if (ticket > 0)
         {
            Print("[MACD+RSI PULLBACK BUY] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
                  " | Reason: Bullish Trend Resumption with MACD & RSI Confluence",
                  " | MACD Hist: ", DoubleToStr(macdHist_1, 3), " > ", DoubleToStr(macdHist_2, 3),
                  " | RSI: ", DoubleToStr(rsi_1, 1), " (Bullish Momentum)",
                  " | SL: ", sl, " | TP1: ", tp);
            g_PartialClosed = false;
            g_LastBarTime = currentBarTime;
            return;
         }
      }

      // B) SELL PULLBACK: Price pulled back to EMA 20/50 zone + MACD & RSI Expanding Momentum
      bool touchedValueZoneSell = (High[1] >= ema20 || High[2] >= ema20 || High[3] >= ema20);
      bool priceRejectedZoneSell = (close1 <= ema20 && close1 < open1);
      
      // MACD expanding momentum
      bool macdGainingBearish = (macdMain_1 < macdSig_1) && (macdHist_1 < macdHist_2 && macdHist_1 < 0);
      
      // RSI confirming trend resumption (below 55, hooking down, not oversold)
      bool rsiBearishResumption = (rsi_1 < rsi_2) && (rsi_1 <= 55.0 && rsi_1 >= 36.0);
      if (!InpRequireRSITrendSync) rsiBearishResumption = true;

      if (trendBearish && touchedValueZoneSell && priceRejectedZoneSell && macdGainingBearish && rsiBearishResumption)
      {
         double price = Bid;
         double sl    = NormalizeDouble(price + slDistUSD, Digits);
         double tp    = NormalizeDouble(price - tp1DistUSD, Digits);

         string comment = "MACD+RSI MA Pullback Sell";
         int ticket = OrderSend(Symbol(), OP_SELL, lot, price, InpSlippage, sl, tp, comment, InpMagicNumber, 0, clrCrimson);
         if (ticket > 0)
         {
            Print("[MACD+RSI PULLBACK SELL] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
                  " | Reason: Bearish Trend Resumption with MACD & RSI Confluence",
                  " | MACD Hist: ", DoubleToStr(macdHist_1, 3), " < ", DoubleToStr(macdHist_2, 3),
                  " | RSI: ", DoubleToStr(rsi_1, 1), " (Bearish Momentum)",
                  " | SL: ", sl, " | TP1: ", tp);
            g_PartialClosed = false;
            g_LastBarTime = currentBarTime;
            return;
         }
      }
   }

   g_LastBarTime = currentBarTime;
}

//+------------------------------------------------------------------+
//| Manage Open Swing Trades: Partial Close at TP1 & ATR Trailing    |
//+------------------------------------------------------------------+
void ManageOpenSwingTrades()
{
   double atr = iATR(Symbol(), 0, InpATRPeriod, 1);
   if (atr <= 0) atr = 3.00;

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

            // 2. Trailing Stop for the remaining Runner using ATR
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
//| Close all swing positions for this EA                            |
//+------------------------------------------------------------------+
void CloseAllSwingPositions()
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

   double ema200 = iMA(Symbol(), 0, InpTrendEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   string trend = (Close[1] > ema200) ? "BULLISH (BUY ONLY)" : "BEARISH (SELL ONLY)";

   double macdM = iMACD(Symbol(), 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, 1);
   double macdS = iMACD(Symbol(), 0, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, 1);
   double macdH = macdM - macdS;
   string macdDesc = (macdH > 0) ? "Expanding Bullish" : "Expanding Bearish";

   double rsiVal = iRSI(Symbol(), 0, InpRSIPeriod, PRICE_CLOSE, 1);
   string rsiDesc = (rsiVal >= 50.0) ? "Bullish Territory" : "Bearish Territory";

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
      ObjectSetString(0, g_BtnName, OBJPROP_TEXT, "DAILY GAP LOCK (Resumes Tomorrow)");
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
      ObjectSetString(0, g_BtnName, OBJPROP_TEXT, "SESSION ACTIVE: " + sessionPhase);
      ObjectSetInteger(0, g_BtnName, OBJPROP_BGCOLOR, clrSeaGreen);
      ObjectSetInteger(0, g_BtnName, OBJPROP_COLOR, clrWhite);
   }

   string hud = "";
   hud += "====================================================\n";
   hud += "  XAUUSD SWING MASTER EA v2.50 (MACD & RSI DUAL)    \n";
   hud += "====================================================\n";
   hud += StringConcatenate("  Current Balance   : $", DoubleToStr(bal, 2), " (Initial: $", DoubleToStr(g_InitialBalance, 2), ")\n");
   hud += StringConcatenate("  Current Equity    : $", DoubleToStr(eq, 2), " | Total PnL: $", DoubleToStr(pnl, 2), " (", DoubleToStr(pct, 1), "%)\n");
   hud += StringConcatenate("  Peak Equity       : $", DoubleToStr(g_PeakEquity, 2), " | DD from Peak: ", DoubleToStr(ddFromPeak, 1), "% (Max: ", DoubleToStr(InpMaxDrawdownFromPeak, 1), "%)\n");
   hud += StringConcatenate("  Profit Floor      : $", DoubleToStr(g_ProfitFloor, 2), (g_ProfitFloor > 0 ? " [LOCKED CAPITAL]" : " [Not Set Yet]"), "\n");
   hud += "----------------------------------------------------\n";
   hud += StringConcatenate("  Key S/R Levels    : PDH: $", DoubleToStr(g_PDH, 2), " | PDL: $", DoubleToStr(g_PDL, 2), "\n");
   hud += StringConcatenate("  Today Extremes    : High: $", DoubleToStr(g_TodayHigh, 2), " | Low: $", DoubleToStr(g_TodayLow, 2), "\n");
   hud += StringConcatenate("  MACD Momentum     : Hist: ", DoubleToStr(macdH, 3), " (", macdDesc, ")\n");
   hud += StringConcatenate("  RSI Indicator     : ", DoubleToStr(rsiVal, 1), " (", rsiDesc, ")\n");
   hud += StringConcatenate("  Session Phase     : ", sessionPhase, "\n");
   hud += StringConcatenate("  New Orders Allowed: ", (IsOrderPlacementAllowed() ? "YES" : "NO (Outside Window)"), "\n");
   hud += StringConcatenate("  Active Trades     : ", CountOpenSwingTrades(), " trade(s)\n");
   hud += StringConcatenate("  Partial TP1 Status: ", (g_PartialClosed ? "TP1 BANKED (RUNNER TRAILING)" : "AWAITING TP1"), "\n");
   hud += StringConcatenate("  Current Gold Bid  : $", DoubleToStr(Bid, 2), " | Spread: $", DoubleToStr(Ask - Bid, 2), "\n");
   hud += "====================================================\n";

   Comment(hud);
}
