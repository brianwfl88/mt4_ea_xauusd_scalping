//+------------------------------------------------------------------+
//|                                         XAUUSD_SwingMaster.mq4   |
//|               Institutional Trend & Volatility Swing Engine      |
//|                    Engineered for Gold (XAUUSD) Swing Trading    |
//|                    Version 2.00: Strict Capital Preservation     |
//+------------------------------------------------------------------+
#property copyright "Quantitative Trading Engine"
#property link      "https://github.com"
#property version   "2.00"
#property strict

//--- Inputs: Strict Capital Protection & Mathematical Risk Sizing
input string   _Section1               = "=== Strict Capital Preservation & Risk ===";
input double   InpRiskPercentPerTrade  = 4.0;      // Max Risk % per trade of current equity (3.0% - 5.0%)
input double   InpMaxDrawdownFromPeak  = 15.0;     // Max Drawdown % from Peak Equity before emergency halt
input bool     InpEnableProfitRatchet  = true;     // Ratchet Profit Floor (Locks in gains at $200, $300, etc.)
input double   InpRewardRatioTP1       = 2.0;      // Risk-to-Reward ratio for TP1 (1:2 R:R)
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
double g_ContractSize          = 100.0;
double g_InitialBalance        = 0.0;
double g_PeakEquity            = 0.0;
double g_ProfitFloor           = 0.0;
bool   g_PartialClosed         = false;
bool   g_CircuitBreakerTripped = false;
bool   g_FridayClosedForLowVol = false;
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

   g_InitialBalance        = AccountBalance();
   g_PeakEquity            = MathMax(g_InitialBalance, AccountEquity());
   g_ProfitFloor           = 0.0;
   g_PartialClosed         = false;
   g_CircuitBreakerTripped = false;
   g_FridayClosedForLowVol = false;
   g_LastBarTime           = 0;

   Print("==================================================================");
   Print("[INIT] XAUUSD Swing Master Engine v2.00 Initialized.");
   Print("[INIT] Capital Protection Active | Starting Balance: $", DoubleToStr(g_InitialBalance, 2),
         " | Leverage: 1:", AccountLeverage(),
         " | Contract Size: ", DoubleToStr(g_ContractSize, 0),
         " | Risk Per Trade: ", DoubleToStr(InpRiskPercentPerTrade, 1), "%");
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
   // 1. Maintain Peak Equity and Ratchet Profit Floors
   MaintainCapitalProtection();

   // 2. Check Circuit Breaker Status
   if (g_CircuitBreakerTripped)
   {
      UpdateHUD();
      return;
   }

   // 3. Friday Volatility & Weekend Risk Manager
   if (InpEnableFridayFilter)
   {
      CheckFridayWeekendRisk();
   }

   // 4. Manage Active Open Swing Positions (TP1 Partial Close, Break-Even, ATR Trail)
   ManageOpenSwingTrades();

   // 5. Update On-Chart HUD
   UpdateHUD();

   // 6. Entry Guard Checks
   if (g_CircuitBreakerTripped) return;
   if (g_FridayClosedForLowVol) return;
   if (CountOpenSwingTrades() > 0) return; // Strictly 1 swing setup at a time
   if (!IsSpreadOk()) return;

   // 7. Check Swing Entry Signal
   CheckAndExecuteSwingEntry();
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
      // When equity hits $200, floor = $150 (locks in +$50 minimum)
      // When equity hits $300, floor = $240 (locks in +$140 minimum)
      // When equity hits $400, floor = $330 (locks in +$230 minimum)
      if (InpEnableProfitRatchet)
      {
         if (g_PeakEquity >= 400.0)      g_ProfitFloor = MathMax(g_ProfitFloor, 330.0);
         else if (g_PeakEquity >= 300.0) g_ProfitFloor = MathMax(g_ProfitFloor, 240.0);
         else if (g_PeakEquity >= 200.0) g_ProfitFloor = MathMax(g_ProfitFloor, 150.0);
      }
   }

   // 1. Check Maximum Drawdown from Peak Equity (e.g. max 15% drawdown from all-time peak)
   double ddFromPeak = 0.0;
   if (g_PeakEquity > 0)
   {
      ddFromPeak = ((g_PeakEquity - curEquity) / g_PeakEquity) * 100.0;
   }

   if (ddFromPeak >= InpMaxDrawdownFromPeak)
   {
      if (!g_CircuitBreakerTripped)
      {
         Print("[CIRCUIT BREAKER ACTIVATED] Equity fell ", DoubleToStr(ddFromPeak, 1),
               "% from peak of $", DoubleToStr(g_PeakEquity, 2),
               ". Current Equity: $", DoubleToStr(curEquity, 2),
               ". Closing all positions to lock in capital!");
         CloseAllSwingPositions();
         g_CircuitBreakerTripped = true;
      }
      return;
   }

   // 2. Check Profit Floor Ratchet Breach
   if (InpEnableProfitRatchet && g_ProfitFloor > 0 && curEquity <= g_ProfitFloor)
   {
      if (!g_CircuitBreakerTripped)
      {
         Print("[PROFIT FLOOR RATCHET TRIGGERED] Equity ($", DoubleToStr(curEquity, 2),
               ") reached locked floor of $", DoubleToStr(g_ProfitFloor, 2),
               ". Closing positions to preserve banked profits!");
         CloseAllSwingPositions();
         g_CircuitBreakerTripped = true;
      }
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
//| DYNAMIC RISK SIZING: Lot size mathematically tied to Stop Loss    |
//| GUARANTEES that a losing trade NEVER exceeds InpRiskPercent      |
//+------------------------------------------------------------------+
double CalculateDynamicRiskLot(double slDistanceUSD)
{
   double equity = AccountEquity();
   if (equity <= 0) equity = AccountBalance();

   // Maximum dollars permitted to risk on this trade
   double maxRiskDollars = equity * (InpRiskPercentPerTrade / 100.0);

   // Loss on 1.0 standard lot for slDistanceUSD price move:
   // Example: $10.00 Gold move on 1 lot (100 oz) = $1,000 loss
   double lossPerStandardLot = slDistanceUSD * g_ContractSize;

   double lot = 0.01;
   if (lossPerStandardLot > 0)
   {
      lot = maxRiskDollars / lossPerStandardLot;
   }

   // Broker compliance
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   lot = MathFloor(lot / lotStep) * lotStep;
   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;

   // Margin check at current leverage
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

   // Ensure SL satisfies broker minimum stop distance
   double minStopUSD = (MarketInfo(Symbol(), MODE_STOPLEVEL) * Point) + (10 * Point);
   if (slDistUSD < minStopUSD) slDistUSD = minStopUSD;
   if (slDistUSD < 2.50) slDistUSD = 2.50; // Minimum $2.50 buffer on Gold

   double tp1DistUSD = slDistUSD * InpRewardRatioTP1;

   // Calculate strictly risk-controlled lot size
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

      int ticket = OrderSend(Symbol(), OP_BUY, lot, price, InpSlippage, sl, tp, "Swing Buy Setup", InpMagicNumber, 0, clrDodgerBlue);
      if (ticket > 0)
      {
         Print("[SWING BUY EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
               " | Max Dollar Risk: $", DoubleToStr(actualRiskUSD, 2), " (", DoubleToStr(InpRiskPercentPerTrade, 1), "% of equity)",
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

      int ticket = OrderSend(Symbol(), OP_SELL, lot, price, InpSlippage, sl, tp, "Swing Sell Setup", InpMagicNumber, 0, clrCrimson);
      if (ticket > 0)
      {
         Print("[SWING SELL EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
               " | Max Dollar Risk: $", DoubleToStr(actualRiskUSD, 2), " (", DoubleToStr(InpRiskPercentPerTrade, 1), "% of equity)",
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
   double ddFromPeak = (g_PeakEquity > 0) ? ((g_PeakEquity - eq) / g_PeakEquity) * 100.0 : 0.0;

   double ema200 = iMA(Symbol(), 0, InpTrendEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   string trend = (Close[1] > ema200) ? "BULLISH (BUY ONLY)" : "BEARISH (SELL ONLY)";

   string hud = "";
   hud += "====================================================\n";
   hud += "  XAUUSD SWING MASTER EA v2.00 (CAPITAL GUARD)      \n";
   hud += "====================================================\n";
   hud += StringConcatenate("  Current Balance   : $", DoubleToStr(bal, 2), " (Initial: $", DoubleToStr(g_InitialBalance, 2), ")\n");
   hud += StringConcatenate("  Current Equity    : $", DoubleToStr(eq, 2), " | Total PnL: $", DoubleToStr(pnl, 2), " (", DoubleToStr(pct, 1), "%)\n");
   hud += StringConcatenate("  Peak Equity       : $", DoubleToStr(g_PeakEquity, 2), " | DD from Peak: ", DoubleToStr(ddFromPeak, 1), "% (Max: ", DoubleToStr(InpMaxDrawdownFromPeak, 1), "%)\n");
   hud += StringConcatenate("  Profit Floor      : $", DoubleToStr(g_ProfitFloor, 2), (g_ProfitFloor > 0 ? " [LOCKED CAPITAL]" : " [Not Set Yet]"), "\n");
   hud += "----------------------------------------------------\n";
   hud += StringConcatenate("  Risk Per Trade    : ", DoubleToStr(InpRiskPercentPerTrade, 1), "% of equity (Dynamic Formula)\n");
   hud += StringConcatenate("  Circuit Breaker   : ", (g_CircuitBreakerTripped ? "HALTED - GAINS PROTECTED" : "ACTIVE & MONITORING"), "\n");
   hud += StringConcatenate("  Trend Bias        : ", trend, "\n");
   hud += StringConcatenate("  Active Trades     : ", CountOpenSwingTrades(), " trade(s)\n");
   hud += StringConcatenate("  Partial TP1 Status: ", (g_PartialClosed ? "TP1 BANKED (RUNNER TRAILING)" : "AWAITING TP1"), "\n");
   hud += StringConcatenate("  Current Gold Bid  : $", DoubleToStr(Bid, 2), " | Spread: $", DoubleToStr(Ask - Bid, 2), "\n");
   hud += "====================================================\n";

   Comment(hud);
}
