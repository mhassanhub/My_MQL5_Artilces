//+------------------------------------------------------------------+
//|                                                      ZScore.mq5  |
//+------------------------------------------------------------------+
#property indicator_separate_window // Render in a separate window below price
#property indicator_buffers 1       // Total dynamic buffers managed
#property indicator_plots   1       // Number of visible plotted lines
// Define properties for the Z-Score Plot Line
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
input int InpPeriod = 20; // Lookback Period (N) for SMA and Standard Deviation
double ExtZScoreBuffer[];
//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, ExtZScoreBuffer, INDICATOR_DATA);
   PlotIndexSetString(0, PLOT_LABEL, "Z-Score");
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpPeriod);
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   if(InpPeriod <= 1)
     {
      Print("Error: Lookback period must be greater than 1.");
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
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
   if(rates_total < InpPeriod)
      return(0);
   int start = prev_calculated - 1;
   if(start < InpPeriod)
      start = InpPeriod;
   for(int i = start; i < rates_total && !IsStopped(); i++)
     {
      double sum = 0.0;
      for(int j = 0; j < InpPeriod; j++)
        {
         sum += close[i - j];
        }
      double mean = sum / InpPeriod;
      double sum_sq_diff = 0.0;
      for(int j = 0; j < InpPeriod; j++)
        {
         double diff = close[i - j] - mean;
         sum_sq_diff += diff * diff;
        }
      double variance = sum_sq_diff / InpPeriod;
      double std_dev = MathSqrt(variance);
      if(std_dev != 0.0)
         ExtZScoreBuffer[i] = (close[i] - mean) / std_dev;
      else
         ExtZScoreBuffer[i] = 0.0;
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+