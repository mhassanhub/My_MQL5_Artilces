//+------------------------------------------------------------------+
//|                                                ScannerTypes.mqh |
//|          Shared types, helpers and universe construction         |
//+------------------------------------------------------------------+
#ifndef SCANNER_TYPES_MQH
#define SCANNER_TYPES_MQH

//--- where the list of scanned symbols comes from
enum ENUM_UNIVERSE_SOURCE
  {
   UNIVERSE_MARKET_WATCH = 0,   // Market Watch symbols
   UNIVERSE_CUSTOM_LIST  = 1,   // Custom comma-separated list
   UNIVERSE_PATH_FILTER  = 2    // All symbols under a path prefix
  };

//--- sort orders available on the dashboard
enum ENUM_SCAN_SORT
  {
   SCAN_SORT_SCORE     = 0,
   SCAN_SORT_RS_STRONG = 1,
   SCAN_SORT_RS_WEAK   = 2,
   SCAN_SORT_ATR       = 3
  };

//--- settings of one scanner run
struct SScanConfig
  {
   ENUM_TIMEFRAMES   tf;
   int               emaFast;
   int               emaSlow;
   int               emaTrend;
   int               rsiPeriod;
   int               bbPeriod;
   int               atrPeriod;
   double            bbDeviation;
   int               squeezeLookback;
   int               volumeLookback;
   int               rsLookback;
   double            wTrend;
   double            wMomentum;
   double            wRelStrength;
   double            setupWeight;
   double            biasThreshold;
   double            minScore;
   uint              retryMs;
  };

//--- latest evaluated state of one symbol
struct SSnapshot
  {
   string            symbol;
   datetime          barTime;       // open time of the bar that triggered the evaluation
   bool              valid;
   int               direction;     // +1 long, -1 short, 0 neutral
   double            close;
   double            trend;         // -100..+100
   double            momentum;      // -100..+100
   double            squeeze;       // 0..100 volatility compression
   double            volumeSurge;   // 0..100 volume expansion
   double            atrPct;        // ATR as percent of price
   double            retN;          // return over the RS lookback, percent
   double            rsRank;        // 0..100 percentile across the universe
   double            bias;          // -100..+100
   double            score;         // 0..100
  };

//+------------------------------------------------------------------+
//| Sign of a number: +1, -1 or 0                                    |
//+------------------------------------------------------------------+
int SignOf(const double value)
  {
   if(value>0.0)
      return 1;
   if(value<0.0)
      return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Limit a value to the range [lo, hi]                              |
//+------------------------------------------------------------------+
double ClampValue(const double value,const double lo,const double hi)
  {
   if(value<lo)
      return lo;
   if(value>hi)
      return hi;
   return value;
  }

//+------------------------------------------------------------------+
//| Put a snapshot into the empty state                              |
//+------------------------------------------------------------------+
void ResetSnapshot(SSnapshot &s,const string symbol)
  {
   s.symbol=symbol;
   s.barTime=0;
   s.valid=false;
   s.direction=0;
   s.close=0.0;
   s.trend=0.0;
   s.momentum=0.0;
   s.squeeze=0.0;
   s.volumeSurge=0.0;
   s.atrPct=0.0;
   s.retN=0.0;
   s.rsRank=50.0;
   s.bias=0.0;
   s.score=0.0;
  }

//+------------------------------------------------------------------+
//| Is the name already present among the first 'count' items?       |
//+------------------------------------------------------------------+
bool IsInList(const string &list[],const int count,const string name)
  {
   for(int i=0;i<count;i++)
      if(list[i]==name)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Build the list of symbols to scan. Returns the number of names.  |
//+------------------------------------------------------------------+
int BuildUniverse(const ENUM_UNIVERSE_SOURCE source,const string customList,
                  const string pathPrefix,string &result[])
  {
   ArrayResize(result,0);
   int count=0;

   if(source==UNIVERSE_CUSTOM_LIST)
     {
      string parts[];
      const int n=StringSplit(customList,',',parts);
      for(int i=0;i<n;i++)
        {
         string name=parts[i];
         StringTrimLeft(name);
         StringTrimRight(name);
         if(name=="" || IsInList(result,count,name))
            continue;
         if(!SymbolSelect(name,true))
            continue;                      // unknown symbol name
         ArrayResize(result,count+1);
         result[count]=name;
         count++;
        }
      return count;
     }

   const bool marketWatchOnly=(source==UNIVERSE_MARKET_WATCH);
   const int total=SymbolsTotal(marketWatchOnly);
   for(int i=0;i<total;i++)
     {
      const string name=SymbolName(i,marketWatchOnly);
      if(name=="" || IsInList(result,count,name))
         continue;
      if(source==UNIVERSE_PATH_FILTER && pathPrefix!="")
        {
         const string path=SymbolInfoString(name,SYMBOL_PATH);
         if(StringFind(path,pathPrefix)!=0)
            continue;
        }
      if(SymbolInfoInteger(name,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED)
         continue;
      if(!SymbolSelect(name,true))
         continue;
      ArrayResize(result,count+1);
      result[count]=name;
      count++;
     }
   return count;
  }

#endif