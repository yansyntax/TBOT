//+------------------------------------------------------------------+
//|                                           AUTOWIN90_MT5.mq5       |
//|  XAUUSD M1 pullback/trend scalper for MT5 hedging accounts.      |
//|                                                                  |
//|  Important: this EA does not promise a win rate. Test it on a    |
//|  demo account and validate the inputs against the broker's symbol |
//|  contract, spread, commission and execution conditions.          |
//+------------------------------------------------------------------+
#property copyright "AUTOWIN90%"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

input group "Identity and execution"
input string InpTradeSymbol = "";                 // Empty = chart symbol
input long   InpMagicNumber = 90909001;
input bool   InpRequireGoldSymbol = true;         // Symbol name must contain XAUUSD
input int    InpMaxSpreadPoints = 50;             // Maximum spread in symbol points
input int    InpCooldownBars = 2;                 // Bars to wait after a basket closes
input int    InpDeviationPoints = 30;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;

input group "Six layer volumes"
input double InpLayer1Lots = 0.01;
input double InpLayer2Lots = 0.01;
input double InpLayer3Lots = 0.01;
input double InpLayer4Lots = 0.01;
input double InpLayer5Lots = 0.01;
input double InpLayer6Lots = 0.01;

input group "Profit targets (account currency units, USC on a cent account)"
input double InpLayer1TargetUSC = 0.10;
input double InpLayer2TargetUSC = 0.20;
input double InpLayer3TargetUSC = 0.30;
input double InpLayer4TargetUSC = 0.50;
input double InpLayer5TargetUSC = 1.00;
input double InpLayer6TargetUSC = 2.00;
input double InpBasketCutUSC = 15.00;              // Close all six at/below this loss
input double InpPerLayerLossCutUSC = 0.00;         // 0 = disabled; optional extra safety

input group "Daily guard (account currency units, USC on a cent account)"
input double InpDailyProfitLimitUSC = 1500.00;
input double InpDailyLossLimitUSC = 50.00;
input bool   InpCloseAtDailyLimit = true;

input group "M1 trend and pullback signal"
input int    InpFastEMAPeriod = 9;
input int    InpSlowEMAPeriod = 21;
input int    InpTrendEMAPeriod = 50;
input int    InpRSIPeriod = 14;
input double InpBuyRSIMax = 58.0;                 // Pullback must not be overbought
input double InpSellRSIMin = 42.0;                // Pullback must not be oversold
input double InpMinStrongBodyPercent = 55.0;     // Body/range of confirmation candle
input int    InpMinStrongBodyPoints = 10;
input int    InpPullbackTolerancePoints = 30;     // Distance from fast EMA
input bool   InpRequireBreakOfPullback = true;
input bool   InpUseADXFilter = true;
input int    InpADXPeriod = 14;
input double InpMinADX = 18.0;

int fastEmaHandle = INVALID_HANDLE;
int slowEmaHandle = INVALID_HANDLE;
int trendEmaHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;
int adxHandle = INVALID_HANDLE;
datetime lastBarTime = 0;
datetime lastBasketCloseTime = 0;
string tradeSymbol = "";

double LayerLots(const int layer)
{
   switch(layer)
   {
      case 1: return InpLayer1Lots;
      case 2: return InpLayer2Lots;
      case 3: return InpLayer3Lots;
      case 4: return InpLayer4Lots;
      case 5: return InpLayer5Lots;
      case 6: return InpLayer6Lots;
   }
   return 0.0;
}

double LayerTarget(const int layer)
{
   switch(layer)
   {
      case 1: return InpLayer1TargetUSC;
      case 2: return InpLayer2TargetUSC;
      case 3: return InpLayer3TargetUSC;
      case 4: return InpLayer4TargetUSC;
      case 5: return InpLayer5TargetUSC;
      case 6: return InpLayer6TargetUSC;
   }
   return 0.0;
}

string LayerComment(const int layer)
{
   return "AUTOWIN90% L" + IntegerToString(layer);
}

bool IsHedgingAccount()
{
   const ENUM_ACCOUNT_MARGIN_MODE mode =
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}

bool IsGoldSymbol(const string symbol)
{
   string upper = symbol;
   StringToUpper(upper);
   return StringFind(upper, "XAUUSD") >= 0;
}

double NormalizeVolume(const double requested)
{
   const double minimum = SymbolInfoDouble(tradeSymbol, SYMBOL_VOLUME_MIN);
   const double maximum = SymbolInfoDouble(tradeSymbol, SYMBOL_VOLUME_MAX);
   const double step = SymbolInfoDouble(tradeSymbol, SYMBOL_VOLUME_STEP);
   if(minimum <= 0.0 || maximum <= 0.0 || step <= 0.0)
      return 0.0;

   double volume = MathMax(minimum, MathMin(maximum, requested));
   volume = MathFloor((volume + 1e-9) / step) * step;
   volume = MathMax(minimum, MathMin(maximum, volume));

   int digits = 0;
   double probe = step;
   while(digits < 8 && MathAbs(probe - MathRound(probe)) > 1e-8)
   {
      probe *= 10.0;
      digits++;
   }
   return NormalizeDouble(volume, digits);
}

bool ReadBufferValue(const int handle, const int buffer, const int shift, double &value)
{
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return false;
   value = values[0];
   return value != EMPTY_VALUE;
}

bool IsNewBar()
{
   const datetime currentBar = iTime(tradeSymbol, PERIOD_M1, 0);
   if(currentBar <= 0 || currentBar == lastBarTime)
      return false;
   lastBarTime = currentBar;
   return true;
}

datetime StartOfServerDay()
{
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
}

double TodayNetResult()
{
   const datetime from = StartOfServerDay();
   const datetime to = TimeCurrent();
   if(!HistorySelect(from, to))
      return 0.0;

   double result = 0.0;
   const int total = HistoryDealsTotal();
   for(int index = 0; index < total; index++)
   {
      const ulong ticket = HistoryDealGetTicket(index);
      if(ticket == 0)
         continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != tradeSymbol)
         continue;

      result += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      result += HistoryDealGetDouble(ticket, DEAL_SWAP);
      result += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      result += HistoryDealGetDouble(ticket, DEAL_FEE);
   }
   return result;
}

bool DailyLimitReached(double &todayResult)
{
   todayResult = TodayNetResult();
   if(InpDailyProfitLimitUSC > 0.0 && todayResult >= InpDailyProfitLimitUSC)
      return true;
   if(InpDailyLossLimitUSC > 0.0 && todayResult <= -InpDailyLossLimitUSC)
      return true;
   return false;
}

int ManagedPositionCount()
{
   int count = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != tradeSymbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      count++;
   }
   return count;
}

double ManagedBasketProfit()
{
   double result = 0.0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != tradeSymbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      // POSITION_PROFIT is floating P/L. POSITION_SWAP is included so the
      // basket guard is closer to the account's net result.
      result += PositionGetDouble(POSITION_PROFIT);
      result += PositionGetDouble(POSITION_SWAP);
   }
   return result;
}

int PositionLayerFromComment(const string comment)
{
   const int marker = StringFind(comment, "L");
   if(marker < 0)
      return 0;
   const string suffix = StringSubstr(comment, marker + 1);
   const int layer = (int)StringToInteger(suffix);
   return layer >= 1 && layer <= 6 ? layer : 0;
}

bool CloseManagedPositions(const string reason)
{
   bool allClosed = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != tradeSymbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(!trade.PositionClose(ticket, InpDeviationPoints))
      {
         PrintFormat("AUTOWIN90 close failed ticket=%I64u reason=%s retcode=%u %s",
                     ticket, reason, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         allClosed = false;
      }
   }

   if(allClosed)
      lastBasketCloseTime = TimeCurrent();
   return allClosed;
}

void ManageOpenPositions()
{
   const int count = ManagedPositionCount();
   if(count <= 0)
      return;

   const double basketProfit = ManagedBasketProfit();
   if(InpBasketCutUSC > 0.0 && basketProfit <= -InpBasketCutUSC)
   {
      CloseManagedPositions("basket cut");
      return;
   }

   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != tradeSymbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      const int layer = PositionLayerFromComment(PositionGetString(POSITION_COMMENT));
      const double netFloatingProfit =
         PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      const double target = LayerTarget(layer);

      if(target > 0.0 && netFloatingProfit >= target)
      {
         if(!trade.PositionClose(ticket, InpDeviationPoints))
            PrintFormat("AUTOWIN90 layer target close failed ticket=%I64u retcode=%u %s",
                        ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         continue;
      }

      if(InpPerLayerLossCutUSC > 0.0 && netFloatingProfit <= -InpPerLayerLossCutUSC)
      {
         if(!trade.PositionClose(ticket, InpDeviationPoints))
            PrintFormat("AUTOWIN90 layer loss close failed ticket=%I64u retcode=%u %s",
                        ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
}

bool SpreadAllowed()
{
   MqlTick tick;
   if(!SymbolInfoTick(tradeSymbol, tick))
      return false;
   const double point = SymbolInfoDouble(tradeSymbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;
   const double spreadPoints = (tick.ask - tick.bid) / point;
   return InpMaxSpreadPoints <= 0 || spreadPoints <= InpMaxSpreadPoints;
}

bool CooldownAllowed()
{
   if(lastBasketCloseTime <= 0 || InpCooldownBars <= 0)
      return true;
   const int barsSinceClose =
      iBarShift(tradeSymbol, PERIOD_M1, lastBasketCloseTime, false);
   return barsSinceClose < 0 || barsSinceClose >= InpCooldownBars;
}

bool GetSignal(int &direction)
{
   direction = 0;
   MqlRates rates[4];
   ArraySetAsSeries(rates, true);
   if(CopyRates(tradeSymbol, PERIOD_M1, 0, 4, rates) < 4)
      return false;

   double fast1, fast2, slow1, slow2, trend1, rsi1, adx1;
   if(!ReadBufferValue(fastEmaHandle, 0, 1, fast1) ||
      !ReadBufferValue(fastEmaHandle, 0, 2, fast2) ||
      !ReadBufferValue(slowEmaHandle, 0, 1, slow1) ||
      !ReadBufferValue(slowEmaHandle, 0, 2, slow2) ||
      !ReadBufferValue(trendEmaHandle, 0, 1, trend1) ||
      !ReadBufferValue(rsiHandle, 0, 1, rsi1))
      return false;

   if(InpUseADXFilter && !ReadBufferValue(adxHandle, 0, 1, adx1))
      return false;
   if(InpUseADXFilter && adx1 < InpMinADX)
      return false;

   const double point = SymbolInfoDouble(tradeSymbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;

   const double pullbackLow = rates[2].low;
   const double pullbackHigh = rates[2].high;
   const double pullbackClose = rates[2].close;
   const double strongOpen = rates[1].open;
   const double strongClose = rates[1].close;
   const double strongHigh = rates[1].high;
   const double strongLow = rates[1].low;
   const double range = strongHigh - strongLow;
   const double body = MathAbs(strongClose - strongOpen);
   if(range <= 0.0 || body < InpMinStrongBodyPoints * point)
      return false;
   if(body / range * 100.0 < InpMinStrongBodyPercent)
      return false;

   const bool upTrend = fast1 > slow1 && slow1 > trend1 &&
                        rates[1].close > trend1 && fast1 >= fast2 && slow1 >= slow2;
   const bool downTrend = fast1 < slow1 && slow1 < trend1 &&
                          rates[1].close < trend1 && fast1 <= fast2 && slow1 <= slow2;

   const bool buyPullback =
      pullbackLow <= fast2 + InpPullbackTolerancePoints * point &&
      pullbackClose >= fast2 - InpPullbackTolerancePoints * point &&
      rsi1 <= InpBuyRSIMax;
   const bool sellPullback =
      pullbackHigh >= fast2 - InpPullbackTolerancePoints * point &&
      pullbackClose <= fast2 + InpPullbackTolerancePoints * point &&
      rsi1 >= InpSellRSIMin;

   const bool bullishConfirmation =
      strongClose > strongOpen &&
      (!InpRequireBreakOfPullback || strongClose > pullbackHigh);
   const bool bearishConfirmation =
      strongClose < strongOpen &&
      (!InpRequireBreakOfPullback || strongClose < pullbackLow);

   if(InpAllowBuy && upTrend && buyPullback && bullishConfirmation)
   {
      direction = 1;
      return true;
   }
   if(InpAllowSell && downTrend && sellPullback && bearishConfirmation)
   {
      direction = -1;
      return true;
   }
   return false;
}

bool OpenSixLayers(const int direction)
{
   trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(tradeSymbol);

   int opened = 0;
   for(int layer = 1; layer <= 6; layer++)
   {
      const double volume = NormalizeVolume(LayerLots(layer));
      if(volume <= 0.0)
      {
         PrintFormat("AUTOWIN90 invalid volume for layer %d", layer);
         continue;
      }

      bool sent = false;
      if(direction > 0)
         sent = trade.Buy(volume, tradeSymbol, 0.0, 0.0, 0.0, LayerComment(layer));
      else
         sent = trade.Sell(volume, tradeSymbol, 0.0, 0.0, 0.0, LayerComment(layer));

      if(sent)
      {
         opened++;
         continue;
      }

      PrintFormat("AUTOWIN90 layer %d open failed retcode=%u %s",
                  layer, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      // Do not leave a partial basket running if the broker rejects a layer.
      CloseManagedPositions("partial open rollback");
      return false;
   }

   if(opened != 6)
   {
      CloseManagedPositions("incomplete six-layer basket");
      return false;
   }

   PrintFormat("AUTOWIN90 opened six %s layers on %s",
               direction > 0 ? "BUY" : "SELL", tradeSymbol);
   return true;
}

int OnInit()
{
   if(_Period != PERIOD_M1)
   {
      Print("AUTOWIN90 must be attached to an M1 chart.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!IsHedgingAccount())
   {
      Print("AUTOWIN90 requires an MT5 hedging account so six independent layers can be managed.");
      return INIT_FAILED;
   }

   tradeSymbol = InpTradeSymbol == "" ? _Symbol : InpTradeSymbol;
   if(InpRequireGoldSymbol && !IsGoldSymbol(tradeSymbol))
   {
      PrintFormat("AUTOWIN90 expected an XAUUSD symbol, received %s.", tradeSymbol);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!SymbolSelect(tradeSymbol, true))
   {
      PrintFormat("AUTOWIN90 could not select symbol %s.", tradeSymbol);
      return INIT_FAILED;
   }
   if(InpBasketCutUSC <= 0.0 || InpDailyLossLimitUSC <= 0.0 ||
      InpDailyProfitLimitUSC <= 0.0)
   {
      Print("AUTOWIN90 basket and daily limits must be positive.");
      return INIT_PARAMETERS_INCORRECT;
   }

   fastEmaHandle = iMA(tradeSymbol, PERIOD_M1, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle = iMA(tradeSymbol, PERIOD_M1, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   trendEmaHandle = iMA(tradeSymbol, PERIOD_M1, InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(tradeSymbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   adxHandle = iADX(tradeSymbol, PERIOD_M1, InpADXPeriod);

   if(fastEmaHandle == INVALID_HANDLE || slowEmaHandle == INVALID_HANDLE ||
      trendEmaHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE ||
      adxHandle == INVALID_HANDLE)
   {
      Print("AUTOWIN90 failed to create indicator handles.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(tradeSymbol);
   PrintFormat("AUTOWIN90 ready: %s M1, account=%s, spread limit=%d points",
               tradeSymbol, AccountInfoString(ACCOUNT_CURRENCY), InpMaxSpreadPoints);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(fastEmaHandle != INVALID_HANDLE) IndicatorRelease(fastEmaHandle);
   if(slowEmaHandle != INVALID_HANDLE) IndicatorRelease(slowEmaHandle);
   if(trendEmaHandle != INVALID_HANDLE) IndicatorRelease(trendEmaHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
}

void OnTick()
{
   if(tradeSymbol == "")
      return;

   ManageOpenPositions();

   double todayResult = 0.0;
   if(DailyLimitReached(todayResult))
   {
      if(InpCloseAtDailyLimit && ManagedPositionCount() > 0)
         CloseManagedPositions("daily limit");
      Comment("AUTOWIN90% halted for today\n",
              "Today net: ", DoubleToString(todayResult, 2), " ",
              AccountInfoString(ACCOUNT_CURRENCY));
      return;
   }

   const int managedCount = ManagedPositionCount();
   if(managedCount > 0)
   {
      Comment("AUTOWIN90% running\n",
              "Layers: ", IntegerToString(managedCount), "/6\n",
              "Basket: ", DoubleToString(ManagedBasketProfit(), 2), " ",
              AccountInfoString(ACCOUNT_CURRENCY), "\n",
              "Today: ", DoubleToString(todayResult, 2), " ",
              AccountInfoString(ACCOUNT_CURRENCY));
      return;
   }

   if(!IsNewBar() || !CooldownAllowed() || !SpreadAllowed())
      return;

   int direction = 0;
   if(GetSignal(direction))
      OpenSixLayers(direction);
}
