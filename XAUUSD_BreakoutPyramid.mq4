//+------------------------------------------------------------------+
//|                                     XAUUSD_BreakoutPyramid.mq4   |
//|               London Volatility Breakout & Pyramiding Engine     |
//|                    Engineered for $100 -> $500 Account Growth    |
//+------------------------------------------------------------------+
#property copyright "Quantitative Trading Engine"
#property link      "https://github.com"
#property version   "2.00"
#property strict

//--- Inputs: Compounding & Account Scaling Tiers
input string   _Section1               = "=== Account Scaling & Risk ===";
input bool     InpUseDynamicTiers      = true;     // Enable Dynamic Compounding Tiers
input double   InpManualBaseLot        = 0.02;     // Manual Lot if Dynamic Tiers disabled
input double   InpMaxLossPerTrade      = 5.00;     // Max Risk per trade in USD (e.g. $5.00)
input double   InpMaxDailyLossUSD      = 12.00;    // Max Daily Loss Circuit Breaker in USD
input double   InpMaxTargetDailyUSD    = 50.00;    // Daily Target USD (auto-scaled by tier)

//--- Inputs: Asian Range & Session Windows
input string   _Section2               = "=== Asian Range & Session Clock ===";
input int      InpBrokerUtcOffset      = 2;        // Broker Server UTC/GMT Offset (e.g. +2 or +3)
input int      InpAsianStartHourUTC    = 0;        // Asian Range Start Hour (UTC)
input int      InpAsianEndHourUTC      = 6;        // Asian Range End Hour (UTC)
input int      InpAsianEndMinUTC       = 30;       // Asian Range End Minute (UTC)
input int      InpTradeStartHourUTC    = 7;        // London Trade Start (07:00 UTC)
input int      InpTradeEndHourUTC      = 16;       // Trade Window End (16:30 UTC)
input double   InpMinAsianRangeUSD     = 3.00;     // Min Asian Range in Gold Dollars (e.g. $3.00)
input double   InpMaxAsianRangeUSD     = 15.00;    // Max Asian Range in Gold Dollars (e.g. $15.00)
input double   InpBreakoutBufferUSD    = 0.50;     // Breakout entry buffer above/below range ($0.50)

//--- Inputs: Zero-Risk Pyramiding & Trailing
input string   _Section3               = "=== Break-Even & Pyramiding ===";
input bool     InpEnablePyramiding     = true;     // Add Runner position when in profit
input double   InpBreakEvenTriggerUSD  = 2.00;     // Gold profit move to trigger Break-Even ($2.00)
input double   InpBreakEvenBufferUSD   = 0.30;     // Profit locked at Break-Even ($0.30)
input double   InpPyramidTriggerUSD    = 2.50;     // Gold move to trigger Runner entry ($2.50)
input double   InpTargetRunnerUSD      = 15.00;    // Take Profit target for runner in Gold $ ($15.00)
input bool     InpUseATRTrailing       = true;     // Trail Stop Loss using ATR
input int      InpATRPeriod            = 14;       // ATR Period for Trailing Stop
input double   InpATRFactor            = 2.2;      // ATR Multiplier for Trailing Stop

//--- Inputs: Execution & Filters
input string   _Section4               = "=== Execution & Filters ===";
input double   InpMaxSpreadUSD         = 0.35;     // Max Allowable Spread in Gold $ ($0.35 = 35 pips)
input int      InpMagicBase            = 888100;   // Magic Number for Base Breakout Trade
input int      InpMagicRunner          = 888200;   // Magic Number for Runner Pyramided Trade
input int      InpSlippage             = 30;       // Max Slippage in Points

//--- Global Variables
double g_AsianHigh           = 0.0;
double g_AsianLow            = 0.0;
bool   g_AsianBoxFormed      = false;
int    g_LastTradingDay      = -1;
double g_DayStartingBalance  = 0.0;
bool   g_DailyLossTripped    = false;
bool   g_BaseTradeTriggered  = false;
bool   g_RunnerTriggered     = false;
double g_ContractSize        = 100.0;
double g_PointValue          = 0.01;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   string sym = Symbol();
   if (StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
   {
      Print("[WARNING] Symbol is ", sym, ". This EA is built specifically for XAUUSD / GOLD.");
   }

   g_ContractSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   if (g_ContractSize <= 0) g_ContractSize = 100.0;

   g_PointValue = Point;
   g_DayStartingBalance = AccountBalance();
   g_LastTradingDay = Day();

   Print("[INIT] XAUUSD Breakout Pyramid Engine Initialized.");
   Print("[INIT] Current Balance: $", DoubleToStr(g_DayStartingBalance, 2),
         " | Contract Size: ", DoubleToStr(g_ContractSize, 0));

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
   // 1. Reset daily trackers at new trading day
   CheckNewDay();

   // 2. Daily Loss Circuit Breaker Check
   double dailyPnL = AccountEquity() - g_DayStartingBalance;
   if (dailyPnL <= -InpMaxDailyLossUSD)
   {
      if (!g_DailyLossTripped)
      {
         Print("[CIRCUIT BREAKER] Daily loss reached -$", DoubleToStr(MathAbs(dailyPnL), 2),
               ". Closing all positions and halting for today.");
         CloseAllEAPositions();
         g_DailyLossTripped = true;
      }
      UpdateHUD("DAILY LOSS LIMIT REACHED - HALTED");
      return;
   }

   // 3. Scan & Calculate Asian Range Box (00:00 - 06:30 UTC)
   CalculateAsianRange();

   // 4. Manage active open positions (Break-Even, Pyramiding, Trailing Stop)
   ManageActiveTrades();

   // 5. Update Chart Display HUD
   string status = g_DailyLossTripped ? "HALTED FOR TODAY" : (IsTradingWindow() ? "Hunting Breakout" : "Outside Trading Session");
   UpdateHUD(status);

   // 6. Check if we can enter a new breakout setup
   if (g_DailyLossTripped) return;
   if (!IsTradingWindow()) return;
   if (g_BaseTradeTriggered) return; // Only 1 primary breakout setup per session
   if (!g_AsianBoxFormed) return;
   if (!IsSpreadOk()) return;

   // 7. Check for Breakout of the Asian Range Box
   CheckBreakoutTrigger();
}

//+------------------------------------------------------------------+
//| Check if new trading day has started                             |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   int currentDay = Day();
   if (currentDay != g_LastTradingDay)
   {
      g_LastTradingDay = currentDay;
      g_DayStartingBalance = AccountBalance();
      g_DailyLossTripped = false;
      g_AsianBoxFormed = false;
      g_AsianHigh = 0.0;
      g_AsianLow = 0.0;
      g_BaseTradeTriggered = false;
      g_RunnerTriggered = false;
      Print("[NEW DAY] Session reset. Starting Balance: $", DoubleToStr(g_DayStartingBalance, 2));
   }
}

//+------------------------------------------------------------------+
//| Calculate Asian Session High and Low (00:00 to 06:30 UTC)        |
//+------------------------------------------------------------------+
void CalculateAsianRange()
{
   int utcHour = GetCurrentUtcHour();
   int utcMin  = TimeMinute(TimeCurrent());

   // If already inside or past trading window and box is calculated, keep it
   if (g_AsianBoxFormed && (utcHour >= InpTradeStartHourUTC)) return;

   // Scanning while within Asian session or right at the end
   if (utcHour < InpTradeStartHourUTC)
   {
      double highest = -1.0;
      double lowest  = 999999.0;

      int totalBars = iBars(Symbol(), PERIOD_M15);
      datetime today00UTC = GetTodayUtcMidnight();

      for (int i = 0; i < totalBars && i < 150; i++)
      {
         datetime barTime = iTime(Symbol(), PERIOD_M15, i);
         if (barTime >= today00UTC)
         {
            int barUtcHour = GetUtcHourFromTime(barTime);
            int barUtcMin  = TimeMinute(barTime);

            if ((barUtcHour > InpAsianStartHourUTC || (barUtcHour == InpAsianStartHourUTC)) &&
                (barUtcHour < InpAsianEndHourUTC || (barUtcHour == InpAsianEndHourUTC && barUtcMin <= InpAsianEndMinUTC)))
            {
               double h = iHigh(Symbol(), PERIOD_M15, i);
               double l = iLow(Symbol(), PERIOD_M15, i);
               if (h > highest) highest = h;
               if (l < lowest)  lowest  = l;
            }
         }
      }

      if (highest > 0 && lowest < 999999.0)
      {
         g_AsianHigh = highest;
         g_AsianLow  = lowest;
         double rangeUSD = g_AsianHigh - g_AsianLow;

         if (rangeUSD >= InpMinAsianRangeUSD && rangeUSD <= InpMaxAsianRangeUSD)
         {
            g_AsianBoxFormed = true;
         }
         else
         {
            g_AsianBoxFormed = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if current time is within active London/NY trading window  |
//+------------------------------------------------------------------+
bool IsTradingWindow()
{
   int utcHour = GetCurrentUtcHour();
   return (utcHour >= InpTradeStartHourUTC && utcHour < InpTradeEndHourUTC);
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Dynamic Account Scaling Tiers        |
//+------------------------------------------------------------------+
double GetTieredLotSize()
{
   if (!InpUseDynamicTiers) return InpManualBaseLot;

   double bal = AccountBalance();

   // Account Growth Compounding Tiers:
   // $100 - $149 : 0.02 lot
   // $150 - $249 : 0.04 lot
   // $250 - $379 : 0.07 lot
   // $380+       : 0.10 lot
   double lot = 0.02;
   if (bal >= 380.0)      lot = 0.10;
   else if (bal >= 250.0) lot = 0.07;
   else if (bal >= 150.0) lot = 0.04;
   else                   lot = 0.02;

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;
   return (MathFloor(lot / lotStep) * lotStep);
}

//+------------------------------------------------------------------+
//| Check Breakout Trigger and execute primary position              |
//+------------------------------------------------------------------+
void CheckBreakoutTrigger()
{
   if (!g_AsianBoxFormed) return;

   RefreshRates();
   double buyTriggerPrice  = g_AsianHigh + InpBreakoutBufferUSD;
   double sellTriggerPrice = g_AsianLow  - InpBreakoutBufferUSD;

   double lot = GetTieredLotSize();

   // Breakout Above Asian High
   if (Ask >= buyTriggerPrice && Ask < (buyTriggerPrice + 1.50))
   {
      double slDist = InpMaxLossPerTrade / (lot * g_ContractSize);
      double sl = NormalizeDouble(Ask - slDist, Digits);
      double tp = NormalizeDouble(Ask + (InpBreakoutBufferUSD * 2) + 10.0, Digits);

      int ticket = OrderSend(Symbol(), OP_BUY, lot, Ask, InpSlippage, sl, tp, "LVPR Base Buy", InpMagicBase, 0, clrDodgerBlue);
      if (ticket > 0)
      {
         Print("[BREAKOUT BUY] Order #", ticket, " opened @ ", Ask, " (Asian High was ", g_AsianHigh, ")");
         g_BaseTradeTriggered = true;
      }
   }
   // Breakout Below Asian Low
   else if (Bid <= sellTriggerPrice && Bid > (sellTriggerPrice - 1.50))
   {
      double slDist = InpMaxLossPerTrade / (lot * g_ContractSize);
      double sl = NormalizeDouble(Bid + slDist, Digits);
      double tp = NormalizeDouble(Bid - (InpBreakoutBufferUSD * 2) - 10.0, Digits);

      int ticket = OrderSend(Symbol(), OP_SELL, lot, Bid, InpSlippage, sl, tp, "LVPR Base Sell", InpMagicBase, 0, clrCrimson);
      if (ticket > 0)
      {
         Print("[BREAKOUT SELL] Order #", ticket, " opened @ ", Bid, " (Asian Low was ", g_AsianLow, ")");
         g_BaseTradeTriggered = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Active Positions: Break-Even, Pyramiding Runner, Trailing |
//+------------------------------------------------------------------+
void ManageActiveTrades()
{
   double atr = iATR(Symbol(), PERIOD_M15, InpATRPeriod, 1);
   if (atr <= 0) atr = 1.50; // default $1.50 if unavailable

   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol())
         {
            int magic = OrderMagicNumber();
            if (magic != InpMagicBase && magic != InpMagicRunner) continue;

            double openPrice = OrderOpenPrice();
            double curPrice  = (OrderType() == OP_BUY) ? Bid : Ask;
            double stopLoss  = OrderStopLoss();
            double priceDiff = (OrderType() == OP_BUY) ? (curPrice - openPrice) : (openPrice - curPrice);

            // 1. Move Base Trade to Break-Even when profit >= InpBreakEvenTriggerUSD ($2.00)
            if (magic == InpMagicBase)
            {
               if (OrderType() == OP_BUY)
               {
                  if (priceDiff >= InpBreakEvenTriggerUSD)
                  {
                     double beSL = NormalizeDouble(openPrice + InpBreakEvenBufferUSD, Digits);
                     if (stopLoss < beSL)
                     {
                        OrderModify(OrderTicket(), openPrice, beSL, OrderTakeProfit(), 0, clrGreen);
                        Print("[BREAK-EVEN LOCKED] Base BUY #", OrderTicket(), " SL moved to ", beSL);
                     }

                     // Trigger Pyramiding: Add Runner if enabled and not yet opened
                     if (InpEnablePyramiding && !g_RunnerTriggered && priceDiff >= InpPyramidTriggerUSD)
                     {
                        AddPyramidRunner(OP_BUY, openPrice + InpBreakEvenBufferUSD);
                     }
                  }
               }
               else if (OrderType() == OP_SELL)
               {
                  if (priceDiff >= InpBreakEvenTriggerUSD)
                  {
                     double beSL = NormalizeDouble(openPrice - InpBreakEvenBufferUSD, Digits);
                     if (stopLoss > beSL || stopLoss == 0)
                     {
                        OrderModify(OrderTicket(), openPrice, beSL, OrderTakeProfit(), 0, clrRed);
                        Print("[BREAK-EVEN LOCKED] Base SELL #", OrderTicket(), " SL moved to ", beSL);
                     }

                     // Trigger Pyramiding: Add Runner if enabled and not yet opened
                     if (InpEnablePyramiding && !g_RunnerTriggered && priceDiff >= InpPyramidTriggerUSD)
                     {
                        AddPyramidRunner(OP_SELL, openPrice - InpBreakEvenBufferUSD);
                     }
                  }
               }
            }

            // 2. Trailing Stop for both Base and Runner positions using ATR
            if (InpUseATRTrailing && priceDiff >= InpBreakEvenTriggerUSD)
            {
               double trailDist = atr * InpATRFactor;

               if (OrderType() == OP_BUY)
               {
                  double trailSL = NormalizeDouble(Bid - trailDist, Digits);
                  if (trailSL > stopLoss && trailSL > openPrice)
                  {
                     OrderModify(OrderTicket(), openPrice, trailSL, OrderTakeProfit(), 0, clrAqua);
                  }
               }
               else if (OrderType() == OP_SELL)
               {
                  double trailSL = NormalizeDouble(Ask + trailDist, Digits);
                  if ((trailSL < stopLoss || stopLoss == 0) && trailSL < openPrice)
                  {
                     OrderModify(OrderTicket(), openPrice, trailSL, OrderTakeProfit(), 0, clrMagenta);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add Pyramiding Runner Position (Financed by Locked Profit)       |
//+------------------------------------------------------------------+
void AddPyramidRunner(int orderType, double protectedSL)
{
   double lot = GetTieredLotSize();
   RefreshRates();

   double price = (orderType == OP_BUY) ? Ask : Bid;
   double sl    = NormalizeDouble(protectedSL, Digits);
   double tp    = (orderType == OP_BUY) ? NormalizeDouble(price + InpTargetRunnerUSD, Digits) : NormalizeDouble(price - InpTargetRunnerUSD, Digits);
   color clr    = (orderType == OP_BUY) ? clrSteelBlue : clrDarkOrange;

   int ticket = OrderSend(Symbol(), orderType, lot, price, InpSlippage, sl, tp, "LVPR Runner Trade", InpMagicRunner, 0, clr);
   if (ticket > 0)
   {
      Print("[PYRAMID RUNNER OPENED] Order #", ticket, " ", (orderType == OP_BUY ? "BUY" : "SELL"),
            " ", lot, " lots @ ", price, " | SL locked to Base Entry Protection: ", sl);
      g_RunnerTriggered = true;
   }
}

//+------------------------------------------------------------------+
//| Spread Check in Gold Dollars                                     |
//+------------------------------------------------------------------+
bool IsSpreadOk()
{
   double spreadUSD = (Ask - Bid);
   return (spreadUSD <= InpMaxSpreadUSD);
}

//+------------------------------------------------------------------+
//| Close all orders belonging to this EA                            |
//+------------------------------------------------------------------+
void CloseAllEAPositions()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol())
         {
            int magic = OrderMagicNumber();
            if (magic == InpMagicBase || magic == InpMagicRunner)
            {
               double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
               OrderClose(OrderTicket(), OrderLots(), closePrice, InpSlippage, clrGray);
            }
         }
      }
   }
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

datetime GetTodayUtcMidnight()
{
   datetime now = TimeCurrent();
   int sHour = TimeHour(now);
   int sMin  = TimeMinute(now);
   int sSec  = TimeSeconds(now);
   return (now - (sHour * 3600 + sMin * 60 + sSec) + (InpBrokerUtcOffset * 3600));
}

//+------------------------------------------------------------------+
//| Heads-Up Dashboard Display                                       |
//+------------------------------------------------------------------+
void UpdateHUD(string status)
{
   double bal     = AccountBalance();
   double eq      = AccountEquity();
   double dayPnL  = eq - g_DayStartingBalance;
   double dayPct  = (g_DayStartingBalance > 0) ? (dayPnL / g_DayStartingBalance) * 100.0 : 0.0;
   double spread  = (Ask - Bid);
   double nextLot = GetTieredLotSize();

   string hud = "";
   hud += "====================================================\n";
   hud += "  XAUUSD LONDON VOLATILITY PYRAMID ENGINE (5X TARGET)\n";
   hud += "====================================================\n";
   hud += StringConcatenate("  Current Balance  : $", DoubleToStr(bal, 2), " (Start: $", DoubleToStr(g_DayStartingBalance, 2), ")\n");
   hud += StringConcatenate("  Current Equity   : $", DoubleToStr(eq, 2), " | Today's PnL: $", DoubleToStr(dayPnL, 2), " (", DoubleToStr(dayPct, 1), "%)\n");
   hud += StringConcatenate("  Next Trade Lot   : ", DoubleToStr(nextLot, 2), " lot (Compounded Tier)\n");
   hud += "----------------------------------------------------\n";
   hud += StringConcatenate("  Asian Range Box  : ", (g_AsianBoxFormed ? StringConcatenate("$", DoubleToStr(g_AsianLow, 2), " - $", DoubleToStr(g_AsianHigh, 2), " (Width: $", DoubleToStr(g_AsianHigh - g_AsianLow, 2), ")") : "Forming..."), "\n");
   hud += StringConcatenate("  Current Gold Bid : $", DoubleToStr(Bid, 2), " | Spread: $", DoubleToStr(spread, 2), "\n");
   hud += StringConcatenate("  Engine Status    : ", status, "\n");
   hud += StringConcatenate("  Base Order Open  : ", (g_BaseTradeTriggered ? "Active / In Play" : "Awaiting Breakout"), "\n");
   hud += StringConcatenate("  Runner Pyramided : ", (g_RunnerTriggered ? "RUNNER ACTIVE (Riding Trend)" : "Not Triggered"), "\n");
   hud += "====================================================\n";

   Comment(hud);
}
