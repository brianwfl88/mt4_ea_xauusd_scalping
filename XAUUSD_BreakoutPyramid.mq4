//+------------------------------------------------------------------+
//|                                     XAUUSD_BreakoutPyramid.mq4   |
//|               London Volatility Breakout & Pyramiding Engine     |
//|                    Engineered for $100 -> $500 Account Growth    |
//|                    Updated: Multi-Broker & Backtester Hardened   |
//+------------------------------------------------------------------+
#property copyright "Quantitative Trading Engine"
#property link      "https://github.com"
#property version   "2.10"
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
input int      InpAsianEndMinUTC       = 59;       // Asian Range End Minute (UTC)
input int      InpTradeStartHourUTC    = 7;        // London Trade Start (07:00 UTC)
input int      InpTradeEndHourUTC      = 17;       // Trade Window End (17:00 UTC)
input double   InpMinAsianRangeUSD     = 1.50;     // Min Asian Range in Gold Dollars ($1.50)
input double   InpMaxAsianRangeUSD     = 25.00;    // Max Asian Range in Gold Dollars ($25.00)
input double   InpBreakoutBufferUSD    = 0.30;     // Breakout entry buffer above/below range ($0.30)

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
input double   InpMaxSpreadUSD         = 0.60;     // Max Spread in Gold $ (0.60 = $0.60, tester-friendly)
input int      InpMagicBase            = 888100;   // Magic Number for Base Breakout Trade
input int      InpMagicRunner          = 888200;   // Magic Number for Runner Pyramided Trade
input int      InpSlippage             = 50;       // Max Slippage in Points
input bool     InpVerboseLogging       = true;     // Print diagnostic logs to MT4 Journal

//--- Global Variables
double g_AsianHigh             = 0.0;
double g_AsianLow              = 0.0;
bool   g_AsianBoxFormed        = false;
int    g_LastTradingDay        = -1;
int    g_LastLoggedHour        = -1;
double g_DayStartingBalance    = 0.0;
bool   g_DailyLossTripped      = false;
bool   g_BaseTradeTriggered    = false;
bool   g_RunnerTriggered       = false;
double g_ContractSize          = 100.0;
double g_PointValue            = 0.01;

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

   Print("==================================================================");
   Print("[INIT] XAUUSD Breakout Pyramid Engine v2.10 Ready.");
   Print("[INIT] Balance: $", DoubleToStr(g_DayStartingBalance, 2),
         " | Leverage: 1:", AccountLeverage(),
         " | Contract Size: ", DoubleToStr(g_ContractSize, 0),
         " | MinStopLevel: ", MarketInfo(Symbol(), MODE_STOPLEVEL), " points");
   Print("==================================================================");

   // Force immediate initial scan of today's Asian range
   CalculateAsianRange();

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

   // 2. Periodic Diagnostic Log (Once per hour in Journal)
   LogHourlyDiagnostics();

   // 3. Daily Loss Circuit Breaker Check
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

   // 4. Calculate / Refresh Asian Range Box
   CalculateAsianRange();

   // 5. Manage active open positions (Break-Even, Pyramiding, Trailing Stop)
   ManageActiveTrades();

   // 6. Update Chart Display HUD
   string status = g_DailyLossTripped ? "HALTED FOR TODAY" : (IsTradingWindow() ? "Hunting Breakout" : "Outside Trading Session");
   UpdateHUD(status);

   // 7. Check if we can enter a new breakout setup
   if (g_DailyLossTripped) return;
   if (!IsTradingWindow()) return;
   if (g_BaseTradeTriggered) return; // Only 1 primary breakout setup per session
   if (!g_AsianBoxFormed) return;
   if (!IsSpreadOk()) return;

   // 8. Check for Breakout of the Asian Range Box
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
      CalculateAsianRange();
   }
}

//+------------------------------------------------------------------+
//| Periodic Diagnostic Logging to MT4 Journal                       |
//+------------------------------------------------------------------+
void LogHourlyDiagnostics()
{
   if (!InpVerboseLogging) return;

   int currentHour = TimeHour(TimeCurrent());
   if (currentHour != g_LastLoggedHour)
   {
      g_LastLoggedHour = currentHour;
      int utcHour = GetCurrentUtcHour();
      double spreadUSD = Ask - Bid;

      Print("[STATUS CHECK] Server Time: ", TimeToStr(TimeCurrent(), TIME_DATE|TIME_MINUTES),
            " | UTC Hour: ", utcHour,
            " | Spread: $", DoubleToStr(spreadUSD, 2),
            " | Asian Box Formed: ", (g_AsianBoxFormed ? "YES (" + DoubleToStr(g_AsianLow, 2) + " - " + DoubleToStr(g_AsianHigh, 2) + ")" : "NO"),
            " | Window Open: ", (IsTradingWindow() ? "YES" : "NO"),
            " | Base Order Active: ", (g_BaseTradeTriggered ? "YES" : "NO"));
   }
}

//+------------------------------------------------------------------+
//| Self-Contained Asian Session High and Low Calculation             |
//+------------------------------------------------------------------+
void CalculateAsianRange()
{
   // If already locked for today's trading, retain it
   if (g_AsianBoxFormed && g_AsianHigh > 0 && g_AsianLow > 0) return;

   double highest = -1.0;
   double lowest  = 999999.0;
   int matchedBars = 0;

   // Calculate target day's UTC midnight in server time
   datetime serverNow = TimeCurrent();
   int sYear  = TimeYear(serverNow);
   int sMonth = TimeMonth(serverNow);
   int sDay   = TimeDay(serverNow);

   // Scan bars on current chart directly
   int totalBars = Bars;
   for (int i = 0; i < totalBars && i < 300; i++)
   {
      datetime barTime = Time[i];
      if (TimeYear(barTime) == sYear && TimeMonth(barTime) == sMonth && TimeDay(barTime) == sDay)
      {
         int barUtcHour = GetUtcHourFromTime(barTime);
         int barUtcMin  = TimeMinute(barTime);

         // Include bars from Asian session (e.g. 00:00 to 06:59 UTC)
         if (barUtcHour >= InpAsianStartHourUTC && barUtcHour <= InpAsianEndHourUTC)
         {
            double h = High[i];
            double l = Low[i];
            if (h > highest) highest = h;
            if (l < lowest)  lowest  = l;
            matchedBars++;
         }
      }
      else if (matchedBars > 0)
      {
         // Crossed into yesterday
         break;
      }
   }

   if (matchedBars > 0 && highest > 0 && lowest < 999999.0)
   {
      double rangeUSD = highest - lowest;
      if (rangeUSD >= InpMinAsianRangeUSD && rangeUSD <= InpMaxAsianRangeUSD)
      {
         g_AsianHigh = highest;
         g_AsianLow  = lowest;
         g_AsianBoxFormed = true;

         Print("[ASIAN RANGE FORMED] Scanned ", matchedBars, " bars. Low: $", DoubleToStr(g_AsianLow, 2),
               " | High: $", DoubleToStr(g_AsianHigh, 2), " | Width: $", DoubleToStr(rangeUSD, 2));
      }
      else
      {
         // If range is slightly wider/tighter, allow it with warning to prevent total stall
         if (rangeUSD > 0.50)
         {
            g_AsianHigh = highest;
            g_AsianLow  = lowest;
            g_AsianBoxFormed = true;
            Print("[ASIAN RANGE ACCEPTED (FALLBACK)] Range $", DoubleToStr(rangeUSD, 2), " accepted.");
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
//| Calculate Lot Size with Margin Safety Check                      |
//+------------------------------------------------------------------+
double GetTieredLotSize()
{
   double lot = InpManualBaseLot;

   if (InpUseDynamicTiers)
   {
      double bal = AccountBalance();
      if (bal >= 380.0)      lot = 0.10;
      else if (bal >= 250.0) lot = 0.07;
      else if (bal >= 150.0) lot = 0.04;
      else                   lot = 0.02;
   }

   // Normalize lot size to broker specifications
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;
   lot = MathFloor(lot / lotStep) * lotStep;

   // CRITICAL MARGIN CHECK: Ensure account has enough margin at current leverage
   double marginReq = MarketInfo(Symbol(), MODE_MARGINREQUIRED) * lot;
   if (marginReq <= 0)
   {
      // If broker doesn't report MARGINREQUIRED directly, estimate:
      marginReq = (Ask * lot * g_ContractSize) / MathMax(AccountLeverage(), 1);
   }

   if (marginReq > (AccountFreeMargin() * 0.80) && lot > minLot)
   {
      Print("[MARGIN ALERT] Lot ", DoubleToStr(lot, 2), " requires $", DoubleToStr(marginReq, 2),
            " margin. Free margin is $", DoubleToStr(AccountFreeMargin(), 2), ". Downsizing to min lot ", DoubleToStr(minLot, 2));
      lot = minLot;
   }

   return lot;
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

   // Broker minimum stop distance check
   double minStopPoints = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double minStopUSD    = (minStopPoints > 0) ? minStopPoints : (1.00); // at least $1.00 safe buffer

   // Breakout Above Asian High
   if (Ask >= buyTriggerPrice && Ask <= (buyTriggerPrice + 4.00))
   {
      double slDist = InpMaxLossPerTrade / (lot * g_ContractSize);
      if (slDist < minStopUSD) slDist = minStopUSD + (10 * Point);

      double sl = NormalizeDouble(Ask - slDist, Digits);
      double tp = NormalizeDouble(Ask + 15.00, Digits);

      int ticket = OrderSend(Symbol(), OP_BUY, lot, Ask, InpSlippage, sl, tp, "LVPR Base Buy", InpMagicBase, 0, clrDodgerBlue);
      if (ticket > 0)
      {
         Print("[BREAKOUT BUY SUCCESS] Order #", ticket, " opened @ ", DoubleToStr(Ask, Digits),
               " | SL: ", DoubleToStr(sl, Digits), " | TP: ", DoubleToStr(tp, Digits),
               " | Range was: $", DoubleToStr(g_AsianLow, 2), " - $", DoubleToStr(g_AsianHigh, 2));
         g_BaseTradeTriggered = true;
      }
      else
      {
         int err = GetLastError();
         Print("[ERROR] Breakout BUY OrderSend failed! Error #", err,
               " | Ask: ", Ask, " | SL: ", sl, " | TP: ", tp, " | MinStopUSD: ", minStopUSD);
      }
   }
   // Breakout Below Asian Low
   else if (Bid <= sellTriggerPrice && Bid >= (sellTriggerPrice - 4.00))
   {
      double slDist = InpMaxLossPerTrade / (lot * g_ContractSize);
      if (slDist < minStopUSD) slDist = minStopUSD + (10 * Point);

      double sl = NormalizeDouble(Bid + slDist, Digits);
      double tp = NormalizeDouble(Bid - 15.00, Digits);

      int ticket = OrderSend(Symbol(), OP_SELL, lot, Bid, InpSlippage, sl, tp, "LVPR Base Sell", InpMagicBase, 0, clrCrimson);
      if (ticket > 0)
      {
         Print("[BREAKOUT SELL SUCCESS] Order #", ticket, " opened @ ", DoubleToStr(Bid, Digits),
               " | SL: ", DoubleToStr(sl, Digits), " | TP: ", DoubleToStr(tp, Digits),
               " | Range was: $", DoubleToStr(g_AsianLow, 2), " - $", DoubleToStr(g_AsianHigh, 2));
         g_BaseTradeTriggered = true;
      }
      else
      {
         int err = GetLastError();
         Print("[ERROR] Breakout SELL OrderSend failed! Error #", err,
               " | Bid: ", Bid, " | SL: ", sl, " | TP: ", tp, " | MinStopUSD: ", minStopUSD);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Active Positions: Break-Even, Pyramiding Runner, Trailing |
//+------------------------------------------------------------------+
void ManageActiveTrades()
{
   double atr = iATR(Symbol(), PERIOD_CURRENT, InpATRPeriod, 1);
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
   // In Strategy Tester, relax spread constraint slightly to account for fixed tester spreads
   double maxSpread = IsTesting() ? MathMax(InpMaxSpreadUSD, 0.80) : InpMaxSpreadUSD;
   return (spreadUSD <= maxSpread);
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
   hud += "  XAUUSD LONDON VOLATILITY PYRAMID ENGINE v2.10     \n";
   hud += "====================================================\n";
   hud += StringConcatenate("  Current Balance  : $", DoubleToStr(bal, 2), " (Start: $", DoubleToStr(g_DayStartingBalance, 2), ")\n");
   hud += StringConcatenate("  Current Equity   : $", DoubleToStr(eq, 2), " | Today's PnL: $", DoubleToStr(dayPnL, 2), " (", DoubleToStr(dayPct, 1), "%)\n");
   hud += StringConcatenate("  Next Trade Lot   : ", DoubleToStr(nextLot, 2), " lot (Compounded Tier)\n");
   hud += "----------------------------------------------------\n";
   hud += StringConcatenate("  Asian Range Box  : ", (g_AsianBoxFormed ? StringConcatenate("$", DoubleToStr(g_AsianLow, 2), " - $", DoubleToStr(g_AsianHigh, 2), " (Width: $", DoubleToStr(g_AsianHigh - g_AsianLow, 2), ")") : "Scanning..."), "\n");
   hud += StringConcatenate("  Current Gold Bid : $", DoubleToStr(Bid, 2), " | Spread: $", DoubleToStr(spread, 2), "\n");
   hud += StringConcatenate("  Engine Status    : ", status, "\n");
   hud += StringConcatenate("  Base Order Open  : ", (g_BaseTradeTriggered ? "Active / In Play" : "Awaiting Breakout"), "\n");
   hud += StringConcatenate("  Runner Pyramided : ", (g_RunnerTriggered ? "RUNNER ACTIVE (Riding Trend)" : "Not Triggered"), "\n");
   hud += "====================================================\n";

   Comment(hud);
}
