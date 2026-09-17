//+------------------------------------------------------------------+
//|                                  M1_Scalp_BasketCut_Fixed.mq5    |
//|                               Copyright 2026, Smart Basket Bot   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "10.00"

#include <Trade\Trade.mqh>
CTrade trade;

// --- Input Settings ---
input group "--- Layering Settings ---"
input double   InpLotSize            = 0.01;     // Lot per Entry
input int      InpLayerCount         = 6;        // Eksekusi 6 Layer Sekaligus
input ulong    InpMagicNumber        = 778899;   // Magic Number

input group "--- Basket Profit & Cut Loss (TOTAL KESELURUHAN) ---"
input double   InpTotalTargetProfit  = 1.50;     // Total Profit Gabungan 6 Layer (misal 1.50 USC = @0.25 USC)
input double   InpTotalMaxLoss       = 15.0;     // TOTAL MAKSIMAL RUGI KESELURUHAN 6 LAYER (-15 USC)

input group "--- Filter Area Pantulan (High/Low) ---"
input int      InpLookbackCandles    = 30;       // Cek 30 candle M1 ke belakang
input double   InpBufferPips         = 30.0;     // Jarak aman dari Ujung Pantulan (30 Pips)

datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   Print("EA Basket Cut Loss -15 USC Ready!");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) {}

void OnTick()
  {
   // 1. HITUNG TOTAL PROFIT/LOSS BASKET GABUNGAN 6 LAYER
   ManageBasketPL();

   // 2. Jeda 5 detik setelah close sebelum cari entry baru
   if(TimeCurrent() - lastTradeTime < 5) return;

   // 3. Jika posisi kosong, analisa area pantulan & eksekusi 6 layer
   if(CountPositions() == 0)
     {
      ExecuteSmartEntry();
     }
  }

// --- FUNGSI BASKET CUT LOSS (TOTAL KESELURUHAN LAYER) ---
void ManageBasketPL()
  {
   if(CountPositions() == 0) return;

   double totalProfit = 0;

   // Hitung total akumulasi PnL dari semua layer yang terbuka
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            totalProfit += (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
           }
        }
     }

   // A. JIKA TOTAL KESELURUHAN PROFIT TERCAPAI -> CUT ALL
   if(totalProfit >= InpTotalTargetProfit)
     {
      CloseAllPositions();
      Print("TOTAL BASKET PROFIT TERCAPAI: ", totalProfit, " USC -> CLOSE ALL!");
      lastTradeTime = TimeCurrent();
     }
   // B. JIKA TOTAL KESELURUHAN MINUS MELEBIHI -15 USC -> FAST CUT ALL!
   else if(totalProfit <= -InpTotalMaxLoss)
     {
      CloseAllPositions();
      Print("TOTAL BASKET MINUS MEMBENGKAK: ", totalProfit, " USC -> FAST CUT ALL (-15 USC)!");
      lastTradeTime = TimeCurrent();
     }
  }

// --- FUNGSI CLOSE SELURUH POSISI ---
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            trade.PositionClose(ticket);
           }
        }
     }
  }

// --- FUNGSI ENTRY DENGAN FILTER AREA PANTULAN ---
void ExecuteSmartEntry()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, _Period, 1, InpLookbackCandles, rates) < InpLookbackCandles) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Cari Puncak Teratas (Resistance) & Lembah Terbawah (Support) 30 Candle Terakhir
   double highestHigh = rates[0].high;
   double lowestLow   = rates[0].low;

   for(int i = 1; i < InpLookbackCandles; i++)
     {
      if(rates[i].high > highestHigh) highestHigh = rates[i].high;
      if(rates[i].low < lowestLow)   lowestLow   = rates[i].low;
     }

   bool isCandleBull = rates[0].close > rates[0].open;
   bool isCandleBear = rates[0].close < rates[0].open;

   double distToResistance = (highestHigh - ask) / (10 * point); // Pips ke puncak
   double distToSupport    = (bid - lowestLow) / (10 * point);   // Pips ke lembah

   // A. BUY: Hanya jika candle hijau DAN posisi harga masih JAUH dari Puncak Pantulan Atas (> 30 pips)
   if(isCandleBull && distToResistance > InpBufferPips)
     {
      Print("Posisi Aman dari Puncak (Jarak: ", distToResistance, " Pips) -> Tembak 6 BUY");
      for(int k = 0; k < InpLayerCount; k++)
        {
         trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Basket Buy");
        }
      lastTradeTime = TimeCurrent();
     }
   // B. SELL: Hanya jika candle merah DAN posisi harga masih JAUH dari Lembah Pantulan Bawah (> 30 pips)
   else if(isCandleBear && distToSupport > InpBufferPips)
     {
      Print("Posisi Aman dari Lembah (Jarak: ", distToSupport, " Pips) -> Tembak 6 SELL");
      for(int k = 0; k < InpLayerCount; k++)
        {
         trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Basket Sell");
        }
      lastTradeTime = TimeCurrent();
     }
   else
     {
      // Terdeteksi Dekat Area Pantulan -> TAHAN ENTRY
      Print("Harga Dekat Area Pantulan Atas/Bawah -> DIBATALKAN (Anti Keseret)");
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
