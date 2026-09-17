//+------------------------------------------------------------------+
//|                               LowRisk_GoldScalper_500USC.mq5     |
//|                               Copyright 2026, Safe Scalper Bot   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

// --- Input Parameters ---
input group "--- Settings Risk & Modal (500 USC) ---"
input double   InpLotSize         = 0.01;     // Lot Terkecil (Aman untuk 500 USC)
input int      InpMaxPositions    = 1;        // Maksimal 1 Posisi Terbuka (Low Risk)
input ulong    InpMagicNumber     = 121212;   // Magic Number EA

input group "--- Target Pips (1 Pips = 10 Points) ---"
input int      InpStopLossPips    = 15;       // Cut Loss Max 15 Pips
input int      InpTakeProfitPips  = 15;       // Target Profit 15 Pips
input int      InpBEPips          = 8;        // Kunci SL+ saat Profit 8 Pips

// Global Handles
int handleEMA_Fast;
int handleEMA_Slow;
int handleRSI;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   handleEMA_Fast = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(_Symbol, _Period, 50, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI      = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
   
   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Slow == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
      return(INIT_FAILED);

   Print("EA Low Risk Gold Scalper Berhasil Dijalankan!");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(handleEMA_Fast);
   IndicatorRelease(handleEMA_Slow);
   IndicatorRelease(handleRSI);
  }

void OnTick()
  {
   // 1. Geser ke SL+ jika running profit
   ApplyBreakEven();

   // 2. Eksekusi Entry jika posisi sedang kosong
   if(CountPositions() < InpMaxPositions)
     {
      CheckEntrySignal();
     }
  }

// --- Fungsi Analisis Sinyal Scalping Presisi ---
void CheckEntrySignal()
  {
   double emaFast[], emaSlow[], rsi[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleEMA_Fast, 0, 0, 2, emaFast) < 2) return;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 2, emaSlow) < 2) return;
   if(CopyBuffer(handleRSI, 0, 0, 2, rsi) < 2) return;

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Arah Uptrend (EMA20 > EMA50) + RSI Konfirmasi Naik (RSI antara 50 - 68)
   if(emaFast[0] > emaSlow[0] && rsi[0] > 50.0 && rsi[0] < 68.0)
     {
      double sl = ask - (InpStopLossPips * 10 * point);
      double tp = ask + (InpTakeProfitPips * 10 * point);
      trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "Safe Buy Scalp");
     }
   // Arah Downtrend (EMA20 < EMA50) + RSI Konfirmasi Turun (RSI antara 32 - 50)
   else if(emaFast[0] < emaSlow[0] && rsi[0] < 50.0 && rsi[0] > 32.0)
     {
      double sl = bid + (InpStopLossPips * 10 * point);
      double tp = bid - (InpTakeProfitPips * 10 * point);
      trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "Safe Sell Scalp");
     }
  }

// --- Fungsi Auto SL+ (Lock Profit) ---
void ApplyBreakEven()
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            double currentSL = PositionGetDouble(POSITION_SL);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
              {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               if(bid - openPrice >= InpBEPips * 10 * point)
                 {
                  double newSL = openPrice + (2 * 10 * point); // Lock +2 Pips
                  if(newSL > currentSL) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                 }
              }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
              {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               if(openPrice - ask >= InpBEPips * 10 * point)
                 {
                  double newSL = openPrice - (2 * 10 * point); // Lock +2 Pips
                  if(currentSL == 0 || newSL < currentSL) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                 }
              }
           }
        }
     }
  }

int CountPositions()
  {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetTicket(i) > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
        }
     }
   return count;
  }
