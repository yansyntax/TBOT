//+------------------------------------------------------------------+
//|                                AutoClose_SmartTrend_XAUUSD.mq5   |
//|                                Copyright 2026, Smart Gold Bot    |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "2.00"

#include <Trade\Trade.mqh>
CTrade trade;

// --- Input Parameters ---
input group "--- Risk & Lot Settings ---"
input double   InpLotSize         = 0.01;     // Ukuran Lot
input int      InpMaxEntries      = 5;        // Maksimal Entry Terbuka
input ulong    InpMagicNumber     = 888111;   // Magic Number EA

input group "--- Protection & Cut Loss (in Points/Pips) ---"
input int      InpStopLoss        = 200;      // Cut Loss / Stop Loss (200 Pts = 20 Pips)
input int      InpTakeProfit      = 200;      // Target Profit (200 Pts = 20 Pips)
input int      InpTrailingStart   = 100;      // Jarak Aktifkan SL+ (100 Pts = 10 Pips)
input int      InpTrailingStop    = 50;       // Jarak Pengunci SL+ (50 Pts = 5 Pips)

input group "--- Trend Indicator Settings ---"
input int      InpMAPeriod        = 50;       // Moving Average Period
input int      InpMACDFast        = 12;       // MACD Fast EMA
input int      InpMACDSlow        = 26;       // MACD Slow EMA
input int      InpMACDSignal      = 9;        // MACD Signal Period

// --- Global Handles ---
int handleMA;
int handleMACD;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   handleMA   = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleMACD = iMACD(_Symbol, _Period, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   
   if(handleMA == INVALID_HANDLE || handleMACD == INVALID_HANDLE)
     {
      Print("Gagal inisialisasi Indikator!");
      return(INIT_FAILED);
     }

   Print("EA Smart Trend XAUUSD dengan Protection 20 Pips Berhasil Aktif.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handleMA);
   IndicatorRelease(handleMACD);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Kelola Trailing Stop / SL+ untuk mengunci profit yang sedang running
   ApplyTrailingStop();

   // 2. Jika total posisi masih kurang dari batas max (5 entry), cari setup entry baru
   if(CountOpenPositions() < InpMaxEntries)
     {
      CheckAndExecuteEntry();
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Eksekusi Entry Berdasarkan Tren EMA + MACD                |
//+------------------------------------------------------------------+
void CheckAndExecuteEntry()
  {
   double ma[];
   double macdMain[], macdSignal[];
   double closePrice[];
   
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   ArraySetAsSeries(closePrice, true);

   if(CopyBuffer(handleMA, 0, 0, 2, ma) < 2) return;
   if(CopyBuffer(handleMACD, MAIN_LINE, 0, 2, macdMain) < 2) return;
   if(CopyBuffer(handleMACD, SIGNAL_LINE, 0, 2, macdSignal) < 2) return;
   if(CopyClose(_Symbol, _Period, 0, 2, closePrice) < 2) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // SENYAL BUY: Harga di atas EMA 50 & MACD Histogram di atas Signal Line
   if(closePrice[0] > ma[0] && macdMain[0] > macdSignal[0])
     {
      if(!HasPositionOfType(POSITION_TYPE_BUY))
        {
         double sl = ask - (InpStopLoss * point);   // Auto Cut Loss 20 Pips
         double tp = ask + (InpTakeProfit * point); // Auto Take Profit 20 Pips
         
         trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "Smart Buy XAUUSD");
         Print("Setup BUY Terdeteksi. Entry BUY dipasang dengan SL 20 Pips!");
        }
     }
   // SENYAL SELL: Harga di bawah EMA 50 & MACD Histogram di bawah Signal Line
   else if(closePrice[0] < ma[0] && macdMain[0] < macdSignal[0])
     {
      if(!HasPositionOfType(POSITION_TYPE_SELL))
        {
         double sl = bid + (InpStopLoss * point);   // Auto Cut Loss 20 Pips
         double tp = bid - (InpTakeProfit * point); // Auto Take Profit 20 Pips
         
         trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "Smart Sell XAUUSD");
         Print("Setup SELL Terdeteksi. Entry SELL dipasang dengan SL 20 Pips!");
        }
     }
  }

//+------------------------------------------------------------------+
//| Fungsi Trailing Stop / SL+ (Kunci Profit)                        |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            double currentSL = PositionGetDouble(POSITION_SL);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
              {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               // Jika profit sudah melebahi TrailingStart (10 pips)
               if(bid - openPrice > InpTrailingStart * point)
                 {
                  double newSL = bid - (InpTrailingStop * point);
                  if(newSL > currentSL)
                    {
                     trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                     Print("Posisi BUY #", ticket, " SL digeser ke SL+ untuk kunci profit!");
                    }
                 }
              }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
              {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               // Jika profit sudah melebihi TrailingStart (10 pips)
               if(openPrice - ask > InpTrailingStart * point)
                 {
                  double newSL = ask + (InpTrailingStop * point);
                  if(currentSL == 0 || newSL < currentSL)
                    {
                     trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                     Print("Posisi SELL #", ticket, " SL digeser ke SL+ untuk kunci profit!");
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
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
            count++;
        }
     }
   return count;
  }

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
