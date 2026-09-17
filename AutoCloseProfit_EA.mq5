//+------------------------------------------------------------------+
//|                                           AutoCloseProfit_EA.mq5 |
//|                                  Copyright 2026, Trading System  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

// --- Input Parameters ---
input group "--- Risk & Entry Settings ---"
input double   InpLotSize         = 0.01;     // Ukuran Lot per Entry
input int      InpMaxEntries      = 5;        // Maksimal Entry Terbuka
input ulong    InpMagicNumber     = 998877;   // Magic Number EA

input group "--- Trend Indicator Settings ---"
input int      InpMAPeriod        = 20;       // Period Moving Average (Trend Detector)
input ENUM_MA_METHOD InpMAMethod  = MODE_SMA; // Tipe Moving Average

// --- Global Variables ---
int handleMA;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Inisialisasi Indikator Moving Average untuk Filter Tren
   handleMA = iMA(_Symbol, _Period, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   if(handleMA == INVALID_HANDLE)
     {
      Print("Gagal membuat handle indikator MA!");
      return(INIT_FAILED);
     }

   Print("EA MT5 Auto Close Profit & Re-Entry Berhasil Dijalankan.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handleMA);
   Print("EA Dihentikan.");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Cek dan Close semua posisi yang sedang Running Profit
   CloseProfitPositions();

   // 2. Jika tidak ada posisi running yang berlebih, cari sinyal Re-Entry
   int currentOpenPositions = CountOpenPositions();
   if(currentOpenPositions < InpMaxEntries)
     {
      CheckAndExecuteEntry();
     }
  }

//+------------------------------------------------------------------+
//| Fungsi untuk Menutup Posisi yang Running Profit                  |
//+------------------------------------------------------------------+
void CloseProfitPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            
            // Jika running profit lebih besar dari 0 (plus), langsung CLOSE
            if(profit > 0.0)
              {
               trade.PositionClose(ticket);
               Print("Posisi #", ticket, " running profit $", profit, " -> BERHASIL DICLOSE!");
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Fungsi untuk Mengukur Tren dan Membuka Posisi Baru (Re-entry)   |
//+------------------------------------------------------------------+
void CheckAndExecuteEntry()
  {
   double ma[];
   double closePrice[];
   
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(closePrice, true);

   if(CopyBuffer(handleMA, 0, 0, 2, ma) < 2) return;
   if(CopyClose(_Symbol, _Period, 0, 2, closePrice) < 2) return;

   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Jika Harga Running di ATAS Indikator MA -> Sinyal UPTREND (BUY)
   if(closePrice[0] > ma[0])
     {
      // Pastikan belum ada posisi BUY yang baru saja terbuka di tick ini
      if(!HasPositionOfType(POSITION_TYPE_BUY))
        {
         trade.Buy(InpLotSize, _Symbol, currentAsk, 0, 0, "Join Trend Buy");
         Print("Sinyal Naik / Uptrend Detected -> Entry BUY");
        }
     }
   // Jika Harga Running di BAWAH Indikator MA -> Sinyal DOWNTREND (SELL)
   else if(closePrice[0] < ma[0])
     {
      // Pastikan belum ada posisi SELL yang baru saja terbuka di tick ini
      if(!HasPositionOfType(POSITION_TYPE_SELL))
        {
         trade.Sell(InpLotSize, _Symbol, currentBid, 0, 0, "Join Trend Sell");
         Print("Sinyal Turun / Downtrend Detected -> Entry SELL");
        }
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Helper: Hitung Total Posisi Terbuka                       |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetTicket(i) > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            count++;
           }
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Fungsi Helper: Cek Jenis Posisi                                  |
//+------------------------------------------------------------------+
bool HasPositionOfType(ENUM_POSITION_TYPE type)
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetTicket(i) > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            if(PositionGetInteger(POSITION_TYPE) == type)
              return true;
           }
        }
     }
   return false;
  }
//+------------------------------------------------------------------+