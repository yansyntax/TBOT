//+------------------------------------------------------------------+
//|                                     AutoCloseProfit_XAUUSD.mq5 |
//|                                  Copyright 2026, Trading System  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

// --- Input Parameters Khusus XAUUSD ---
input group "--- Risk & Entry XAUUSD ---"
input double   InpLotSize         = 0.01;     // Ukuran Lot per Entry
input int      InpMaxEntries      = 5;        // Maksimal Entry Terbuka (Max 5)
input double   InpMinProfitUSD    = 0.50;     // Target Profit Minimal per Order ($)
input ulong    InpMagicNumber     = 777999;   // Magic Number EA XAUUSD

input group "--- Indikator Tren Gold ---"
input int      InpMAPeriod        = 50;       // Period Moving Average (Trend Major)
input int      InpRSIPeriod       = 14;       // Period RSI (Filter Overbought/Oversold)

// --- Global Variables ---
int handleMA;
int handleRSI;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Inisialisasi Indikator MA & RSI
   handleMA  = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   
   if(handleMA == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
     {
      Print("Gagal membuat handle indikator!");
      return(INIT_FAILED);
     }

   Print("EA XAUUSD Auto Close Profit Berhasil Dijalankan.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handleMA);
   IndicatorRelease(handleRSI);
   Print("EA XAUUSD Dihentikan.");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Cek dan Close semua posisi XAUUSD yang sudah mencapai Target Profit
   CloseProfitPositions();

   // 2. Cek apakah total entry masih di bawah batas maksimal (Max 5)
   int currentOpenPositions = CountOpenPositions();
   if(currentOpenPositions < InpMaxEntries)
     {
      CheckAndExecuteEntry();
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Close Posisi XAUUSD jika Profit >= InpMinProfitUSD         |
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
            
            // Tutup posisi jika profit bersih sudah melebihi target minimal ($0.50)
            if(profit >= InpMinProfitUSD)
              {
               trade.PositionClose(ticket);
               Print("XAUUSD Posisi #", ticket, " Profit $", profit, " -> CLOSED!");
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Analisis Sinyal & Re-entry XAUUSD                        |
//+------------------------------------------------------------------+
void CheckAndExecuteEntry()
  {
   double ma[];
   double rsi[];
   double closePrice[];
   
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(closePrice, true);

   if(CopyBuffer(handleMA, 0, 0, 2, ma) < 2) return;
   if(CopyBuffer(handleRSI, 0, 0, 2, rsi) < 2) return;
   if(CopyClose(_Symbol, _Period, 0, 2, closePrice) < 2) return;

   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Sinyal BUY: Harga di atas EMA 50 & RSI > 50 (Tren Naik)
   if(closePrice[0] > ma[0] && rsi[0] > 50)
     {
      if(!HasPositionOfType(POSITION_TYPE_BUY))
        {
         trade.Buy(InpLotSize, _Symbol, currentAsk, 0, 0, "XAUUSD Buy Trend");
         Print("XAUUSD Uptrend Detected -> Entry BUY");
        }
     }
   // Sinyal SELL: Harga di bawah EMA 50 & RSI < 50 (Tren Turun)
   else if(closePrice[0] < ma[0] && rsi[0] < 50)
     {
      if(!HasPositionOfType(POSITION_TYPE_SELL))
        {
         trade.Sell(InpLotSize, _Symbol, currentBid, 0, 0, "XAUUSD Sell Trend");
         Print("XAUUSD Downtrend Detected -> Entry SELL");
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Hitung Jumlah Posisi Terbuka                             |
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
//| Helper: Cek Posisi Aktif                                         |
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
