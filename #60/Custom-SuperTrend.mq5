//+------------------------------------------------------------------+
//|                                            Custom-SuperTrend.mq5 |
//+------------------------------------------------------------------+
#property copyright   "Author: Your Name"
#property link        "https://www.mql5.com"
#property version     "1.00"
#property description "Supertrend: an ATR-based adaptive trend-following line"

#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   1
#property indicator_label1  "Supertrend"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLimeGreen,clrTomato
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input int    InpATRPeriod  = 10;   // ATR period (Wilder smoothing)
input double InpMultiplier = 3.0;  // ATR multiplier (band distance)

//+------------------------------------------------------------------+
//| Indicator buffers                                                |
//+------------------------------------------------------------------+
double g_stBuffer[];      // 0: Supertrend value (plotted)
double g_colorBuffer[];   // 1: colour index (0 = up trend, 1 = down trend)
double g_dirBuffer[];     // 2: direction (+1 up, -1 down)
double g_atrBuffer[];     // 3: Average True Range (Wilder)
double g_trBuffer[];      // 4: True Range
double g_upperBuffer[];   // 5: final upper band
double g_lowerBuffer[];   // 6: final lower band

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpATRPeriod<1 || InpMultiplier<=0.0)                                     // reject invalid inputs
     {
      Print("Supertrend: invalid input parameters");                            // tell the user why
      return(INIT_PARAMETERS_INCORRECT);                                        // stop initialization
     }
   SetIndexBuffer(0,g_stBuffer,INDICATOR_DATA);                                 // plotted line
   SetIndexBuffer(1,g_colorBuffer,INDICATOR_COLOR_INDEX);                       // colour index
   SetIndexBuffer(2,g_dirBuffer,INDICATOR_CALCULATIONS);                        // direction
   SetIndexBuffer(3,g_atrBuffer,INDICATOR_CALCULATIONS);                        // ATR
   SetIndexBuffer(4,g_trBuffer,INDICATOR_CALCULATIONS);                         // true range
   SetIndexBuffer(5,g_upperBuffer,INDICATOR_CALCULATIONS);                      // upper band
   SetIndexBuffer(6,g_lowerBuffer,INDICATOR_CALCULATIONS);                      // lower band
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,InpATRPeriod);                         // skip warm-up bars
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,0.0);                                  // 0.0 = nothing drawn
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);                               // price precision
   IndicatorSetString(INDICATOR_SHORTNAME,"Supertrend");                        // name in data window
   return(INIT_SUCCEEDED);                                                      // indicator is ready
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total<=InpATRPeriod)                                                // not enough bars yet
      return(0);                                                                // nothing calculated
   int start=(prev_calculated>1) ? prev_calculated-1 : 0;                       // recalc last bar only
   for(int i=start;i<rates_total;i++)                                           // walk from old to new
     {
      double prevClose=(i>0) ? close[i-1] : close[i];                           // previous close (current on bar 0)
      g_trBuffer[i]=MathMax(high[i],prevClose)-MathMin(low[i],prevClose);       // true range

      if(i<InpATRPeriod)                                                        // warm-up zone: no ATR yet
        {
         g_atrBuffer[i]=0.0;                                                    // no ATR yet
         g_stBuffer[i]=0.0;                                                     // nothing to draw
         g_colorBuffer[i]=0.0;                                                  // default colour
         g_dirBuffer[i]=0.0;                                                    // no direction
         g_upperBuffer[i]=0.0;                                                  // no upper band
         g_lowerBuffer[i]=0.0;                                                  // no lower band
         continue;                                                              // go to next bar
        }

      if(i==InpATRPeriod-1)                                                       // first ATR value
        {
         double sum=0.0;                                                        // accumulator
         for(int k=0;k<InpATRPeriod;k++)                                       // bars 1..period
            sum+=g_trBuffer[k];                                                 // add true range
         g_atrBuffer[i]=sum/InpATRPeriod;                                       // simple-average seed
        }
      else
        {
         double prevAtr=g_atrBuffer[i-1];                                       // ATR of previous bar
         g_atrBuffer[i]=(prevAtr*(InpATRPeriod-1)+g_trBuffer[i])/InpATRPeriod;  // Wilder
        }

      double hl2=(high[i]+low[i])/2.0;                                          // median price
      double bandWidth=InpMultiplier*g_atrBuffer[i];                            // distance from median
      double basicUpper=hl2+bandWidth;                                          // raw upper band
      double basicLower=hl2-bandWidth;                                          // raw lower band

      if(i==InpATRPeriod)                                                       // first valid bar: initialise
        {
         g_upperBuffer[i]=basicUpper;                                           // seed upper band
         g_lowerBuffer[i]=basicLower;                                           // seed lower band
         g_dirBuffer[i]=(close[i]>=hl2) ? 1.0 : -1.0;                           // start with close vs median
        }
      else
        {
         double prevUpper=g_upperBuffer[i-1];                                   // final upper of last bar
         double prevLower=g_lowerBuffer[i-1];                                   // final lower of last bar

         if(basicUpper<prevUpper || prevClose>prevUpper)                        // tighten, or reset after break
            g_upperBuffer[i]=basicUpper;                                        // accept the new band
         else
            g_upperBuffer[i]=prevUpper;                                         // keep old band (ratchet)

         if(basicLower>prevLower || prevClose<prevLower)                        // raise, or reset after break
            g_lowerBuffer[i]=basicLower;                                        // accept the new band
         else
            g_lowerBuffer[i]=prevLower;                                         // keep old band (ratchet)

         double dir=g_dirBuffer[i-1];                                           // carry previous direction
         if(dir<0.0 && close[i]>g_upperBuffer[i])                               // down trend broken upward
            dir=1.0;                                                            // flip to up trend
         else if(dir>0.0 && close[i]<g_lowerBuffer[i])                          // up trend broken downward
            dir=-1.0;                                                           // flip to down trend
         g_dirBuffer[i]=dir;                                                    // store direction
        }

      if(g_dirBuffer[i]>0.0)                                                    // up trend: line below price
        {
         g_stBuffer[i]=g_lowerBuffer[i];                                        // lower band is the line
         g_colorBuffer[i]=0.0;                                                  // colour 0: green
        }
      else                                                                      // down trend: line above price
        {
         g_stBuffer[i]=g_upperBuffer[i];                                        // upper band is the line
         g_colorBuffer[i]=1.0;                                                  // colour 1: red
        }
     }
   return(rates_total);                                                         // all bars processed
  }