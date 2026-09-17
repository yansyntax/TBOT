//+------------------------------------------------------------------+
//|                               M5_Scalp_AdvancedSMC_5Layer.mq5    |
//|                               Copyright 2026, Ultimate SMC Bot   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "13.00"

#include <Trade\Trade.mqh>
CTrade trade;

// --- Input Settings ---
input group "--- Settings Layer & Basket Risk ---"
input double   InpLotSize            = 0.01;     // Lot per Entry
input int      InpLayerCount         = 5;        // 5 Layer Instant Execution
input ulong    InpMagicNumber        = 554433;   // Magic Number EA

input group "--- Basket Profit & Cut Loss (TOTAL KESELURUHAN) ---"
input double   InpTotalTargetProfit  = 1.50;     // Target Profit Gabungan 5 Layer (1.50 USC)
input double   InpTotalMaxLoss       = 10.0;     // TOTAL MAX LOSS 5 LAYER (-10 USC TOTAL)

input group "--- SMC & Price Action Settings (M5 Optimized) ---"
input int      InpLookbackCandles    = 24;       // Lookback 24 Candle M5 (2 Jam Terakhir)
input double   InpMinFvgPips         = 15.0;     // Celah FVG Minimal M5 (15 Pips)

datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   Print("EA Advanced SMC M5 (5 Layer & Hard Cut -10 USC) Active!");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) {}

void OnTick()
  {
   // 1. Monitor Basket PnL: Hard Cut All (-10 USC) / Take Profit All
   ManageBasketPL();

   // 2. Jeda 10 detik antar siklus
   if(TimeCurrent() - lastTradeTime < 10) return;

   // 3. Analisis SMC di M5 & Eksekusi 5 Layer
   if(CountPositions() == 0)
     {
      ExecuteM5SMCEntry();
     }
  }

// --- FUNGSI MANAGEMENT TOTAL BASKET LOSS/PROFIT ---
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
      Print("M5 BASKET PROFIT TERCAPAI: ", totalProfit, " USC -> CLOSE ALL!");
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

// --- FUNGSI ANALISIS SMC KHUSUS M5 ---
void ExecuteM5SMCEntry()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, _Period, 0, InpLookbackCandles, rates) < InpLookbackCandles) return;

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // 1. DETEKSI MSS (Market Structure Shift M5)
   bool isMSS_Bullish = (rates[0].close > rates[2].high); 
   bool isMSS_Bearish = (rates[0].close < rates[2].low);  

   // 2. DETEKSI FVG (Fair Value Gap M5)
   bool isBullishFVG = (rates[0].low - rates[2].high) / (10 * point) >= InpMinFvgPips;
   bool isBearishFVG = (rates[2].low - rates[0].high) / (10 * point) >= InpMinFvgPips;

   // 3. DETEKSI RALLY BASE RALLY (RBR) & DROP BASE DROP (DBD)
   double baseRange = MathAbs(rates[1].high - rates[1].low) / (10 * point);
   bool isBase = baseRange <= 20.0; 
   bool isRallyBaseRally = (rates[2].close > rates[2].open) && isBase && (rates[0].close > rates[0].open);
   bool isDropBaseDrop   = (rates[2].close < rates[2].open) && isBase && (rates[0].close < rates[0].open);

   // 4. DEMAND & SUPPLY LEVEL M5
   double demandLevel = rates[1].low;
   double supplyLevel = rates[1].high;

   for(int i = 1; i < InpLookbackCandles; i++)
     {
      if(rates[i].low < demandLevel)   demandLevel = rates[i].low;
      if(rates[i].high > supplyLevel)  supplyLevel = rates[i].high;
     }

   // 5. RETEST / PULLBACK CONFIRMATION M5
   bool isDemandPullback = (bid - demandLevel) / (10 * point) <= 30.0 && (rates[0].close > rates[0].open);
   bool isSupplyPullback = (supplyLevel - ask) / (10 * point) <= 30.0 && (rates[0].close < rates[0].open);

   // --- EKSEKUSI FINAL SETUP M5 ---

   // SETUP BUY M5
   if((isMSS_Bullish || isBullishFVG || isRallyBaseRally) && isDemandPullback)
     {
      Print("M5 SMC BUY Confirmed -> Tembak 5 BUY!");
      for(int k = 0; k < InpLayerCount; k++)
        {
         trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "M5 SMC Buy");
        }
      lastTradeTime = TimeCurrent();
     }
   // SETUP SELL M5
   else if((isMSS_Bearish || isBearishFVG || isDropBaseDrop) && isSupplyPullback)
     {
      Print("M5 SMC SELL Confirmed -> Tembak 5 SELL!");
      for(int k = 0; k < InpLayerCount; k++)
        {
         trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "M5 SMC Sell");
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
