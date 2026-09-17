//+------------------------------------------------------------------+
//|                               M1_Scalp_AdvancedSMC_5Layer.mq5    |
//|                               Copyright 2026, Ultimate SMC Bot   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "12.00"

#include <Trade\Trade.mqh>
CTrade trade;

// --- Input Settings ---
input group "--- Settings Layer & Basket Risk ---"
input double   InpLotSize            = 0.01;     // Lot per Entry
input int      InpLayerCount         = 5;        // Dikurangi jadi 5 Layer
input ulong    InpMagicNumber        = 112233;   // Magic Number EA

input group "--- Basket Profit & Cut Loss (TOTAL KESELURUHAN) ---"
input double   InpTotalTargetProfit  = 1.25;     // Target Profit Gabungan 5 Layer (1.25 USC)
input double   InpTotalMaxLoss       = 10.0;     // TOTAL MAX LOSS 5 LAYER (-10 USC TOTAL)

input group "--- SMC & Price Action Settings ---"
input int      InpLookbackCandles    = 30;       // Lookback Candle untuk SnR, SnD, MSS & Base
input double   InpMinFvgPips         = 10.0;     // Celah FVG Minimal (10 Pips)

datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   Print("EA Advanced SMC (MSS, CRT, SnD, RBS, RBR, FVG) Active!");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) {}

void OnTick()
  {
   // 1. Eksekusi Basket Cut Loss (-10 USC TOTAL) atau Basket Profit
   ManageBasketPL();

   // 2. Jeda 5 detik antar transaksi
   if(TimeCurrent() - lastTradeTime < 5) return;

   // 3. Analisis Struktur SMC & Eksekusi Entry 5 Layer
   if(CountPositions() == 0)
     {
      ExecuteAdvancedSMCEntry();
     }
  }

// --- FUNGSI MANAGEMEN TOTAL BASKET LOSS/PROFIT ---
void ManageBasketPL()
  {
   if(CountPositions() == 0) return;

   double totalProfit = 0;

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

   // A. BASKET PROFIT
   if(totalProfit >= InpTotalTargetProfit)
     {
      CloseAllPositions();
      Print("BASKET PROFIT TERCAPAI: ", totalProfit, " USC -> CLOSE ALL!");
      lastTradeTime = TimeCurrent();
     }
   // B. HARD BASKET CUT LOSS (-10 USC TOTAL)
   else if(totalProfit <= -InpTotalMaxLoss)
     {
      CloseAllPositions();
      Print("TOTAL BASKET MINUS MELEBIHI -10 USC (", totalProfit, " USC) -> FAST CUT ALL!");
      lastTradeTime = TimeCurrent();
     }
  }

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

// --- FUNGSI EKSEKUSI ADVANCED SMC ---
void ExecuteAdvancedSMCEntry()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, _Period, 0, InpLookbackCandles, rates) < InpLookbackCandles) return;

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // 1. DETEKSI MSS (Market Structure Shift)
   bool isMSS_Bullish = (rates[0].close > rates[2].high); // Harga tembus High sebelumnya
   bool isMSS_Bearish = (rates[0].close < rates[2].low);  // Harga tembus Low sebelumnya

   // 2. DETEKSI FVG (Fair Value Gap / Imbalance)
   bool isBullishFVG = (rates[0].low - rates[2].high) / (10 * point) >= InpMinFvgPips;
   bool isBearishFVG = (rates[2].low - rates[0].high) / (10 * point) >= InpMinFvgPips;

   // 3. DETEKSI RALLY BASE RALLY (RBR) & DROP BASE DROP (DBD)
   double baseRange = MathAbs(rates[1].high - rates[1].low) / (10 * point);
   bool isBase = baseRange <= 15.0; // Candle kecil (Base)
   bool isRallyBaseRally = (rates[2].close > rates[2].open) && isBase && (rates[0].close > rates[0].open);
   bool isDropBaseDrop   = (rates[2].close < rates[2].open) && isBase && (rates[0].close < rates[0].open);

   // 4. DETEKSI AREA DEMAND, SUPPLY & RBS (Resistance Become Support)
   double demandLevel = rates[1].low;
   double supplyLevel = rates[1].high;

   for(int i = 1; i < InpLookbackCandles; i++)
     {
      if(rates[i].low < demandLevel)   demandLevel = rates[i].low;
      if(rates[i].high > supplyLevel)  supplyLevel = rates[i].high;
     }

   // 5. RETEST / PULLBACK CONFIRMATION
   bool isDemandPullback = (bid - demandLevel) / (10 * point) <= 25.0 && (rates[0].close > rates[0].open);
   bool isSupplyPullback = (supplyLevel - ask) / (10 * point) <= 25.0 && (rates[0].close < rates[0].open);

   // --- SYARAT FINAL ENTRY SMC ---

   // SETUP BUY: (MSS Bullish / RBR / FVG) AND (Retest ke Area Demand / RBS)
   if((isMSS_Bullish || isBullishFVG || isRallyBaseRally) && isDemandPullback)
     {
      Print("SMC BUY Confluence Confirmed (MSS/FVG/RBR + Pullback) -> Tembak 5 BUY!");
      for(int k = 0; k < InpLayerCount; k++)
        {
         trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "SMC Buy Confluence");
        }
      lastTradeTime = TimeCurrent();
     }
   // SETUP SELL: (MSS Bearish / DBD / FVG) AND (Retest ke Area Supply / SBR)
   else if((isMSS_Bearish || isBearishFVG || isDropBaseDrop) && isSupplyPullback)
     {
      Print("SMC SELL Confluence Confirmed (MSS/FVG/DBD + Pullback) -> Tembak 5 SELL!");
      for(int k = 0; k < InpLayerCount; k++)
        {
         trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "SMC Sell Confluence");
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
