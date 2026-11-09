//+------------------------------------------------------------------+
//|                                              MarketScannerEA.mq5 |
//|        Multi-asset technical scanner with cross-sectional rank   |
//+------------------------------------------------------------------+
#property copyright   "Market Scanner Made Easy"
#property version     "1.00"
#property description "Multi-asset technical scanner with cross-sectional ranking."
#property description "Analysis only: the program never places or modifies trades."

#include <myFiles\MarketScanner\ScannerEngine.mqh>
#include <myFiles\MarketScanner\ScannerPanel.mqh>

input group "Universe"
input ENUM_UNIVERSE_SOURCE InpUniverse           = UNIVERSE_MARKET_WATCH;   // Symbol source
input string               InpCustomList         = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,USDCHF,NZDUSD,XAUUSD"; // Custom list
input string               InpPathPrefix         = "Forex";                 // Path prefix

input group "Indicators"
input ENUM_TIMEFRAMES      InpTimeframe          = PERIOD_H1;               // Scan timeframe
input int                  InpFastEma            = 20;                      // Fast EMA
input int                  InpSlowEma            = 50;                      // Slow EMA
input int                  InpTrendEma           = 200;                     // Trend EMA
input int                  InpRsiPeriod          = 14;                      // RSI period
input int                  InpBbPeriod           = 20;                      // Bollinger period
input double               InpBbDeviation        = 2.0;                     // Bollinger deviation
input int                  InpAtrPeriod          = 14;                      // ATR period
input int                  InpSqueezeLookback    = 100;                     // Compression lookback (bars)
input int                  InpVolumeLookback     = 20;                      // Volume average (bars)
input int                  InpRsLookback         = 48;                      // Relative strength lookback (bars)

input group "Scoring"
input double               InpWeightTrend        = 0.40;                    // Weight: trend
input double               InpWeightMomentum     = 0.30;                    // Weight: momentum
input double               InpWeightRelStrength  = 0.30;                    // Weight: relative strength
input double               InpSetupWeight        = 0.30;                    // Share of setup quality in score
input double               InpBiasThreshold      = 35.0;                    // Bias needed for a direction
input double               InpMinScore           = 50.0;                    // Score needed for an alert

input group "Engine"
input int                  InpTimerMs            = 200;                     // Timer period (ms)
input int                  InpBudgetMs           = 40;                      // Time budget per step (ms)
input int                  InpRetrySeconds       = 15;                      // Retry delay for unready symbols (s)

input group "Dashboard"
input int                  InpRows               = 15;                      // Visible rows (5-40)
input int                  InpPanelX             = 10;                      // Panel X
input int                  InpPanelY             = 20;                      // Panel Y

input group "Output"
input bool                 InpPopupAlerts        = true;                    // Popup alerts
input bool                 InpPushAlerts         = false;                   // Push notifications
input bool                 InpExportCsv          = false;                   // Export CSV
input int                  InpExportSeconds      = 60;                      // Minimum seconds between exports

CMarketScanner  g_scanner;
CScannerPanel   g_panel;
ENUM_TIMEFRAMES g_tf=PERIOD_H1;
ulong           g_evaluations=0;
ulong           g_lastStepUs=0;
ulong           g_lastExport=0;

//+------------------------------------------------------------------+
bool ValidateInputs(void)
  {
   if(InpFastEma<2 || InpSlowEma<=InpFastEma || InpTrendEma<=InpSlowEma)
     {
      Print("MarketScanner: EMA periods must satisfy 2 <= fast < slow < trend");
      return false;
     }
   if(InpRsiPeriod<2 || InpAtrPeriod<1 || InpBbPeriod<2 || InpBbDeviation<=0.0)
     {
      Print("MarketScanner: invalid RSI, ATR or Bollinger parameters");
      return false;
     }
   if(InpSqueezeLookback<5 || InpVolumeLookback<2 || InpRsLookback<1)
     {
      Print("MarketScanner: invalid lookback length");
      return false;
     }
   if(InpWeightTrend<0.0 || InpWeightMomentum<0.0 || InpWeightRelStrength<0.0 ||
      InpWeightTrend+InpWeightMomentum+InpWeightRelStrength<=0.0)
     {
      Print("MarketScanner: weights must be non-negative and not all zero");
      return false;
     }
   if(InpSetupWeight<0.0 || InpSetupWeight>1.0)
     {
      Print("MarketScanner: the setup weight must be between 0 and 1");
      return false;
     }
   if(InpTimerMs<10 || InpBudgetMs<1 || InpRetrySeconds<1 || InpExportSeconds<1)
     {
      Print("MarketScanner: invalid timer, budget, retry or export setting");
      return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
void BuildConfig(SScanConfig &cfg)
  {
   cfg.tf=g_tf;
   cfg.emaFast=InpFastEma;
   cfg.emaSlow=InpSlowEma;
   cfg.emaTrend=InpTrendEma;
   cfg.rsiPeriod=InpRsiPeriod;
   cfg.bbPeriod=InpBbPeriod;
   cfg.atrPeriod=InpAtrPeriod;
   cfg.bbDeviation=InpBbDeviation;
   cfg.squeezeLookback=InpSqueezeLookback;
   cfg.volumeLookback=InpVolumeLookback;
   cfg.rsLookback=InpRsLookback;
   cfg.wTrend=InpWeightTrend;
   cfg.wMomentum=InpWeightMomentum;
   cfg.wRelStrength=InpWeightRelStrength;
   cfg.setupWeight=InpSetupWeight;
   cfg.biasThreshold=InpBiasThreshold;
   cfg.minScore=InpMinScore;
   cfg.retryMs=(uint)(InpRetrySeconds*1000);
  }
//+------------------------------------------------------------------+
string StatusText(void)
  {
   return StringFormat("%s | universe %d | ranked %d | evaluations %I64u | last step %.2f ms | sort %s",
                       StringSubstr(EnumToString(g_tf),7),
                       g_scanner.Count(),
                       g_scanner.Ranked(),
                       g_evaluations,
                       (double)g_lastStepUs/1000.0,
                       EnumToString(g_scanner.SortKey()));
  }
//+------------------------------------------------------------------+
void FlushAlerts(void)
  {
   const int total=g_scanner.AlertCount();
   for(int i=0;i<total;i++)
     {
      const string text=g_scanner.AlertAt(i);
      Print("Scanner: ",text);
      if(InpPopupAlerts)
         Alert(text);
      if(InpPushAlerts)
         SendNotification(text);
     }
   g_scanner.ClearAlerts();
  }
//+------------------------------------------------------------------+
void ExportCsv(void)
  {
   const string fileName="MarketScanner_"+StringSubstr(EnumToString(g_tf),7)+".csv";
   const int handle=FileOpen(fileName,FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("MarketScanner: cannot open %s (error %d)",fileName,GetLastError());
      return;
     }
   FileWrite(handle,"Rank","Symbol","Direction","Score","Bias","Trend","Momentum",
             "RS_Percentile","Return_Pct","Squeeze","VolumeSurge","ATR_Pct","BarTime");
   const int total=g_scanner.Ranked();
   for(int r=0;r<total;r++)
     {
      SSnapshot s;
      if(!g_scanner.Row(r,s))
         continue;
      FileWrite(handle,r+1,s.symbol,s.direction,
                DoubleToString(s.score,2),DoubleToString(s.bias,2),
                DoubleToString(s.trend,0),DoubleToString(s.momentum,2),
                DoubleToString(s.rsRank,2),DoubleToString(s.retN,3),
                DoubleToString(s.squeeze,1),DoubleToString(s.volumeSurge,1),
                DoubleToString(s.atrPct,3),TimeToString(s.barTime,TIME_DATE|TIME_MINUTES));
     }
   FileClose(handle);
  }
//+------------------------------------------------------------------+
//| Bring an existing chart to the front or open a new one           |
//+------------------------------------------------------------------+
void OpenSymbolChart(const string symbol,const ENUM_TIMEFRAMES tf)
  {
   long id=ChartFirst();
   while(id>=0)
     {
      if(ChartSymbol(id)==symbol && ChartPeriod(id)==tf)
        {
         ChartSetInteger(id,CHART_BRING_TO_TOP,true);
         return;
        }
      id=ChartNext(id);
     }
   if(ChartOpen(symbol,tf)==0)
      PrintFormat("MarketScanner: cannot open a chart for %s (error %d)",symbol,GetLastError());
  }
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_tf=(InpTimeframe==PERIOD_CURRENT)?(ENUM_TIMEFRAMES)_Period:InpTimeframe;
   g_evaluations=0;
   g_lastStepUs=0;
   g_lastExport=0;

   SScanConfig cfg;
   BuildConfig(cfg);

   string symbols[];
   const int total=BuildUniverse(InpUniverse,InpCustomList,InpPathPrefix,symbols);
   if(total<2)
     {
      PrintFormat("MarketScanner: the universe needs at least two symbols, found %d",total);
      return INIT_FAILED;
     }
   if(!g_scanner.Init(cfg,symbols,total,(uint)InpBudgetMs))
      return INIT_FAILED;

   const int rows=(int)ClampValue((double)InpRows,5.0,40.0);
   if(!g_panel.Create("MSX"+IntegerToString(ChartID())+"_",InpPanelX,InpPanelY,rows))
     {
      g_panel.Destroy();
      g_scanner.Shutdown();
      return INIT_FAILED;
     }
   g_panel.Update(g_scanner,"Scanning...");

   if(!EventSetMillisecondTimer(InpTimerMs))
     {
      g_panel.Destroy();
      g_scanner.Shutdown();
      return INIT_FAILED;
     }
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_panel.Destroy();
   g_scanner.Shutdown();
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
void OnTimer()
  {
   const ulong started=GetMicrosecondCount();
   const int evaluated=g_scanner.Step();
   g_lastStepUs=GetMicrosecondCount()-started;
   g_evaluations+=(ulong)evaluated;

   if(!g_scanner.ConsumeChanged())
      return;

   g_panel.Update(g_scanner,StatusText());
   FlushAlerts();
   if(InpExportCsv && GetTickCount64()-g_lastExport>=(ulong)(InpExportSeconds*1000))
     {
      ExportCsv();
      g_lastExport=GetTickCount64();
     }
  }
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK)
      return;

   int row=-1;
   const ENUM_PANEL_HIT hit=g_panel.Hit(sparam,row);
   switch(hit)
     {
      case HIT_SORT_SCORE:
         g_scanner.SetSortKey(SCAN_SORT_SCORE);
         break;
      case HIT_SORT_RS:
         g_scanner.SetSortKey(g_scanner.SortKey()==SCAN_SORT_RS_STRONG?SCAN_SORT_RS_WEAK:SCAN_SORT_RS_STRONG);
         break;
      case HIT_SORT_ATR:
         g_scanner.SetSortKey(SCAN_SORT_ATR);
         break;
      case HIT_SYMBOL:
        {
         SSnapshot s;
         if(g_scanner.Row(row,s))
            OpenSymbolChart(s.symbol,g_tf);
         break;
        }
      default:
         break;
     }

   if(hit==HIT_NONE)
      return;
   if(hit!=HIT_SYMBOL)
     {
      g_scanner.ConsumeChanged();
      g_panel.Update(g_scanner,StatusText());
     }
   else
      ChartRedraw(0);
  }