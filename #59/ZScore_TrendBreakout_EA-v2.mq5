//+------------------------------------------------------------------+
//|                                      ZScore_Breakout_EA-v2.mq5   |
//|                                  Copyright 2026, Quant Systems   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| INCLUDES & GLOBAL PARAMETERS                                     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>                  // Standard MQL5 trading execution library

CTrade trade;                               // Instantiates global trade management object

// Strategy Input Parameters
input int    InpZPeriod       = 20;         // Rolling lookback window for the statistical calculation
input double InpBreakoutUpper = 2.5;        // Upper deviation threshold to trigger momentum long entries
input double InpBreakoutLower = -2.5;       // Lower deviation threshold to trigger momentum short entries
input double InpExitThreshold = 1.0;        // Exit boundary when expansion momentum cools back down
input double InpLotSize       = 0.1;        // Trade volume allocated per order
input ulong  InpMagicNumber   = 111002;     // EA ticket ID tag for isolated trade management

// Global Variables
int zscore_handle;                          // Memory pointer handle for the custom Z-Score indicator
//+------------------------------------------------------------------+
//| Initialize EA configurations and validate indicator links        |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);                                 // Assign magic number tag to distinguish EA trades

   zscore_handle = iCustom(_Symbol, _Period, "Custom_Z-Score_V2", InpZPeriod); // Bind compiled custom indicator with parameter
   if(zscore_handle == INVALID_HANDLE)                                         // Guard clause to catch path or loading failure
      return(INIT_FAILED);                                                     // Terminate initialization safely

   return(INIT_SUCCEEDED);                                                     // System ready for tick processing
  }
//+------------------------------------------------------------------+
//| Clean up memory handles on EA uninitialization                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(zscore_handle);                                         // Free up memory resources allocated to the handle
  }
//+------------------------------------------------------------------+
//| Main strategy execution handler called on every tick event       |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Bar-Completion Filter: Prevent intra-bar noise and false triggers
   static datetime last_bar_time;                                           // Static variable preserving last processed bar timestamp
   datetime current_bar_time = iTime(_Symbol, _Period, 0);                  // Fetch open timestamp of current candle
   if(current_bar_time == last_bar_time) return;                            // Skip intra-bar tick updates
   last_bar_time = current_bar_time;
   
   // Fetch Calculated Indicator Values
   double z_val[];                                                          // Array buffer for retrieving calculated Z-Score values
   ArraySetAsSeries(z_val, true);                                           // Index 0 set as newest completed bar
   if(CopyBuffer(zscore_handle, 0, 1, 2, z_val) < 2)                       // Pull last 2 completed bars starting from index 1
      return;                                                               // Exit tick cycle if array buffer fails to populate

   double z_current  = z_val[0];                                            // Z-Score score of the most recently closed candle
   double z_previous = z_val[1];                                            // Z-Score score of the candle preceding it

   // Audit Active Positions
   int total_positions = 0;                                                 // Counter for active EA trades
   bool is_long  = false;                                                   // Dynamic state tracking active buy orders
   bool is_short = false;                                                   // Dynamic state tracking active sell orders

   for(int i = PositionsTotal() - 1; i >= 0; i--)                           // Scan open position pool backward
     {
      ulong ticket = PositionGetTicket(i);                                  // Retrieve position ticket handle
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&                   // Confirm position belongs to current instrument
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)              // Confirm position belongs to this EA
        {
         total_positions++;                                                 // Increment open EA positions tally
         long type = PositionGetInteger(POSITION_TYPE);                     // Retrieve trade order direction
         if(type == POSITION_TYPE_BUY)  is_long  = true;                    // Flag active long position state
         if(type == POSITION_TYPE_SELL) is_short = true;                    // Flag active short position state
        }
     }

   // Strategy Exits: Close momentum position when deviation falls below exit line
   if(is_long && z_current < InpExitThreshold)                              // Long momentum exhausted below upper threshold
     {
      ClosePositions(POSITION_TYPE_BUY);                                                     // Flatten open long positions
      is_long = false;                                                      // Reset long state flag
     }
   if(is_short && z_current > -InpExitThreshold)                            // Short momentum exhausted above lower threshold
     {
      ClosePositions(POSITION_TYPE_SELL);                                                     // Flatten open short positions
      is_short = false;                                                     // Reset short state flag
     }

   // Strategy Entries: Execute breakout trades when price surges past statistical boundaries
   if(total_positions == 0)                                                 // Ensure zero open exposure before trade entry
     {
      if(z_previous < InpBreakoutUpper && z_current >= InpBreakoutUpper)    // Upside breakout: Z-Score crosses above +2.5
        {
         trade.Buy(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0, "Z-Breakout Buy");
         last_bar_time = current_bar_time;                                  // Lock timestamp to prevent duplicate entries on bar
        }
      else if(z_previous > InpBreakoutLower && z_current <= InpBreakoutLower) // Downside breakout: Z-Score plunges below -2.5
        {
         trade.Sell(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0, "Z-Breakout Sell");
         last_bar_time = current_bar_time;                                  // Lock timestamp to prevent duplicate entries on bar
        }
     }
  }
//+------------------------------------------------------------------------+
//| Close all active trades associated with this EA magic number and symbol|
//+------------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE pos_type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)                           // Iterate backward through open trades pool
     {
      ulong ticket = PositionGetTicket(i);                                  // Retrieve position ticket index
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&                   // Match current asset symbol
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)              // Match EA's designated magic number
        {
         if(PositionGetInteger(POSITION_TYPE) == pos_type)                  // Filter position direction matching target exit type
            trade.PositionClose(ticket);                                    // Submit order request to close trade ticket
        }
     }
  }
//+------------------------------------------------------------------+