//+------------------------------------------------------------------+
//|                                         XAUUSD_SwingMaster.mq4   |
//|               Institutional Trend & Volatility Swing Engine      |
//|                    Engineered for Gold (XAUUSD) Swing Trading    |
//|                    Version 2.20: Safe Recovery & Restart Engine  |
//+------------------------------------------------------------------+
#property copyright "Quantitative Trading Engine"
#property link      "https://github.com"
#property version   "2.20"
#property strict

//--- Inputs: Strict Capital Protection & Mathematical Risk Sizing
input string   _Section1               = "=== Capital Preservation & Risk ===";
input double   InpRiskPercentPerTrade  = 4.0;      // Max Risk % per trade in Normal Mode (3.0% - 5.0%)
input double   InpMaxDrawdownFromPeak  = 15.0;     // Max Drawdown % from Peak Equity before emergency halt
input bool     InpEnableProfitRatchet  = true;     // Ratchet Profit Floor (Locks in gains at $200, $300, etc.)
input double   InpRewardRatioTP1       = 2.0;      // Risk-to-Reward ratio for TP1 (1:2 R:R)
input double   InpPartialClosePercent  = 50.0;     // Percentage of position to close at TP1 (50%)
input double   InpBreakEvenBufferUSD   = 0.50;     // Profit locked when moving to Break-Even ($0.50)

//--- Inputs: Safe Recovery & Restart Mode
input string   _Section1b              = "=== Safe Recovery & Restart Mode ===";
input bool     InpAutoResumeAfterHalt  = true;     // Automatically resume trading after cooldown
input int      InpHaltCooldownHours    = 8;        // Cooldown hours before auto-resuming (e.g. 8 hours)
input bool     InpEnableRecoveryMode   = true;     // Re-enter market in Safe Recovery Mode (Smallest lot first)
input double   InpRecoveryTargetUSD    = 15.00;    // Profit needed ($) to graduate from Recovery to Normal Mode
input double   InpRecoveryMinLot       = 0.01;     // Stage 1 Lot: Smallest lot size (0.01)
input double   InpRecoveryStepLot      = 0.02;     // Stage 2 Lot: Stepped-up lot size (0.02)

//--- Inputs: Trend & Pullback Logic
input string   _Section2               = "=== Trend & Pullback Logic ===";
input int      InpTrendEMA_Slow        = 200;      // Primary Trend Filter EMA (e.g. 200 EMA)
input int      InpPullbackEMA_Fast     = 20;       // Dynamic Support/Resistance Fast EMA (20)
input int      InpPullbackEMA_Slow     = 50;       // Dynamic Support/Resistance Slow EMA (50)
input int      InpRSIPeriod            = 14;       // RSI Period
input double   InpRSIBuyLevel          = 46.0;     // Buy when RSI pulls back below or near this level
input double   InpRSISellLevel         = 54.0;     // Sell when RSI rallies above or near this level

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
datetime  g_HaltTimestamp         = 0;
bool      g_InRecoveryMode        = false;
int       g_RecoveryStage         = 1;
double    g_RecoveryStartEquity   = 0.0;
datetime  g_LastBarTime           = 0;

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
   g_HaltTimestamp         = 0;
   g_InRecoveryMode        = false;
   g_RecoveryStage         = 1;
   g_RecoveryStartEquity   = g_InitialBalance;
   g_LastBarTime           = 0;

   // Create on-chart interactive resume button
   CreateResumeButton();

   Print("==================================================================");
   Print("[INIT] XAUUSD Swing Master Engine v2.20 Initialized.");
   Print("[INIT] Safe Recovery & Restart Engine Ready | Starting Balance: $", DoubleToStr(g_InitialBalance, 2),
         " | Leverage: 1:", AccountLeverage(),
         " | Contract Size: ", DoubleToStr(g_ContractSize, 0));
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
   // 1. Check Auto-Resume timer if halted
   if (g_CircuitBreakerTripped)
   {
      CheckAutoResumeTimer();
   }

   // 2. Maintain Peak Equity and Ratchet Profit Floors
   if (!g_CircuitBreakerTripped)
   {
      MaintainCapitalProtection();
   }

   // 3. Update HUD & Button status
   UpdateHUD();

   // 4. If halted, block execution until resumed
   if (g_CircuitBreakerTripped) return;

   // 5. Friday Volatility & Weekend Risk Manager
   if (InpEnableFridayFilter)
   {
      CheckFridayWeekendRisk();
   }

   // 6. Manage Active Open Swing Positions (TP1 Partial Close, Break-Even, ATR Trail)
   ManageOpenSwingTrades();

   // 7. Entry Guard Checks
   if (g_CircuitBreakerTripped) return;
   if (g_FridayClosedForLowVol) return;
   if (CountOpenSwingTrades() > 0) return; // Strictly 1 swing setup at a time
   if (!IsSpreadOk()) return;

   // 8. Check Swing Entry Signal
   CheckAndExecuteSwingEntry();
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
            Print("[BUTTON CLICKED] Trading is already active. Current Mode: ", (g_InRecoveryMode ? "RECOVERY" : "NORMAL"));
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

      // Ratchet Profit Floor as capital scales:
      if (InpEnableProfitRatchet && !g_InRecoveryMode)
      {
         if (g_PeakEquity >= 400.0)      g_ProfitFloor = MathMax(g_ProfitFloor, 330.0);
         else if (g_PeakEquity >= 300.0) g_ProfitFloor = MathMax(g_ProfitFloor, 240.0);
         else if (g_PeakEquity >= 200.0) g_ProfitFloor = MathMax(g_ProfitFloor, 150.0);
      }
   }

   // 1. Check Maximum Drawdown from Peak Equity
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

   // 2. Check Profit Floor Ratchet Breach
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
//| DYNAMIC RISK SIZING WITH PROGRESSIVE RECOVERY GRADUATION         |
//+------------------------------------------------------------------+
double CalculateDynamicRiskLot(double slDistanceUSD)
{
   double equity = AccountEquity();
   if (equity <= 0) equity = AccountBalance();

   // --- SAFE RECOVERY MODE LOGIC ---
   if (g_InRecoveryMode)
   {
      double recoveryGain = equity - g_RecoveryStartEquity;

      // Graduation Condition: Reached target profit
      if (recoveryGain >= InpRecoveryTargetUSD)
      {
         Print("==================================================================");
         Print("[RECOVERY COMPLETE] Account gained +$", DoubleToStr(recoveryGain, 2),
               " during recovery. Graduating to Normal Dynamic Risk Sizing!");
         Print("==================================================================");
         g_InRecoveryMode = false;
         g_PeakEquity     = MathMax(g_PeakEquity, equity);
      }
      // Stage 2: Stepped-Up Lot (50% of recovery goal hit)
      else if (recoveryGain >= (InpRecoveryTargetUSD * 0.50))
      {
         g_RecoveryStage = 2;
         return InpRecoveryStepLot;
      }
      // Stage 1: Absolute Smallest Lot (0.01)
      else
      {
         g_RecoveryStage = 1;
         return InpRecoveryMinLot;
      }
   }

   // --- NORMAL DYNAMIC RISK SIZING ---
   double maxRiskDollars = equity * (InpRiskPercentPerTrade / 100.0);
   double lossPerStandardLot = slDistanceUSD * g_ContractSize;

   double lot = 0.01;
   if (lossPerStandardLot > 0)
   {
      lot = maxRiskDollars / lossPerStandardLot;
   }

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   lot = MathFloor(lot / lotStep) * lotStep;
   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;

   // Margin check
   double marginReq = (Ask * lot * g_ContractSize) / MathMax(AccountLeverage(), 1);
   if (marginReq > (AccountFreeMargin() * 0.70) && lot > minLot)
   {
      lot = minLot;
   }

   return lot;
}

//+------------------------------------------------------------------+
//| Check Trend & Pullback Entry Signal                              |
//+------------------------------------------------------------------+
void CheckAndExecuteSwingEntry()
{
   datetime currentBarTime = Time[0];
   if (currentBarTime == g_LastBarTime) return;

   // 1. Trend Direction
   double ema200 = iMA(Symbol(), 0, InpTrendEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema50  = iMA(Symbol(), 0, InpPullbackEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema20  = iMA(Symbol(), 0, InpPullbackEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double close1 = Close[1];
   double low1   = Low[1];
   double high1  = High[1];
   double open1  = Open[1];

   // H4 trend confirmation if available
   double h4_Close = iClose(Symbol(), PERIOD_H4, 1);
   double h4_EMA50 = iMA(Symbol(), PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE, 1);
   bool h4Bullish = true;
   bool h4Bearish = true;
   if (h4_Close > 0 && h4_EMA50 > 0)
   {
      h4Bullish = (h4_Close >= h4_EMA50);
      h4Bearish = (h4_Close <= h4_EMA50);
   }

   bool trendBullish = (close1 > ema200 && ema50 > ema200 && h4Bullish);
   bool trendBearish = (close1 < ema200 && ema50 < ema200 && h4Bearish);

   // 2. RSI Pullback Condition
   double rsi_1 = iRSI(Symbol(), 0, InpRSIPeriod, PRICE_CLOSE, 1);
   double rsi_2 = iRSI(Symbol(), 0, InpRSIPeriod, PRICE_CLOSE, 2);

   // 3. ATR Dynamic Sizing
   double atr = iATR(Symbol(), 0, InpATRPeriod, 1);
   if (atr <= 0) atr = 2.50;
   double slDistUSD = atr * InpATRFactorSL;

   double minStopUSD = (MarketInfo(Symbol(), MODE_STOPLEVEL) * Point) + (10 * Point);
   if (slDistUSD < minStopUSD) slDistUSD = minStopUSD;
   if (slDistUSD < 2.50) slDistUSD = 2.50;

   double tp1DistUSD = slDistUSD * InpRewardRatioTP1;

   // Sizing: respects Safe Recovery Mode or Normal Mode
   double lot = CalculateDynamicRiskLot(slDistUSD);
   double actualRiskUSD = slDistUSD * lot * g_ContractSize;
   double actualRewardUSD = tp1DistUSD * lot * g_ContractSize;

   RefreshRates();

   // --- BUY SETUP ---
   bool touchedValueZoneBuy = (Low[1] <= ema20 || Low[2] <= ema20 || Low[3] <= ema20);

   if (trendBullish && touchedValueZoneBuy && close1 >= ema20 && close1 > open1 && rsi_1 > rsi_2 && rsi_1 <= 62.0)
   {
      double price = Ask;
      double sl    = NormalizeDouble(price - slDistUSD, Digits);
      double tp    = NormalizeDouble(price + tp1DistUSD, Digits);

      string comment = g_InRecoveryMode ? StringConcatenate("Recov S", g_RecoveryStage, " Buy") : "Swing Buy Setup";
      int ticket = OrderSend(Symbol(), OP_BUY, lot, price, InpSlippage, sl, tp, comment, InpMagicNumber, 0, clrDodgerBlue);
      if (ticket > 0)
      {
         Print("[SWING BUY EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
               " | Mode: ", (g_InRecoveryMode ? StringConcatenate("RECOVERY STAGE ", g_RecoveryStage) : "NORMAL DYNAMIC"),
               " | Dollar Risk: $", DoubleToStr(actualRiskUSD, 2),
               " | Potential Reward: $", DoubleToStr(actualRewardUSD, 2),
               " | SL: ", sl, " | TP1: ", tp);
         g_PartialClosed = false;
         g_LastBarTime = currentBarTime;
      }
      else
      {
         Print("[ERROR] Swing BUY OrderSend failed with error #", GetLastError());
      }
      return;
   }

   // --- SELL SETUP ---
   bool touchedValueZoneSell = (High[1] >= ema20 || High[2] >= ema20 || High[3] >= ema20);

   if (trendBearish && touchedValueZoneSell && close1 <= ema20 && close1 < open1 && rsi_1 < rsi_2 && rsi_1 >= 38.0)
   {
      double price = Bid;
      double sl    = NormalizeDouble(price + slDistUSD, Digits);
      double tp    = NormalizeDouble(price - tp1DistUSD, Digits);

      string comment = g_InRecoveryMode ? StringConcatenate("Recov S", g_RecoveryStage, " Sell") : "Swing Sell Setup";
      int ticket = OrderSend(Symbol(), OP_SELL, lot, price, InpSlippage, sl, tp, comment, InpMagicNumber, 0, clrCrimson);
      if (ticket > 0)
      {
         Print("[SWING SELL EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
               " | Mode: ", (g_InRecoveryMode ? StringConcatenate("RECOVERY STAGE ", g_RecoveryStage) : "NORMAL DYNAMIC"),
               " | Dollar Risk: $", DoubleToStr(actualRiskUSD, 2),
               " | Potential Reward: $", DoubleToStr(actualRewardUSD, 2),
               " | SL: ", sl, " | TP1: ", tp);
         g_PartialClosed = false;
         g_LastBarTime = currentBarTime;
      }
      else
      {
         Print("[ERROR] Swing SELL OrderSend failed with error #", GetLastError());
      }
      return;
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
      ObjectSetInteger(0, g_BtnName, OBJPROP_YDISTANCE, 260);
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

   // Mode and sizing description
   string modeStr = "NORMAL DYNAMIC RISK";
   if (g_InRecoveryMode)
   {
      double recovGain = eq - g_RecoveryStartEquity;
      modeStr = StringConcatenate("SAFE RECOVERY STAGE ", g_RecoveryStage, " (Gain: $", DoubleToStr(recovGain, 2), " / $", DoubleToStr(InpRecoveryTargetUSD, 2), ")");
   }

   // Update Button label & color
   CreateResumeButton();
   if (g_CircuitBreakerTripped)
   {
      int elapsedSec = int(TimeCurrent() - g_HaltTimestamp);
      int remainSec = MathMax(0, (InpHaltCooldownHours * 3600) - elapsedSec);
      int remainHours = remainSec / 3600;
      int remainMins  = (remainSec % 3600) / 60;

      ObjectSetString(0, g_BtnName, OBJPROP_TEXT, ">> CLICK TO RESUME TRADING NOW <<");
      ObjectSetInteger(0, g_BtnName, OBJPROP_BGCOLOR, clrOrangeRed);
      ObjectSetInteger(0, g_BtnName, OBJPROP_COLOR, clrWhite);
   }
   else if (g_InRecoveryMode)
   {
      ObjectSetString(0, g_BtnName, OBJPROP_TEXT, StringConcatenate("RECOVERY MODE ACTIVE (Stage ", g_RecoveryStage, ")"));
      ObjectSetInteger(0, g_BtnName, OBJPROP_BGCOLOR, clrGold);
      ObjectSetInteger(0, g_BtnName, OBJPROP_COLOR, clrBlack);
   }
   else
   {
      ObjectSetString(0, g_BtnName, OBJPROP_TEXT, "ENGINE RUNNING NORMALLY (ACTIVE)");
      ObjectSetInteger(0, g_BtnName, OBJPROP_BGCOLOR, clrSeaGreen);
      ObjectSetInteger(0, g_BtnName, OBJPROP_COLOR, clrWhite);
   }

   string hud = "";
   hud += "====================================================\n";
   hud += "  XAUUSD SWING MASTER EA v2.20 (SAFE RECOVERY)      \n";
   hud += "====================================================\n";
   hud += StringConcatenate("  Current Balance   : $", DoubleToStr(bal, 2), " (Initial: $", DoubleToStr(g_InitialBalance, 2), ")\n");
   hud += StringConcatenate("  Current Equity    : $", DoubleToStr(eq, 2), " | Total PnL: $", DoubleToStr(pnl, 2), " (", DoubleToStr(pct, 1), "%)\n");
   hud += StringConcatenate("  Peak Equity       : $", DoubleToStr(g_PeakEquity, 2), " | DD from Peak: ", DoubleToStr(ddFromPeak, 1), "% (Max: ", DoubleToStr(InpMaxDrawdownFromPeak, 1), "%)\n");
   hud += StringConcatenate("  Profit Floor      : $", DoubleToStr(g_ProfitFloor, 2), (g_ProfitFloor > 0 ? " [LOCKED CAPITAL]" : " [Not Set Yet]"), "\n");
   hud += "----------------------------------------------------\n";
   hud += StringConcatenate("  Engine Mode       : ", modeStr, "\n");
   hud += StringConcatenate("  Circuit Breaker   : ", (g_CircuitBreakerTripped ? "HALTED (Cooldown / Waiting Override)" : "ACTIVE & MONITORING"), "\n");
   hud += StringConcatenate("  Trend Bias        : ", trend, "\n");
   hud += StringConcatenate("  Active Trades     : ", CountOpenSwingTrades(), " trade(s)\n");
   hud += StringConcatenate("  Partial TP1 Status: ", (g_PartialClosed ? "TP1 BANKED (RUNNER TRAILING)" : "AWAITING TP1"), "\n");
   hud += StringConcatenate("  Current Gold Bid  : $", DoubleToStr(Bid, 2), " | Spread: $", DoubleToStr(Ask - Bid, 2), "\n");
   hud += "====================================================\n";

   Comment(hud);
}
