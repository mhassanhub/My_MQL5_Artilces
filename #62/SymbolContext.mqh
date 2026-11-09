//+------------------------------------------------------------------+
//|                                                SymbolContext.mqh |
//|    Indicator handle pool, readiness gate and feature extraction  |
//+------------------------------------------------------------------+
#ifndef SYMBOL_CONTEXT_MQH
#define SYMBOL_CONTEXT_MQH

#include "ScannerTypes.mqh"

class CSymbolContext
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_hFast;
   int               m_hSlow;
   int               m_hTrend;
   int               m_hRsi;
   int               m_hAtr;
   int               m_hBands;
   int               m_required;
   datetime          m_lastBar;
   ulong             m_retryAt;

   void              Drop(int &handle);
   bool              Ready(void);
   bool              Defer(const SScanConfig &cfg);
   bool              Fetch(const int handle,const int buffer,const int start,
                           const int count,double &target[]);
public:
                     CSymbolContext(void);
                    ~CSymbolContext(void);
   bool              Init(const string symbol,const SScanConfig &cfg);
   void              Release(void);
   bool              IsDirty(void);
   bool              Evaluate(const SScanConfig &cfg,SSnapshot &out);
  };

//+------------------------------------------------------------------+
CSymbolContext::CSymbolContext(void)
  {
   m_symbol="";
   m_tf=PERIOD_CURRENT;
   m_hFast=INVALID_HANDLE;
   m_hSlow=INVALID_HANDLE;
   m_hTrend=INVALID_HANDLE;
   m_hRsi=INVALID_HANDLE;
   m_hAtr=INVALID_HANDLE;
   m_hBands=INVALID_HANDLE;
   m_required=0;
   m_lastBar=0;
   m_retryAt=0;
  }
//+------------------------------------------------------------------+
CSymbolContext::~CSymbolContext(void)
  {
   Release();
  }
//+------------------------------------------------------------------+
void CSymbolContext::Drop(int &handle)
  {
   if(handle!=INVALID_HANDLE)
     {
      IndicatorRelease(handle);
      handle=INVALID_HANDLE;
     }
  }
//+------------------------------------------------------------------+
void CSymbolContext::Release(void)
  {
   Drop(m_hFast);
   Drop(m_hSlow);
   Drop(m_hTrend);
   Drop(m_hRsi);
   Drop(m_hAtr);
   Drop(m_hBands);
   m_lastBar=0;
   m_retryAt=0;
  }
//+------------------------------------------------------------------+
//| Create all handles once                                          |
//+------------------------------------------------------------------+
bool CSymbolContext::Init(const string symbol,const SScanConfig &cfg)
  {
   Release();
   m_symbol=symbol;
   m_tf=cfg.tf;

   m_hFast =iMA(m_symbol,m_tf,cfg.emaFast,0,MODE_EMA,PRICE_CLOSE);
   m_hSlow =iMA(m_symbol,m_tf,cfg.emaSlow,0,MODE_EMA,PRICE_CLOSE);
   m_hTrend=iMA(m_symbol,m_tf,cfg.emaTrend,0,MODE_EMA,PRICE_CLOSE);
   m_hRsi  =iRSI(m_symbol,m_tf,cfg.rsiPeriod,PRICE_CLOSE);
   m_hAtr  =iATR(m_symbol,m_tf,cfg.atrPeriod);
   m_hBands=iBands(m_symbol,m_tf,cfg.bbPeriod,0,cfg.bbDeviation,PRICE_CLOSE);

   if(m_hFast==INVALID_HANDLE || m_hSlow==INVALID_HANDLE || m_hTrend==INVALID_HANDLE ||
      m_hRsi==INVALID_HANDLE  || m_hAtr==INVALID_HANDLE  || m_hBands==INVALID_HANDLE)
     {
      Release();
      return false;
     }

   //--- the deepest history any calculation needs, plus a safety margin
   int need=cfg.emaTrend;
   need=MathMax(need,cfg.bbPeriod+cfg.squeezeLookback);
   need=MathMax(need,cfg.rsLookback+2);
   need=MathMax(need,cfg.volumeLookback+1);
   need=MathMax(need,cfg.rsiPeriod);
   need=MathMax(need,cfg.atrPeriod);
   m_required=need+10;
   return true;
  }
//+------------------------------------------------------------------+
//| Has the symbol opened a new bar since the last evaluation?       |
//+------------------------------------------------------------------+
bool CSymbolContext::IsDirty(void)
  {
   if(GetTickCount64()<m_retryAt)
      return false;
   const datetime current=iTime(m_symbol,m_tf,0);
   if(current==0)
      return false;                        // history not available yet
   return (current!=m_lastBar);
  }
//+------------------------------------------------------------------+
//| Postpone the symbol and report failure                           |
//+------------------------------------------------------------------+
bool CSymbolContext::Defer(const SScanConfig &cfg)
  {
   m_retryAt=GetTickCount64()+(ulong)cfg.retryMs;
   return false;
  }
//+------------------------------------------------------------------+
//| Is the data synchronized and are all indicators calculated?      |
//+------------------------------------------------------------------+
bool CSymbolContext::Ready(void)
  {
   if(!(bool)SeriesInfoInteger(m_symbol,m_tf,SERIES_SYNCHRONIZED))
      return false;
   if(Bars(m_symbol,m_tf)<m_required)
      return false;
   if(BarsCalculated(m_hFast)<m_required  || BarsCalculated(m_hSlow)<m_required ||
      BarsCalculated(m_hTrend)<m_required || BarsCalculated(m_hRsi)<m_required  ||
      BarsCalculated(m_hAtr)<m_required   || BarsCalculated(m_hBands)<m_required)
      return false;
   return true;
  }
//+------------------------------------------------------------------+
//| Copy a buffer so that index 0 is the bar at shift 'start'        |
//+------------------------------------------------------------------+
bool CSymbolContext::Fetch(const int handle,const int buffer,const int start,
                           const int count,double &target[])
  {
   ArraySetAsSeries(target,true);
   return (CopyBuffer(handle,buffer,start,count,target)==count);
  }
//+------------------------------------------------------------------+
//| Evaluate the last closed bar and fill the per-symbol features    |
//+------------------------------------------------------------------+
bool CSymbolContext::Evaluate(const SScanConfig &cfg,SSnapshot &out)
  {
   const datetime barOpen=iTime(m_symbol,m_tf,0);
   if(barOpen==0 || !Ready())
      return Defer(cfg);

   //--- prices: index 1 is the last closed bar
   double closes[];
   ArraySetAsSeries(closes,true);
   const int closeCount=cfg.rsLookback+2;
   if(CopyClose(m_symbol,m_tf,0,closeCount,closes)!=closeCount)
      return Defer(cfg);
   const double price=closes[1];
   const double past=closes[1+cfg.rsLookback];
   if(price<=0.0 || past<=0.0)
      return Defer(cfg);

   //--- moving averages, RSI, ATR
   double fast[];
   double slow[];
   double trendMa[];
   double rsi[];
   double atr[];
   if(!Fetch(m_hFast,0,1,1,fast) || !Fetch(m_hSlow,0,1,3,slow) ||
      !Fetch(m_hTrend,0,1,1,trendMa) || !Fetch(m_hRsi,0,1,1,rsi) ||
      !Fetch(m_hAtr,0,1,1,atr))
      return Defer(cfg);

   //--- Bollinger width history: 0 = middle, 1 = upper, 2 = lower
   const int bbCount=cfg.squeezeLookback;
   double middle[];
   double upper[];
   double lower[];
   if(!Fetch(m_hBands,0,1,bbCount,middle) || !Fetch(m_hBands,1,1,bbCount,upper) ||
      !Fetch(m_hBands,2,1,bbCount,lower))
      return Defer(cfg);
   if(middle[0]<=0.0)
      return Defer(cfg);
   const double currentWidth=(upper[0]-lower[0])/middle[0];
   int wider=0;
   int samples=0;
   for(int i=1;i<bbCount;i++)
     {
      if(middle[i]<=0.0)
         continue;
      const double width=(upper[i]-lower[i])/middle[i];
      samples++;
      if(width>currentWidth)
         wider++;
     }

   //--- tick volume surge relative to the preceding bars
   const int volCount=cfg.volumeLookback+1;
   long volume[];
   ArraySetAsSeries(volume,true);
   if(CopyTickVolume(m_symbol,m_tf,1,volCount,volume)!=volCount)
      return Defer(cfg);
   double volSum=0.0;
   for(int i=1;i<volCount;i++)
      volSum+=(double)volume[i];
   const double volAvg=volSum/(double)cfg.volumeLookback;
   const double ratio=(volAvg>0.0)?(double)volume[0]/volAvg:1.0;

   //--- publish the features
   out.symbol=m_symbol;
   out.barTime=barOpen;
   out.valid=true;
   out.close=price;
   out.trend=25.0*(double)(SignOf(price-fast[0])+SignOf(fast[0]-slow[0])+
                           SignOf(slow[0]-trendMa[0])+SignOf(slow[0]-slow[2]));
   out.momentum=(rsi[0]-50.0)*2.0;
   out.squeeze=(samples>0)?100.0*(double)wider/(double)samples:0.0;
   out.volumeSurge=ClampValue((ratio-1.0)*50.0,0.0,100.0);
   out.atrPct=100.0*atr[0]/price;
   out.retN=100.0*(price/past-1.0);
   m_lastBar=barOpen;
   return true;
  }

#endif