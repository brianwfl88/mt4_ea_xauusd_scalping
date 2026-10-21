//+------------------------------------------------------------------+
//|                                         XAUUSD_SwingMaster.mq4   |
//|               Institutional Trend & Volatility Swing Engine      |
//|                    Engineered for Gold (XAUUSD) Swing Trading    |
//|                    Updated: Multi-Timeframe & Tester Resilient   |
//+------------------------------------------------------------------+
#property copyright "Quantitative Trading Engine"
#property link      "https://github.com"
#property version   "1.10"
#property strict

//--- Inputs: Account Sizing & Risk Management
input string   _Section1               = "=== Sizing & Compounding Tiers ===";
input bool     InpUseDynamicTiers      = true;     // Enable Dynamic Compounding Tiers
input double   InpManualBaseLot        = 0.02;     // Manual Lot if Dynamic Tiers disabled (0.02 at 1:500)
input double   InpRewardRatioTP1       = 2.0;      // Risk-to-Reward ratio for TP1 (e.g. 1:2 R:R)
input double   InpPartialClosePercent  = 50.0;     // Percentage of position to close at TP1 (50%)
input double   InpBreakEvenBufferUSD   = 0.50;     // Profit locked when moving to Break-Even ($0.50)

//--- Inputs: Trend & Pullback Logic
input string   _Section2               = "=== Trend & Pullback Logic ===";
input int      InpTrendEMA_Slow        = 200;      // Primary Trend Filter EMA (e.g. 200 EMA)
input int      InpPullbackEMA_Fast     = 20;       // Dynamic Support/Resistance Fast EMA (20)
input int      InpPullbackEMA_Slow     = 50;       // Dynamic Support/Resistance Slow EMA (50)
input int      InpRSIPeriod            = 14;       // RSI Period
input double   InpRSIBuyLevel          = 46.0;     // Buy when RSI pulls back below or near this level
input double   InpRSISellLevel         = 54.0;     // Sell when RSI rallies above or near this level

//--- Inputs: Stop Loss & ATR Trailing Stop
input string   _Section3               = "=== Stop Loss & ATR Trailing ===";
input int      InpATRPeriod            = 14;       // ATR Period for Stop Loss and Trailing
input double   InpATRFactorSL          = 1.5;      // Initial SL Multiplier of ATR ($4.00 - $6.00 risk)
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
double g_ContractSize          = 100.0;
double g_InitialBalance        = 0.0;
bool   g_PartialClosed         = false;
bool   g_FridayClosedForLowVol   = false;
datetime g_LastBarTime         = 0;

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

   g_InitialBalance = AccountBalance();
   g_PartialClosed = false;
   g_FridayClosedForLowVol = false;
   g_LastBarTime = 0;

   Print("==================================================================");
   Print("[INIT] XAUUSD Swing Master Engine v1.10 Ready.");
   Print("[INIT] Balance: $", DoubleToStr(g_InitialBalance, 2),
         " | Leverage: 1:", AccountLeverage(),
         " | Contract Size: ", DoubleToStr(g_ContractSize, 0),
         " | MinStopLevel: ", MarketInfo(Symbol(), MODE_STOPLEVEL), " points");
   Print("==================================================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Friday Volatility & Weekend Risk Manager
   if (InpEnableFridayFilter)
   {
      CheckFridayWeekendRisk();
   }

   // 2. Manage Active Open Swing Positions (TP1 Partial Close, Break-Even, ATR Trail)
   ManageOpenSwingTrades();

   // 3. Update HUD Display
   UpdateHUD();

   // 4. Entry Guard Checks
   if (g_FridayClosedForLowVol) return;
   if (CountOpenSwingTrades() > 0) return; // Holds 1 high-conviction swing setup at a time
   if (!IsSpreadOk()) return;

   // 5. Check Swing Entry Signal (Evaluated once per bar on bar open or live ticks)
   CheckAndExecuteSwingEntry();
}

//+------------------------------------------------------------------+
//| Check Friday Volatility and Close Before Weekend if Low          |
//+------------------------------------------------------------------+
void CheckFridayWeekendRisk()
{
   datetime now = TimeCurrent();
   int dayOfWeek = TimeDayOfWeek(now);

   // Friday is Day 5
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
//| Calculate Lot Size using Dynamic Compounding Tiers for 1:500     |
//+------------------------------------------------------------------+
double GetCompoundedSwingLot()
{
   double lot = InpManualBaseLot;

   if (InpUseDynamicTiers)
   {
      double bal = AccountBalance();
      // Compounding tiers optimized for 1:500 leverage:
      // $100 - $149 : 0.02 lot ($10.60 margin)
      // $150 - $249 : 0.04 lot ($21.20 margin)
      // $250 - $379 : 0.07 lot ($37.10 margin)
      // $380+       : 0.10 lot ($53.00 margin)
      if (bal >= 380.0)      lot = 0.10;
      else if (bal >= 250.0) lot = 0.07;
      else if (bal >= 150.0) lot = 0.04;
      else                   lot = 0.02;
   }

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;
   lot = MathFloor(lot / lotStep) * lotStep;

   // Margin safety check
   double marginReq = (Ask * lot * g_ContractSize) / MathMax(AccountLeverage(), 1);
   if (marginReq > (AccountFreeMargin() * 0.70) && lot > minLot)
   {
      lot = minLot;
   }

   return lot;
}

//+------------------------------------------------------------------+
//| Check Trend & Pullback Entry Signal (Self-Contained & Resilient) |
//+------------------------------------------------------------------+
void CheckAndExecuteSwingEntry()
{
   // Only evaluate on new bar formation to avoid intra-bar whipsaw
   datetime currentBarTime = Time[0];
   if (currentBarTime == g_LastBarTime) return;

   // 1. Determine Trend Direction:
   // Uses 200-EMA on current chart (or H4 fallback if available)
   double ema200 = iMA(Symbol(), 0, InpTrendEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema50  = iMA(Symbol(), 0, InpPullbackEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema20  = iMA(Symbol(), 0, InpPullbackEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double close1 = Close[1];
   double low1   = Low[1];
   double high1  = High[1];
   double open1  = Open[1];

   // Attempt H4 trend confirmation if H4 data is present in tester/terminal
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

   // Ensure SL satisfies broker minimum stop distance
   double minStopUSD = (MarketInfo(Symbol(), MODE_STOPLEVEL) * Point) + (10 * Point);
   if (slDistUSD < minStopUSD) slDistUSD = minStopUSD;
   if (slDistUSD < 2.50) slDistUSD = 2.50; // Minimum $2.50 buffer on Gold

   double tp1DistUSD = slDistUSD * InpRewardRatioTP1;

   // Diagnostic bar log
   if (InpVerboseLogging)
   {
      Print("[SWING SCAN] Bar: ", TimeToStr(currentBarTime, TIME_DATE|TIME_MINUTES),
            " | Close: $", DoubleToStr(close1, 2),
            " | EMA200: $", DoubleToStr(ema200, 2),
            " | Trend: ", (trendBullish ? "BULLISH" : (trendBearish ? "BEARISH" : "NEUTRAL")),
            " | RSI: ", DoubleToStr(rsi_1, 1));
   }

   RefreshRates();
   double lot = GetCompoundedSwingLot();

   // --- BUY SETUP ---
   // 1. Bullish Trend (Price > EMA200)
   // 2. Recent pullback: Low penetrated into or below EMA20/EMA50 zone in last 3 bars
   // 3. Rejection / Bullish turn: Close[1] closed above EMA20 and Close[1] > Open[1]
   // 4. RSI recovering upward (rsi_1 > rsi_2 and rsi_1 <= 60)
   bool touchedValueZoneBuy = (Low[1] <= ema20 || Low[2] <= ema20 || Low[3] <= ema20);

   if (trendBullish && touchedValueZoneBuy && close1 >= ema20 && close1 > open1 && rsi_1 > rsi_2 && rsi_1 <= 62.0)
   {
      double price = Ask;
      double sl    = NormalizeDouble(price - slDistUSD, Digits);
      double tp    = NormalizeDouble(price + tp1DistUSD, Digits);

      int ticket = OrderSend(Symbol(), OP_BUY, lot, price, InpSlippage, sl, tp, "Swing Buy Setup", InpMagicNumber, 0, clrDodgerBlue);
      if (ticket > 0)
      {
         Print("[SWING BUY SUCCESS] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
               " | SL: ", sl, " (Risk: $", DoubleToStr(slDistUSD, 2), ") | TP1: ", tp, " (Reward: $", DoubleToStr(tp1DistUSD, 2), ")");
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
   // 1. Bearish Trend (Price < EMA200)
   // 2. Recent pullback: High penetrated into or above EMA20/EMA50 zone in last 3 bars
   // 3. Rejection / Bearish turn: Close[1] closed below EMA20 and Close[1] < Open[1]
   // 4. RSI turning downward (rsi_1 < rsi_2 and rsi_1 >= 38.0)
   bool touchedValueZoneSell = (High[1] >= ema20 || High[2] >= ema20 || High[3] >= ema20);

   if (trendBearish && touchedValueZoneSell && close1 <= ema20 && close1 < open1 && rsi_1 < rsi_2 && rsi_1 >= 38.0)
   {
      double price = Bid;
      double sl    = NormalizeDouble(price + slDistUSD, Digits);
      double tp    = NormalizeDouble(price - tp1DistUSD, Digits);

      int ticket = OrderSend(Symbol(), OP_SELL, lot, price, InpSlippage, sl, tp, "Swing Sell Setup", InpMagicNumber, 0, clrCrimson);
      if (ticket > 0)
      {
         Print("[SWING SELL SUCCESS] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
               " | SL: ", sl, " (Risk: $", DoubleToStr(slDistUSD, 2), ") | TP1: ", tp, " (Reward: $", DoubleToStr(tp1DistUSD, 2), ")");
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
                     // If lot cannot be split (e.g. 0.01 lot), move SL to Break-Even directly
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
//| On-Chart Heads-Up Dashboard Display                              |
//+------------------------------------------------------------------+
void UpdateHUD()
{
   double bal = AccountBalance();
   double eq  = AccountEquity();
   double pnl = eq - g_InitialBalance;
   double pct = (g_InitialBalance > 0) ? (pnl / g_InitialBalance) * 100.0 : 0.0;
   double lot = GetCompoundedSwingLot();

   double ema200 = iMA(Symbol(), 0, InpTrendEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   string trend = (Close[1] > ema200) ? "BULLISH (BUY ONLY)" : "BEARISH (SELL ONLY)";

   string hud = "";
   hud += "====================================================\n";
   hud += "  XAUUSD SWING MASTER EA v1.10                      \n";
   hud += "====================================================\n";
   hud += StringConcatenate("  Current Balance   : $", DoubleToStr(bal, 2), " (Initial: $", DoubleToStr(g_InitialBalance, 2), ")\n");
   hud += StringConcatenate("  Current Equity    : $", DoubleToStr(eq, 2), " | Total PnL: $", DoubleToStr(pnl, 2), " (", DoubleToStr(pct, 1), "%)\n");
   hud += StringConcatenate("  Compounded Lot    : ", DoubleToStr(lot, 2), " lot (Leverage 1:500)\n");
   hud += "----------------------------------------------------\n";
   hud += StringConcatenate("  Trend Bias        : ", trend, "\n");
   hud += StringConcatenate("  Active Trades     : ", CountOpenSwingTrades(), " trade(s)\n");
   hud += StringConcatenate("  Partial TP1 Status: ", (g_PartialClosed ? "TP1 BANKED (RUNNER TRAILING)" : "AWAITING TP1"), "\n");
   hud += StringConcatenate("  Friday Guard      : ", (g_FridayClosedForLowVol ? "TRIGGERED (CLOSED FOR WEEKEND)" : "MONITORING"), "\n");
   hud += StringConcatenate("  Current Gold Bid  : $", DoubleToStr(Bid, 2), " | Spread: $", DoubleToStr(Ask - Bid, 2), "\n");
   hud += "====================================================\n";

   Comment(hud);
}
