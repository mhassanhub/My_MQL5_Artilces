//+------------------------------------------------------------------+
//|                                  ZScore_TrendFilter_EA-v2.mq5    |
//|                                  Copyright 2026, Quant Systems   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Structuring core inputs, strategy thresholds, and trade handles  |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>                  // Standard MQL5 trade execution library

CTrade trade;                               // Global CTrade instance for order routing

// Strategy Input Parameters
input int    InpZPeriod      = 20;          // Lookback period for Z-Score statistical window
input int    InpEMAPeriod    = 200;         // Baseline EMA period used to determine overall macro trend
input double InpBuyPullback  = -1.5;        // Z-Score threshold to trigger long entry in an uptrend
input double InpSellPullback = 1.5;         // Z-Score threshold to trigger short entry in a downtrend
input double InpLotSize      = 0.1;         // Fixed lot sizing allocated per order execution
input ulong  InpMagicNumber  = 111003;      // Unique identifier tag to manage position allocation

// Global Handles
int zscore_handle;                          // Custom Z-Score indicator pointer handle
int ema_handle;                             // Moving Average indicator pointer handle
//+----------------------------------------------------------------------+
//| Initialization sequence to configure magic number and indicator links|
//+----------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);                               // Assign magic number tag to isolate trades

   // Load indicator handles for runtime data fetching
   zscore_handle = iCustom(_Symbol, _Period, "Custom_Z-Score_V2", InpZPeriod);
   ema_handle    = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   // Validate handle creation to prevent runtime errors
   if(zscore_handle == INVALID_HANDLE || ema_handle == INVALID_HANDLE)
     {
      Print("Failed to load indicator handles.");                            // Log error to Experts journal
      return(INIT_FAILED);                                                   // Abort initialization safely
     }

   return(INIT_SUCCEEDED);                                                   // Setup successfully verified
  }
//+------------------------------------------------------------------+
//| Clean-up routine to release allocated indicator handles on remove|
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(zscore_handle);                                         // Free custom indicator memory
   IndicatorRelease(ema_handle);                                            // Free EMA indicator memory allocation
  }
//+------------------------------------------------------------------+
//| Core strategy execution loop triggered on every price quote tick |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Bar-Completion Control: Restrict strategy evaluation to closed candles
   static datetime last_bar_time;                                           // Persistent timestamp tracker
   datetime current_bar_time = iTime(_Symbol, _Period, 0);                  // Obtain current candle open time
   if(current_bar_time == last_bar_time) return;                            // Skip intra-bar tick updates
   last_bar_time = current_bar_time;

   // Buffer Setup and Data Retrieval
   double z_val[];                                                          // Array buffer for Z-Score readings
   double ema_val[];                                                        // Array buffer for EMA baseline
   double close_val[];                                                      // Array buffer for historical close prices

   ArraySetAsSeries(z_val, true);                                           // Reverse index ordering (0 = newest closed)
   ArraySetAsSeries(ema_val, true);
   ArraySetAsSeries(close_val, true);

   // Copy calculated indicator and bar values into local buffers
   if(CopyBuffer(zscore_handle, 0, 1, 2, z_val) < 2) return;                 // Read last 2 closed Z-Score values
   if(CopyBuffer(ema_handle, 0, 1, 1, ema_val) < 1) return;                  // Read latest closed EMA value
   if(CopyClose(_Symbol, _Period, 1, 1, close_val) < 1) return;              // Read latest closed price bar

   double z_current   = z_val[0];                                            // Most recently completed candle Z-Score
   double z_previous  = z_val[1];                                            // Candle preceding the most recent closed
   double current_ema = ema_val[0];                                          // Current EMA trendline value
   double close_price = close_val[0];                                        // Closed price of the evaluated bar

   // Audit Existing EA Positions
   int total_positions = 0;                                                 // Counter for active positions owned by EA
   bool is_long  = false;                                                   // Flag tracking active buy state
   bool is_short = false;                                                   // Flag tracking active sell state

   for(int i = PositionsTotal() - 1; i >= 0; i--)                           // Scan active platform positions backwards
     {
      ulong ticket = PositionGetTicket(i);                                  // Retrieve order ticket ID
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&                   // Verify current chart symbol matches
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)              // Verify EA magic number matches
        {
         total_positions++;                                                 // Increment position counter
         long type = PositionGetInteger(POSITION_TYPE);                     // Retrieve position direction
         if(type == POSITION_TYPE_BUY)  is_long  = true;                    // Long trade active
         if(type == POSITION_TYPE_SELL) is_short = true;                    // Short trade active
        }
     }

   // Dynamic Position Exits: Take profit when reversion reaches opposite boundary
   if(is_long && z_current >= 1.0)                                          // Long profit target reached (+1.0 standard dev)
     {
      ClosePositions(POSITION_TYPE_BUY);                                                     // Exit active long positions
      is_long = false;                                                      // Reset state flag
     }
   if(is_short && z_current <= -1.0)                                        // Short profit target reached (-1.0 standard dev)
     {
      ClosePositions(POSITION_TYPE_SELL);                                                     // Exit active short positions
      is_short = false;                                                     // Reset state flag
     }

   // Strategy Entry Logic: Trend-aligned pullback execution
   if(total_positions == 0)                                                 // Confirm no exposure before entering
     {
      // Long Entry: Macro Uptrend (Price > 200 EMA) + Oversold Pullback Rebound (Z-Score crosses back above -1.5)
      if(close_price > current_ema && z_previous < InpBuyPullback && z_current >= InpBuyPullback)
        {
         trade.Buy(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0, "Z-Trend Pullback Buy");
         last_bar_time = current_bar_time;                                  // Lock bar time to prevent double entry
        }
      // Short Entry: Macro Downtrend (Price < 200 EMA) + Overbought Pullback Rebound (Z-Score crosses back below +1.5)
      else if(close_price < current_ema && z_previous > InpSellPullback && z_current <= InpSellPullback)
        {
         trade.Sell(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0, "Z-Trend Pullback Sell");
         last_bar_time = current_bar_time;                                  // Lock bar time to prevent double entry
        }
     }
  }
//+-------------------------------------------------------------------+
//| Iterates and flattens all open positions matching symbol and magic|
//+-------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE pos_type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)                           // Loop through open positions in reverse order
     {
      ulong ticket = PositionGetTicket(i);                                  // Read position ticket number
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&                   // Ensure symbol matches current chart
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&              // Ensure magic number matches EA instance
	 PositionGetInteger(POSITION_TYPE) == pos_type)
        {
         trade.PositionClose(ticket);                                       // Execute position closure
        }
     }
  }
//+------------------------------------------------------------------+