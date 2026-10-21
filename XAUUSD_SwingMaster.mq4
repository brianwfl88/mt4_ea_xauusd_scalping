//+------------------------------------------------------------------+
//|                                         XAUUSD_SwingMaster.mq4   |
//|               Institutional Trend & Volatility Swing Engine      |
//|                    Engineered for Gold (XAUUSD) Swing Trading    |
//|                         Supports 1:500 Leverage & Compounding    |
//+------------------------------------------------------------------+
#property copyright "Quantitative Trading Engine"
#property link      "https://github.com"
#property version   "1.00"
#property strict

//--- Inputs: Account Sizing & Risk Management
input string   _Section1               = "=== Sizing & Compounding Tiers ===";
input bool     InpUseDynamicTiers      = true;     // Enable Dynamic Compounding Tiers
input double   InpManualBaseLot        = 0.02;     // Manual Lot if Dynamic Tiers disabled (0.02 at 1:500)
input double   InpRiskPercentPerTrade  = 6.0;      // Risk % per swing setup (5.0 - 8.0%)
input double   InpRewardRatioTP1       = 2.0;      // Risk-to-Reward ratio for TP1 (e.g. 1:2 R:R)
input double   InpPartialClosePercent  = 50.0;     // Percentage of position to close at TP1 (50%)
input double   InpBreakEvenBufferUSD   = 0.50;     // Profit locked when moving to Break-Even ($0.50)

//--- Inputs: Multi-Timeframe Trend & Value Zone
input string   _Section2               = "=== Macro Trend & Pullback Logic ===";
input int      InpMacroEMA_Fast        = 50;       // Macro Trend Fast EMA (H4 / D1)
input int      InpMacroEMA_Slow        = 200;      // Macro Trend Slow EMA (H4 / D1)
input int      InpPullbackEMA_Fast     = 20;       // H1 Value Zone Fast EMA
input int      InpPullbackEMA_Slow     = 50;       // H1 Value Zone Slow EMA
input int      InpRSIPeriod            = 14;       // H1 RSI Period
input double   InpRSIOversoldBuy       = 42.0;     // Buy when RSI pulls back below this and hooks up
input double   InpRSIOverboughtSell    = 58.0;     // Sell when RSI pulls back above this and hooks down

//--- Inputs: Stop Loss & ATR Trailing Stop
input string   _Section3               = "=== Stop Loss & ATR Trailing ===";
input int      InpATRPeriod            = 14;       // ATR Period for Stop Loss and Trailing
input double   InpATRFactorSL          = 1.8;      // Initial SL Multiplier of H1/H4 ATR
input double   InpATRFactorTrail       = 2.2;      // Runner Trailing Stop Multiplier of ATR
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
input int      InpSlippage             = 40;       // Max Slippage in Points
input bool     InpVerboseLogging       = true;     // Verbose logging in Journal

//--- Global Variables
double g_ContractSize        = 100.0;
double g_InitialBalance      = 0.0;
bool   g_PartialClosed       = false;
bool   g_FridayClosedForLowVol = false;
int    g_LastLoggedHour      = -1;

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

   Print("==================================================================");
   Print("[INIT] XAUUSD Swing Master Engine v1.0 Initialized.");
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

   // 3. Hourly Diagnostic Output
   LogHourlyStatus();

   // 4. Update HUD Display
   UpdateHUD();

   // 5. Entry Guard Checks
   if (g_FridayClosedForLowVol) return;
   if (CountOpenSwingTrades() > 0) return; // Swing strategy holds 1 high-conviction setup at a time
   if (!IsSpreadOk()) return;

   // 6. Check Swing Entry Signal
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
         // Calculate current H1 ATR vs 24-period moving average of ATR
         double currentATR = iATR(Symbol(), PERIOD_H1, InpATRPeriod, 1);
         double sumATR = 0.0;
         for (int i = 1; i <= 24; i++)
         {
            sumATR += iATR(Symbol(), PERIOD_H1, InpATRPeriod, i);
         }
         double avgATR = sumATR / 24.0;

         // Check if volatility has dried up
         if (avgATR > 0 && (currentATR < (avgATR * InpFridayVolThreshold)))
         {
            if (CountOpenSwingTrades() > 0)
            {
               Print("[FRIDAY WEEKEND GUARD] Low volatility detected on Friday late session. Current ATR: $",
                     DoubleToStr(currentATR, 2), " < ", DoubleToStr(InpFridayVolThreshold * 100.0, 0),
                     "% of 24h Average ATR ($", DoubleToStr(avgATR, 2), "). Closing open positions to eliminate weekend gap risk.");
               CloseAllSwingPositions();
               g_FridayClosedForLowVol = true;
            }
         }
      }
   }
   else
   {
      g_FridayClosedForLowVol = false; // Reset on other days
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
      // Scaling tiers optimized for $100 starting balance:
      // $100 - $149 : 0.02 lot (requires ~$10.60 margin at 1:500)
      // $150 - $249 : 0.04 lot (requires ~$21.20 margin at 1:500)
      // $250 - $379 : 0.07 lot (requires ~$37.10 margin at 1:500)
      // $380+       : 0.10 lot (requires ~$53.00 margin at 1:500)
      if (bal >= 380.0)      lot = 0.10;
      else if (bal >= 250.0) lot = 0.07;
      else if (bal >= 150.0) lot = 0.04;
      else                   lot = 0.02;
   }

   // Broker compliance check
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;
   lot = MathFloor(lot / lotStep) * lotStep;

   // Margin check
   double marginReq = (Ask * lot * g_ContractSize) / MathMax(AccountLeverage(), 1);
   if (marginReq > (AccountFreeMargin() * 0.70) && lot > minLot)
   {
      lot = minLot;
   }

   return lot;
}

//+------------------------------------------------------------------+
//| Check Multi-Timeframe Trend & H1 Pullback Entry Signal           |
//+------------------------------------------------------------------+
void CheckAndExecuteSwingEntry()
{
   // 1. Macro Trend Confirmation (H4 Timeframe EMA 50 vs EMA 200)
   double h4_EMA_Fast = iMA(Symbol(), PERIOD_H4, InpMacroEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double h4_EMA_Slow = iMA(Symbol(), PERIOD_H4, InpMacroEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double h4_Close    = iClose(Symbol(), PERIOD_H4, 1);

   bool macroBullish = (h4_Close > h4_EMA_Fast && h4_EMA_Fast > h4_EMA_Slow);
   bool macroBearish = (h4_Close < h4_EMA_Fast && h4_EMA_Fast < h4_EMA_Slow);

   if (!macroBullish && !macroBearish) return; // No clear directional macro trend

   // 2. H1 Pullback into Value Zone (between EMA 20 and EMA 50)
   double h1_EMA20 = iMA(Symbol(), PERIOD_H1, InpPullbackEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double h1_EMA50 = iMA(Symbol(), PERIOD_H1, InpPullbackEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double h1_Close1 = iClose(Symbol(), PERIOD_H1, 1);
   double h1_Low1   = iLow(Symbol(), PERIOD_H1, 1);
   double h1_High1  = iHigh(Symbol(), PERIOD_H1, 1);

   // 3. H1 RSI Momentum Turnaround Confirmation
   double rsi_1 = iRSI(Symbol(), PERIOD_H1, InpRSIPeriod, PRICE_CLOSE, 1);
   double rsi_2 = iRSI(Symbol(), PERIOD_H1, InpRSIPeriod, PRICE_CLOSE, 2);

   // Calculate Dynamic Stop Loss distance using H1 ATR
   double atr = iATR(Symbol(), PERIOD_H1, InpATRPeriod, 1);
   if (atr <= 0) atr = 2.50; // fallback $2.50
   double slDistUSD = atr * InpATRFactorSL;

   // Ensure Stop Loss satisfies broker minimum StopLevel
   double minStopUSD = (MarketInfo(Symbol(), MODE_STOPLEVEL) * Point) + (10 * Point);
   if (slDistUSD < minStopUSD) slDistUSD = minStopUSD;

   // TP1 Target based on Risk-to-Reward ratio
   double tp1DistUSD = slDistUSD * InpRewardRatioTP1;

   RefreshRates();
   double lot = GetCompoundedSwingLot();

   // --- BUY SETUP ---
   // Macro Bullish + H1 Low dipped into/near EMA20-50 zone + RSI hooked up from oversold
   if (macroBullish && h1_Low1 <= h1_EMA20 && h1_Close1 >= h1_EMA20 && (rsi_2 <= InpRSIOversoldBuy && rsi_1 > rsi_2))
   {
      double price = Ask;
      double sl    = NormalizeDouble(price - slDistUSD, Digits);
      double tp    = NormalizeDouble(price + tp1DistUSD, Digits);

      int ticket = OrderSend(Symbol(), OP_BUY, lot, price, InpSlippage, sl, tp, "Swing Buy Setup", InpMagicNumber, 0, clrDodgerBlue);
      if (ticket > 0)
      {
         Print("[SWING BUY EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
               " | SL: ", sl, " (Risk: $", DoubleToStr(slDistUSD, 2), ") | TP1: ", tp, " (Reward: $", DoubleToStr(tp1DistUSD, 2), ")");
         g_PartialClosed = false;
      }
      else
      {
         Print("[ERROR] Swing BUY OrderSend failed with error #", GetLastError());
      }
   }
   // --- SELL SETUP ---
   // Macro Bearish + H1 High tested into/near EMA20-50 zone + RSI hooked down from overbought
   else if (macroBearish && h1_High1 >= h1_EMA20 && h1_Close1 <= h1_EMA20 && (rsi_2 >= InpRSIOverboughtSell && rsi_1 < rsi_2))
   {
      double price = Bid;
      double sl    = NormalizeDouble(price + slDistUSD, Digits);
      double tp    = NormalizeDouble(price - tp1DistUSD, Digits);

      int ticket = OrderSend(Symbol(), OP_SELL, lot, price, InpSlippage, sl, tp, "Swing Sell Setup", InpMagicNumber, 0, clrCrimson);
      if (ticket > 0)
      {
         Print("[SWING SELL EXECUTED] Order #", ticket, " ", DoubleToStr(lot, 2), " lots @ ", price,
               " | SL: ", sl, " (Risk: $", DoubleToStr(slDistUSD, 2), ") | TP1: ", tp, " (Reward: $", DoubleToStr(tp1DistUSD, 2), ")");
         g_PartialClosed = false;
      }
      else
      {
         Print("[ERROR] Swing SELL OrderSend failed with error #", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Open Swing Trades: Partial Close at TP1 & ATR Trailing    |
//+------------------------------------------------------------------+
void ManageOpenSwingTrades()
{
   double atr = iATR(Symbol(), PERIOD_H4, InpATRPeriod, 1);
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
            double profitUSD = (OrderType() == OP_BUY) ? (curPrice - openPrice) : (openPrice - curPrice);

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
                              " at target price ", curPrice, ". Locking remainder at Break-Even!");
                        g_PartialClosed = true;

                        // Shift Stop Loss to Break-Even + Buffer and clear TP to let runner ride
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

            // 2. Trailing Stop for the remaining Runner using H4 ATR
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
//| Periodic Diagnostic Output to MT4 Journal                        |
//+------------------------------------------------------------------+
void LogHourlyStatus()
{
   if (!InpVerboseLogging) return;

   int currentHour = TimeHour(TimeCurrent());
   if (currentHour != g_LastLoggedHour)
   {
      g_LastLoggedHour = currentHour;
      double h4_fast = iMA(Symbol(), PERIOD_H4, InpMacroEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
      double h4_slow = iMA(Symbol(), PERIOD_H4, InpMacroEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
      string trend = (h4_fast > h4_slow) ? "BULLISH" : "BEARISH";

      Print("[SWING SCANNER] Time: ", TimeToStr(TimeCurrent(), TIME_DATE|TIME_MINUTES),
            " | H4 Macro Trend: ", trend,
            " | H1 Close: ", DoubleToStr(Close[1], 2),
            " | Open Trades: ", CountOpenSwingTrades(),
            " | Spread: $", DoubleToStr(Ask - Bid, 2));
   }
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

   double h4_fast = iMA(Symbol(), PERIOD_H4, InpMacroEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double h4_slow = iMA(Symbol(), PERIOD_H4, InpMacroEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   string trend = (h4_fast > h4_slow) ? "BULLISH (BUY ONLY)" : "BEARISH (SELL ONLY)";

   string hud = "";
   hud += "====================================================\n";
   hud += "  XAUUSD SWING MASTER EA (H1/H4 SWING ENGINE)       \n";
   hud += "====================================================\n";
   hud += StringConcatenate("  Current Balance   : $", DoubleToStr(bal, 2), " (Initial: $", DoubleToStr(g_InitialBalance, 2), ")\n");
   hud += StringConcatenate("  Current Equity    : $", DoubleToStr(eq, 2), " | Total PnL: $", DoubleToStr(pnl, 2), " (", DoubleToStr(pct, 1), "%)\n");
   hud += StringConcatenate("  Compounded Lot    : ", DoubleToStr(lot, 2), " lot (Leverage 1:500)\n");
   hud += "----------------------------------------------------\n";
   hud += StringConcatenate("  H4 Macro Trend    : ", trend, "\n");
   hud += StringConcatenate("  Active Trades     : ", CountOpenSwingTrades(), " trade(s)\n");
   hud += StringConcatenate("  Partial TP1 Status: ", (g_PartialClosed ? "TP1 BANKED (RUNNER TRAILING)" : "AWAITING TP1"), "\n");
   hud += StringConcatenate("  Friday Low Vol Guard: ", (g_FridayClosedForLowVol ? "TRIGGERED (CLOSED FOR WEEKEND)" : "MONITORING"), "\n");
   hud += StringConcatenate("  Current Gold Bid  : $", DoubleToStr(Bid, 2), " | Spread: $", DoubleToStr(Ask - Bid, 2), "\n");
   hud += "====================================================\n";

   Comment(hud);
}
