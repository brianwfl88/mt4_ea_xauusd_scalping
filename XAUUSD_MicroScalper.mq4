//+------------------------------------------------------------------+
//|                                         XAUUSD_MicroScalper.mq4  |
//|                         Automated High-Liquidity Micro-Scalper   |
//|                                  Engineered for $100 -> $500 Target |
//+------------------------------------------------------------------+
#property copyright "Quantitative Trading Engine"
#property link      "https://github.com"
#property version   "1.00"
#property strict

//--- Input Parameters
input string   _Strategy_Settings      = "=== Strategy & Risk Rules ===";
input double   InpFixedLot             = 0.01;      // Fixed Lot Size (Micro Lot 0.01)
input bool     InpUseCompounding       = false;     // Enable Dynamic Compounding (Lot grows with equity)
input double   InpRiskPercentPerTrade  = 2.0;       // Risk % per trade if compounding (1.5 - 2.5%)
input double   InpProfitTargetPercent  = 1.0;       // Target Profit % per trade (Close at >= 1% gain)
input double   InpStopLossPercent      = 2.0;       // Stop Loss % per trade (Max loss per trade)
input double   InpMaxDrawdownPercent   = 4.8;       // Hard Drawdown Circuit Breaker % (Max 5.0%)
input bool     InpUseBreakEven         = true;      // Enable Move Stop to Break-Even
input double   InpBreakEvenTriggerPct  = 0.5;       // Profit % to trigger Break-Even (e.g. 0.5%)
input double   InpBreakEvenLockPips    = 2.0;       // Pips to lock above entry price

input string   _Session_Settings       = "=== Session & Liquidity Filter ===";
input bool     InpTradeLondon          = true;      // Trade London Open Session
input int      InpLondonStartHour      = 7;         // London Start Hour (UTC)
input int      InpLondonEndHour        = 11;        // London End Hour (UTC)
input bool     InpTradeNewYork         = true;      // Trade New York Open Session
input int      InpNewYorkStartHour     = 13;        // New York Start Hour (UTC)
input int      InpNewYorkEndHour       = 17;        // New York End Hour (UTC)
input int      InpBrokerUtcOffset      = 2;         // Broker Server UTC/GMT Offset (e.g., +2 or +3)
input double   InpMaxSpreadPips        = 35.0;      // Max Allowable Spread in Pips (e.g. 35 = $0.35)

input string   _Indicator_Settings     = "=== Indicator & Signal Triggers ===";
input int      InpFastEMA              = 50;        // Trend Filter Fast EMA (M5)
input int      InpSlowEMA              = 200;       // Trend Filter Slow EMA (M5)
input int      InpBBPeriod             = 20;        // Bollinger Bands Period (M1)
input double   InpBBDeviation          = 2.0;       // Bollinger Bands Deviation
input int      InpRSIPeriod            = 14;        // RSI Period (M1)
input double   InpRSIBuyThreshold      = 52.0;      // RSI Buy Momentum Level
input double   InpRSISellThreshold     = 48.0;      // RSI Sell Momentum Level

input string   _Execution_Settings     = "=== Execution & Magic Number ===";
input int      InpMagicNumber          = 777100;    // Unique Magic Number
input int      InpSlippage             = 30;        // Max Slippage in Points
input int      InpMaxConcurrentTrades  = 1;         // Strictly 1 open trade at a time

//--- Global Variables
double g_PeakEquity            = 0.0;
double g_InitialBalance        = 0.0;
bool   g_CircuitBreakerTriggered = false;
int    g_PipMultiplier         = 10;
double g_PipValue              = 0.01;
double g_ContractSize          = 100.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate Symbol
   string sym = Symbol();
   if (StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
   {
      Print("[WARNING] Current symbol is ", sym, ". This EA is optimized specifically for XAUUSD / GOLD.");
   }

   // Initialize Peak Tracking
   g_InitialBalance = AccountBalance();
   g_PeakEquity     = MathMax(g_InitialBalance, AccountEquity());
   g_CircuitBreakerTriggered = false;

   // Point and Pip Normalization
   // For XAUUSD, standard brokers use 2 decimals (0.01 per point, 10 points = 1 pip = $0.10)
   // Some brokers use 3 decimals (0.001 per point, 100 points = 1 pip = $0.10)
   if (Digits == 3 || Digits == 5)
   {
      g_PipMultiplier = 10;
      g_PipValue = Point * 10;
   }
   else
   {
      g_PipMultiplier = 1;
      g_PipValue = Point;
   }

   g_ContractSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   if (g_ContractSize <= 0) g_ContractSize = 100.0; // Default 100 oz per lot

   Print("[INIT] XAUUSD MicroScalper Initialized. Balance: $", DoubleToStr(g_InitialBalance, 2),
         " | Peak Equity: $", DoubleToStr(g_PeakEquity, 2),
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
   // 1. Maintain Peak Equity
   double currentEquity = AccountEquity();
   if (currentEquity > g_PeakEquity)
   {
      g_PeakEquity = currentEquity;
   }

   // 2. Critical Safety: 5% Max Drawdown Circuit Breaker
   double currentDrawdown = 0.0;
   if (g_PeakEquity > 0)
   {
      currentDrawdown = ((g_PeakEquity - currentEquity) / g_PeakEquity) * 100.0;
   }

   if (currentDrawdown >= InpMaxDrawdownPercent)
   {
      if (!g_CircuitBreakerTriggered)
      {
         Print("[CIRCUIT BREAKER TRIGGERED] Drawdown reached ", DoubleToStr(currentDrawdown, 2),
               "% (Limit: ", DoubleToStr(InpMaxDrawdownPercent, 2), "%). Closing all positions and halting trading!");
         CloseAllPositions();
         g_CircuitBreakerTriggered = true;
      }
      UpdateDashboard(currentDrawdown, "CIRCUIT BREAKER ACTIVATED - TRADING HALTED");
      return;
   }

   // 3. Manage Open Trades: 1% Take Profit check & Break-Even
   ManageOpenTrades();

   // 4. Update HUD On-Chart Dashboard
   string sessionStatus = IsWithinActiveSession() ? "Active Session" : "Outside Trading Window";
   UpdateDashboard(currentDrawdown, sessionStatus);

   // 5. Check if trading allowed
   if (g_CircuitBreakerTriggered) return;
   if (!IsWithinActiveSession()) return;
   if (!IsSpreadAcceptable()) return;
   if (CountOpenTrades() >= InpMaxConcurrentTrades) return;

   // 6. Check Signal and Execute Entry
   CheckAndExecuteSignal();
}

//+------------------------------------------------------------------+
//| Check if current server time falls inside London/NY Open Windows |
//+------------------------------------------------------------------+
bool IsWithinActiveSession()
{
   datetime serverTime = TimeCurrent();
   int serverHour = TimeHour(serverTime);

   // Convert Server Hour to UTC Hour
   int utcHour = serverHour - InpBrokerUtcOffset;
   if (utcHour < 0)  utcHour += 24;
   if (utcHour >= 24) utcHour -= 24;

   // Check London Open Window (e.g. 07:00 - 11:00 UTC)
   if (InpTradeLondon && (utcHour >= InpLondonStartHour && utcHour < InpLondonEndHour))
   {
      return true;
   }

   // Check New York Open Window (e.g. 13:00 - 17:00 UTC)
   if (InpTradeNewYork && (utcHour >= InpNewYorkStartHour && utcHour < InpNewYorkEndHour))
   {
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Spread Check to avoid high-spread slippage                      |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   double spreadPoints = MarketInfo(Symbol(), MODE_SPREAD);
   double spreadPips   = spreadPoints / g_PipMultiplier;

   return (spreadPips <= InpMaxSpreadPips);
}

//+------------------------------------------------------------------+
//| Count active positions for this EA                               |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber)
         {
            if (OrderType() == OP_BUY || OrderType() == OP_SELL)
            {
               count++;
            }
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Manage Open Trades: Enforce 1% Take Profit and Break-Even        |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   double currentBalance = AccountBalance();
   double targetProfitDollars = currentBalance * (InpProfitTargetPercent / 100.0);
   double beTriggerDollars    = currentBalance * (InpBreakEvenTriggerPct / 100.0);

   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber)
         {
            double netProfit = OrderProfit() + OrderSwap() + OrderCommission();

            // 1. Take Profit Check: Close if trade has made >= 1% profit
            if (netProfit >= targetProfitDollars)
            {
               Print("[TAKE PROFIT HIT] Net Profit: $", DoubleToStr(netProfit, 2),
                     " >= Target: $", DoubleToStr(targetProfitDollars, 2),
                     " (1% Gain). Closing Order #", OrderTicket());
               CloseSingleOrder(OrderTicket());
               continue;
            }

            // 2. Break-Even Trail
            if (InpUseBreakEven)
            {
               double openPrice = OrderOpenPrice();
               double stopLoss  = OrderStopLoss();

               if (OrderType() == OP_BUY)
               {
                  if (netProfit >= beTriggerDollars)
                  {
                     double newSL = NormalizeDouble(openPrice + (InpBreakEvenLockPips * g_PipValue), Digits);
                     if (stopLoss < openPrice || stopLoss == 0)
                     {
                        bool res = OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrGreen);
                        if (res) Print("[BREAK-EVEN SET] BUY Order #", OrderTicket(), " SL moved to ", newSL);
                     }
                  }
               }
               else if (OrderType() == OP_SELL)
               {
                  if (netProfit >= beTriggerDollars)
                  {
                     double newSL = NormalizeDouble(openPrice - (InpBreakEvenLockPips * g_PipValue), Digits);
                     if (stopLoss > openPrice || stopLoss == 0)
                     {
                        bool res = OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrRed);
                        if (res) Print("[BREAK-EVEN SET] SELL Order #", OrderTicket(), " SL moved to ", newSL);
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check Indicator Signals & Execute Scalp Entry                   |
//+------------------------------------------------------------------+
void CheckAndExecuteSignal()
{
   // 1. Higher Timeframe Trend Filter (M5 EMA 50 vs EMA 200)
   double ema50_M5  = iMA(Symbol(), PERIOD_M5, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema200_M5 = iMA(Symbol(), PERIOD_M5, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double close_M5  = iClose(Symbol(), PERIOD_M5, 1);

   bool trendBullish = (close_M5 > ema50_M5 && ema50_M5 > ema200_M5);
   bool trendBearish = (close_M5 < ema50_M5 && ema50_M5 < ema200_M5);

   // 2. M1 Execution Trigger (Bollinger Bands + RSI)
   double bbUpper_M1 = iBands(Symbol(), PERIOD_M1, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double bbLower_M1 = iBands(Symbol(), PERIOD_M1, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbMiddle_M1= iBands(Symbol(), PERIOD_M1, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_MAIN, 1);
   double rsi_M1     = iRSI(Symbol(), PERIOD_M1, InpRSIPeriod, PRICE_CLOSE, 1);
   double close_M1   = iClose(Symbol(), PERIOD_M1, 1);
   double open_M1    = iOpen(Symbol(), PERIOD_M1, 1);

   // Buy Setup: M5 Trend is Up, M1 breaks upward through BB Mid/Upper with RSI > 52
   if (trendBullish && close_M1 > bbMiddle_M1 && open_M1 <= bbMiddle_M1 && rsi_M1 >= InpRSIBuyThreshold)
   {
      ExecuteOrder(OP_BUY);
   }
   // Sell Setup: M5 Trend is Down, M1 breaks downward through BB Mid/Lower with RSI < 48
   else if (trendBearish && close_M1 < bbMiddle_M1 && open_M1 >= bbMiddle_M1 && rsi_M1 <= InpRSISellThreshold)
   {
      ExecuteOrder(OP_SELL);
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Mode                                 |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double lot = InpFixedLot;

   if (InpUseCompounding)
   {
      double riskDollars = AccountBalance() * (InpRiskPercentPerTrade / 100.0);
      double slPoints    = (AccountBalance() * (InpStopLossPercent / 100.0)) / (g_ContractSize * Point);
      double tickVal     = MarketInfo(Symbol(), MODE_TICKVALUE);

      if (slPoints > 0 && tickVal > 0)
      {
         lot = riskDollars / (slPoints * tickVal);
      }
   }

   // Normalize lot size to broker specifications
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if (lot < minLot) lot = minLot;
   if (lot > maxLot) lot = maxLot;
   lot = MathFloor(lot / lotStep) * lotStep;

   return lot;
}

//+------------------------------------------------------------------+
//| Open Market Order with Strict Stop Loss & Take Profit            |
//+------------------------------------------------------------------+
void ExecuteOrder(int orderType)
{
   double lot = CalculateLotSize();
   double balance = AccountBalance();

   // Dollar Risk & Target Math:
   // 1% profit on $100 = $1.00.
   // On XAUUSD (0.01 lot = 1 oz), a $1.00 price move = $1.00 PnL.
   double targetProfitDollars = balance * (InpProfitTargetPercent / 100.0);
   double maxLossDollars      = balance * (InpStopLossPercent / 100.0);

   // Calculate Price Distance in Gold Dollars
   double targetPriceDist = targetProfitDollars / (lot * g_ContractSize);
   double slPriceDist     = maxLossDollars / (lot * g_ContractSize);

   double price = 0.0;
   double sl    = 0.0;
   double tp    = 0.0;
   color  clr   = clrBlue;

   RefreshRates();

   if (orderType == OP_BUY)
   {
      price = Ask;
      sl    = NormalizeDouble(price - slPriceDist, Digits);
      tp    = NormalizeDouble(price + targetPriceDist, Digits);
      clr   = clrDodgerBlue;
   }
   else if (orderType == OP_SELL)
   {
      price = Bid;
      sl    = NormalizeDouble(price + slPriceDist, Digits);
      tp    = NormalizeDouble(price - targetPriceDist, Digits);
      clr   = clrCrimson;
   }
   else return;

   // Minimum Stop Level Check
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if (MathAbs(price - sl) < stopLevel) sl = (orderType == OP_BUY) ? (price - stopLevel) : (price + stopLevel);
   if (MathAbs(tp - price) < stopLevel) tp = (orderType == OP_BUY) ? (price + stopLevel) : (price - stopLevel);

   int ticket = OrderSend(Symbol(), orderType, lot, price, InpSlippage, sl, tp, "XAUUSD MicroScalper", InpMagicNumber, 0, clr);

   if (ticket > 0)
   {
      Print("[TRADE OPENED] #", ticket, " ", (orderType == OP_BUY ? "BUY " : "SELL "),
            DoubleToStr(lot, 2), " lots @ ", DoubleToStr(price, Digits),
            " | Target: $", DoubleToStr(targetProfitDollars, 2),
            " | SL: ", DoubleToStr(sl, Digits), " | TP: ", DoubleToStr(tp, Digits));
   }
   else
   {
      Print("[ERROR] OrderSend failed with error #", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Close a single order                                             |
//+------------------------------------------------------------------+
bool CloseSingleOrder(int ticket)
{
   if (OrderSelect(ticket, SELECT_BY_TICKET))
   {
      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
      return OrderClose(ticket, OrderLots(), closePrice, InpSlippage, clrGold);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Emergency Close All Positions for this EA                        |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == InpMagicNumber)
         {
            CloseSingleOrder(OrderTicket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| On-Chart Heads-Up Dashboard Display                              |
//+------------------------------------------------------------------+
void UpdateDashboard(double currentDrawdown, string sessionStatus)
{
   double balance = AccountBalance();
   double equity  = AccountEquity();
   double spread  = MarketInfo(Symbol(), MODE_SPREAD) / g_PipMultiplier;
   double todayPnL = equity - g_InitialBalance;
   double todayPnLPct = (g_InitialBalance > 0) ? (todayPnL / g_InitialBalance) * 100.0 : 0.0;

   string hud = "";
   hud += "==================================================\n";
   hud += "  XAUUSD MICRO-SCALPER ($100 -> $500 STRATEGY)    \n";
   hud += "==================================================\n";
   hud += StringConcatenate("  Current Balance     : $", DoubleToStr(balance, 2), "\n");
   hud += StringConcatenate("  Current Equity      : $", DoubleToStr(equity, 2), "\n");
   hud += StringConcatenate("  Peak Equity Recorded: $", DoubleToStr(g_PeakEquity, 2), "\n");
   hud += StringConcatenate("  Current Drawdown    : ", DoubleToStr(currentDrawdown, 2), "% (Max Allowed: ", DoubleToStr(InpMaxDrawdownPercent, 2), "%)\n");
   hud += "--------------------------------------------------\n";
   hud += StringConcatenate("  Session Status      : ", sessionStatus, "\n");
   hud += StringConcatenate("  Current Spread      : ", DoubleToStr(spread, 1), " pips (Max: ", DoubleToStr(InpMaxSpreadPips, 1), ")\n");
   hud += StringConcatenate("  Net Session PnL     : $", DoubleToStr(todayPnL, 2), " (", DoubleToStr(todayPnLPct, 2), "%)\n");
   hud += StringConcatenate("  Circuit Breaker     : ", (g_CircuitBreakerTriggered ? "HALTED [TRIP]" : "OK [MONITORING]"), "\n");
   hud += "==================================================\n";

   Comment(hud);
}
