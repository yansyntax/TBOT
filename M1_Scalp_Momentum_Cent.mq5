//+------------------------------------------------------------------+
//|                                  M1_Scalp_Momentum_Cent.mq5      |
//|                               Copyright 2026, Momentum Scalper   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "9.00"

#include <Trade\Trade.mqh>
CTrade trade;

// --- Input Settings ---
input group "--- Layering Settings ---"
input double   InpLotSize         = 0.01;     // Lot per Entry
input int      InpLayerCount      = 6;        // Eksekusi Langsung 6 Layer
input ulong    InpMagicNumber     = 666777;   // Magic Number

input group "--- Profit & Loss Settings (Dalam USC) ---"
input double   InpTargetProfitUSC = 0.20;     // Target Profit (0.10 - 0.30 USC)
input double   InpMaxLossUSC      = 15.0;     // Max Cut Loss (15 USC)

input group "--- Filtering Area Pembalikan ---"
input int      InpCandleMinPips   = 8;        // Minimal panjang Candle M1 (8 Pips)
input int      InpSrDistancePips  = 25;       // Jarak aman dari area SR/Pembalikan (25 Pips)

// Global Variables
datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   Print("EA M1 Momentum Scalper Ready!");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) {}

void OnTick()
  {
   // 1. Kelola Profit (0.20 USC) & Cut Loss (-15 USC)
   ManageOpenPositions();

   // 2. Jeda beberapa detik setelah close sebelum cari entryan baru
   if(TimeCurrent() - lastTradeTime < 5) return;

   // 3. Jika posisi kosong, analisa momentum candle & eksekusi 6 layer
   if(CountPositions() == 0)
     {
      ExecuteMomentumEntry();
     }
  }

// --- Kelola Take Profit & Cut Loss ---
void ManageOpenPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            
            // Profit tercapai (0.10 - 0.30 USC) -> langsung cut
            if(profit >= InpTargetProfitUSC)
              {
               trade.PositionClose(ticket);
               lastTradeTime = TimeCurrent();
              }
            // Tidak running / minus 15 USC -> langsung cut
            else if(profit <= -InpMaxLossUSC)
              {
               trade.PositionClose(ticket);
               lastTradeTime = TimeCurrent();
              }
           }
        }
     }
  }

// --- Analisa Candle & Eksekusi ---
void ExecuteMomentumEntry()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, _Period, 1, 20, rates) < 20) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Hitung Ukuran Candle M1 Terakhir
   double candleBody = MathAbs(rates[0].close - rates[0].open) / point;
   bool isStrongBear = (rates[0].open - rates[0].close) / point >= (InpCandleMinPips * 10);
   bool isStrongBull = (rates[0].close - rates[0].open) / point >= (InpCandleMinPips * 10);

   // Cari titik High & Low tertinggi dalam 20 candle terakhir (Area Pembalikan)
   double highestPrice = rates[0].high;
   double lowestPrice  = rates[0].low;
   for(int i = 1; i < 20; i++)
     {
      if(rates[i].high > highestPrice) highestPrice = rates[i].high;
      if(rates[i].low < lowestPrice)   lowestPrice  = rates[i].low;
     }

   // A. MOMENTUM TURUN (Kuat Bearish & Jarak ke Support Masih Jauh)
   if(isStrongBear && (bid - lowestPrice) > (InpSrDistancePips * 10 * point))
     {
      for(int k = 0; k < InpLayerCount; k++)
        {
         trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Momentum Sell");
        }
      lastTradeTime = TimeCurrent();
     }
   // B. MOMENTUM NAIK (Kuat Bullish & Jarak ke Resistance Masih Jauh)
   else if(isStrongBull && (highestPrice - ask) > (InpSrDistancePips * 10 * point))
     {
      for(int k = 0; k < InpLayerCount; k++)
        {
         trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Momentum Buy");
        }
      lastTradeTime = TimeCurrent();
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
