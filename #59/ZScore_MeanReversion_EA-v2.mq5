//+------------------------------------------------------------------+
//|                                   ZScore_MeanReversion_EA-v2.mq5 |
//|                                  Copyright 2026, Quant Systems   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
// INCLUDES & GLOBAL PARAMETERS                                      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>                  // Standard MQL5 trading execution library

CTrade trade;                               // Trade object to handle order placement and exits

// Strategy Input Parameters
input int    InpZPeriod     = 20;           // Lookback bars used to calculate rolling mean and std dev
input double InpUpperThresh = 2.0;          // Upper Z-Score threshold to trigger short mean-reversion entries
input double InpLowerThresh = -2.0;         // Lower Z-Score threshold to trigger long mean-reversion entries
input double InpLotSize     = 0.1;          // Fixed position sizing per trade
input ulong  InpMagicNumber = 111001;       // Unique EA identification number to manage orders safely

// Global Variables
int zscore_handle;                          // Stores the memory handle for our custom Z-Score indicator
//+------------------------------------------------------------------+
//| Initialize EA settings and connect indicator handles             |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);                                 // Assign unique magic number to separate our EA's trades

   zscore_handle = iCustom(_Symbol, _Period, "Custom_Z-Score_V2", InpZPeriod); // Bind the compiled custom Z-Score indicator instance
   if(zscore_handle == INVALID_HANDLE)                                         // Verify indicator handle loaded successfully
     {
      Print("Failed to initialize ZScore indicator handle.");                  // Log error to Experts journal if path or handle fails
      return(INIT_FAILED);                                                     // Abort initialization to prevent executing without signals
     }

   return(INIT_SUCCEEDED);                                                     // EA setup completed without issues
  }
//+------------------------------------------------------------------+
//| Release indicator memory allocations on system shutdown          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(zscore_handle);                                            // Clean up memory buffer occupied by the indicator handle
  }
//+------------------------------------------------------------------+
//|  Core strategy execution loop triggered on every price tick      |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Bar-Completion Filter: Prevent intra-bar recalculations and execution churn
   static datetime last_bar_time;                                           // Tracks the open time of the last processed candle
   datetime current_bar_time = iTime(_Symbol, _Period, 0);                  // Fetch opening timestamp of the active candle
   if(current_bar_time == last_bar_time) return;                            // Skip intra-bar tick updates
   last_bar_time = current_bar_time;   

   // Fetch Calculated Indicator Values
   double z_val[];                                                          // Array buffer to hold fetched Z-Score data
   ArraySetAsSeries(z_val, true);                                           // Index 0 represents the most recently completed bar
   if(CopyBuffer(zscore_handle, 0, 1, 2, z_val) < 2)                        // Copy 2 completed bars starting from bar index 1
      return;                                                               // Exit if buffer copy returns insufficient data

   double z_current  = z_val[0];                                            // Z-Score score of the last completed candle (index 1)
   double z_previous = z_val[1];                                            // Z-Score score of the candle prior to last (index 2)

   // Monitor Active Positions
   int total_positions = 0;                                                 // Total open trades belonging to this EA
   bool is_long  = false;                                                   // Track if long position is open
   bool is_short = false;                                                   // Track if short position is open

   for(int i = PositionsTotal() - 1; i >= 0; i--)                           // Loop backward through all open platform positions
     {
      ulong ticket = PositionGetTicket(i);                                  // Select position ticket
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&                   // Ensure position matches current symbol
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)              // Ensure position matches EA magic number
        {
         total_positions++;                                                 // Increment position count for this EA
         long type = PositionGetInteger(POSITION_TYPE);                     // Read position direction
         if(type == POSITION_TYPE_BUY)  is_long  = true;                    // Set active long flag
         if(type == POSITION_TYPE_SELL) is_short = true;                    // Set active short flag
        }
     }

   // Strategy Exits: Take profit when Z-Score reverts back to the mean (0.0)
   if(is_long && z_current >= 0.0)                                          // Long profit target reached mean level
     {
      ClosePositions(POSITION_TYPE_BUY);                                    // Close active buy trade
      is_long = false;                                                      // Reset long flag
     }
   if(is_short && z_current <= 0.0)                                         // Short profit target reached mean level
     {
      ClosePositions(POSITION_TYPE_SELL);                                   // Close active sell trade
      is_short = false;                                                     // Reset short flag
     }

   // Strategy Entries: Buy when recovering from oversold; Sell when cooling from overbought
   if(total_positions == 0)                                                 // Ensure market is clear of existing EA positions
     {
      if(z_previous < InpLowerThresh && z_current >= InpLowerThresh)        // Price re-entered above lower limit (Oversold Recovery)
        {
         trade.Buy(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0, "Z-Score Buy Reversion");
         last_bar_time = current_bar_time;                                  // Lock bar timestamp after execution
        }
      else if(z_previous > InpUpperThresh && z_current <= InpUpperThresh)   // Price re-entered below upper limit (Overbought Recovery)
        {
         trade.Sell(InpLotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0, "Z-Score Sell Reversion");
         last_bar_time = current_bar_time;                                  // Lock bar timestamp after execution
        }
     }
  }
//+------------------------------------------------------------------+
//| Close specific position types filtered by Magic Number and Symbol|
//+------------------------------------------------------------------+
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