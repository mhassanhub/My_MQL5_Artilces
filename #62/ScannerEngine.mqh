//+------------------------------------------------------------------+
//|                                                ScannerEngine.mqh |
//|     Time-sliced scheduler, cross-sectional ranking, signals      |
//+------------------------------------------------------------------+
#ifndef SCANNER_ENGINE_MQH
#define SCANNER_ENGINE_MQH

#include "SymbolContext.mqh"

class CMarketScanner
  {
private:
   SScanConfig       m_cfg;
   CSymbolContext   *m_ctx[];
   SSnapshot         m_snap[];
   bool              m_qualified[];
   int               m_order[];
   string            m_alerts[];
   int               m_count;
   int               m_ranked;
   int               m_cursor;
   ulong             m_budgetUs;
   ENUM_SCAN_SORT    m_sortKey;
   bool              m_changed;
   bool              m_everEvaluated;
   bool              m_settled;

   double            KeyOf(const SSnapshot &s) const;
   void              SortOrder(void);
   void              Rank(void);
   void              DetectSignals(void);
public:
                     CMarketScanner(void);
                    ~CMarketScanner(void);
   bool              Init(const SScanConfig &cfg,const string &symbols[],
                          const int total,const uint budgetMs);
   void              Shutdown(void);
   int               Step(void);
   void              SetSortKey(const ENUM_SCAN_SORT key);
   ENUM_SCAN_SORT    SortKey(void) const              { return m_sortKey; }
   bool              Row(const int rank,SSnapshot &out) const;
   int               Count(void) const                { return m_count; }
   int               Ranked(void) const               { return m_ranked; }
   bool              ConsumeChanged(void);
   int               AlertCount(void) const           { return ArraySize(m_alerts); }
   string            AlertAt(const int index) const   { return m_alerts[index]; }
   void              ClearAlerts(void)                { ArrayResize(m_alerts,0); }
  };

//+------------------------------------------------------------------+
CMarketScanner::CMarketScanner(void)
  {
   m_count=0;
   m_ranked=0;
   m_cursor=0;
   m_budgetUs=40000;
   m_sortKey=SCAN_SORT_SCORE;
   m_changed=false;
   m_everEvaluated=false;
   m_settled=false;
  }
//+------------------------------------------------------------------+
CMarketScanner::~CMarketScanner(void)
  {
   Shutdown();
  }
//+------------------------------------------------------------------+
//| Create one context per symbol; symbols that fail are skipped     |
//+------------------------------------------------------------------+
bool CMarketScanner::Init(const SScanConfig &cfg,const string &symbols[],
                          const int total,const uint budgetMs)
  {
   Shutdown();
   const double wSum=cfg.wTrend+cfg.wMomentum+cfg.wRelStrength;
   if(wSum<=0.0 || total<2 || cfg.rsLookback<1 || cfg.squeezeLookback<5 ||
      cfg.volumeLookback<2 || cfg.setupWeight<0.0 || cfg.setupWeight>1.0)
     {
      Print("CMarketScanner: invalid configuration or fewer than two symbols");
      return false;
     }
   m_cfg=cfg;
   m_budgetUs=(ulong)budgetMs*(ulong)1000;

   ArrayResize(m_ctx,total);
   ArrayResize(m_snap,total);
   m_count=0;
   for(int i=0;i<total;i++)
     {
      CSymbolContext *ctx=new CSymbolContext();
      if(CheckPointer(ctx)==POINTER_INVALID)
         continue;
      if(!ctx.Init(symbols[i],m_cfg))
        {
         PrintFormat("CMarketScanner: %s skipped, handles not created (error %d)",
                     symbols[i],GetLastError());
         delete ctx;
         continue;
        }
      m_ctx[m_count]=ctx;
      ResetSnapshot(m_snap[m_count],symbols[i]);
      m_count++;
     }
   ArrayResize(m_ctx,m_count);
   ArrayResize(m_snap,m_count);
   ArrayResize(m_qualified,m_count);
   ArrayResize(m_order,m_count);
   for(int i=0;i<m_count;i++)
      m_qualified[i]=false;

   if(m_count<2)
     {
      Print("CMarketScanner: fewer than two usable symbols");
      Shutdown();
      return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
//| Release every context and reset the state                        |
//+------------------------------------------------------------------+
void CMarketScanner::Shutdown(void)
  {
   for(int i=0;i<ArraySize(m_ctx);i++)
      if(CheckPointer(m_ctx[i])==POINTER_DYNAMIC)
         delete m_ctx[i];
   ArrayFree(m_ctx);
   ArrayFree(m_snap);
   ArrayFree(m_qualified);
   ArrayFree(m_order);
   ArrayFree(m_alerts);
   m_count=0;
   m_ranked=0;
   m_cursor=0;
   m_changed=false;
   m_everEvaluated=false;
   m_settled=false;
  }
//+------------------------------------------------------------------+
//| One time slice: evaluate dirty symbols until the budget is spent |
//+------------------------------------------------------------------+
int CMarketScanner::Step(void)
  {
   if(m_count==0)
      return 0;
   const ulong started=GetMicrosecondCount();
   int evaluated=0;
   int visited=0;
   while(visited<m_count)
     {
      const int idx=m_cursor;
      m_cursor=(m_cursor+1)%m_count;
      visited++;
      if(!m_ctx[idx].IsDirty())
         continue;
      if(m_ctx[idx].Evaluate(m_cfg,m_snap[idx]))
         evaluated++;
      if(GetMicrosecondCount()-started>=m_budgetUs)
         break;
     }
   if(evaluated>0)
     {
      m_everEvaluated=true;
      Rank();
      DetectSignals();
      m_changed=true;
     }
   else if(m_everEvaluated && visited>=m_count)
      m_settled=true;
   return evaluated;
  }
//+------------------------------------------------------------------+
//| Sort key of a snapshot for the current sort mode                 |
//+------------------------------------------------------------------+
double CMarketScanner::KeyOf(const SSnapshot &s) const
  {
   switch(m_sortKey)
     {
      case SCAN_SORT_RS_STRONG: return s.rsRank;
      case SCAN_SORT_RS_WEAK:   return -s.rsRank;
      case SCAN_SORT_ATR:       return s.atrPct;
      default:                  break;
     }
   return s.score;
  }
//+------------------------------------------------------------------+
//| Build the descending order of valid snapshots (insertion sort)   |
//+------------------------------------------------------------------+
void CMarketScanner::SortOrder(void)
  {
   m_ranked=0;
   for(int i=0;i<m_count;i++)
     {
      if(!m_snap[i].valid)
         continue;
      const double key=KeyOf(m_snap[i]);
      int pos=m_ranked;
      while(pos>0 && KeyOf(m_snap[m_order[pos-1]])<key)
        {
         m_order[pos]=m_order[pos-1];
         pos--;
        }
      m_order[pos]=i;
      m_ranked++;
     }
  }
//+------------------------------------------------------------------+
//| Cross-sectional values: percentile, bias, direction, score       |
//+------------------------------------------------------------------+
void CMarketScanner::Rank(void)
  {
   int validCount=0;
   for(int i=0;i<m_count;i++)
      if(m_snap[i].valid)
         validCount++;

   const double wSum=m_cfg.wTrend+m_cfg.wMomentum+m_cfg.wRelStrength;
   for(int i=0;i<m_count;i++)
     {
      if(!m_snap[i].valid)
         continue;

      //--- mid-rank percentile of the N-bar return
      double below=0.0;
      double equal=0.0;
      for(int j=0;j<m_count;j++)
        {
         if(j==i || !m_snap[j].valid)
            continue;
         if(m_snap[j].retN<m_snap[i].retN)
            below+=1.0;
         else if(m_snap[j].retN==m_snap[i].retN)
            equal+=1.0;
        }
      m_snap[i].rsRank=(validCount>1)?100.0*(below+0.5*equal)/(double)(validCount-1):50.0;

      //--- directional bias on the common -100..+100 scale
      const double rsCentered=(m_snap[i].rsRank-50.0)*2.0;
      m_snap[i].bias=(m_cfg.wTrend*m_snap[i].trend+
                      m_cfg.wMomentum*m_snap[i].momentum+
                      m_cfg.wRelStrength*rsCentered)/wSum;
      if(m_snap[i].bias>=m_cfg.biasThreshold)
         m_snap[i].direction=1;
      else if(m_snap[i].bias<=-m_cfg.biasThreshold)
         m_snap[i].direction=-1;
      else
         m_snap[i].direction=0;

      //--- conviction blended with setup quality
      const double setup=0.5*m_snap[i].squeeze+0.5*m_snap[i].volumeSurge;
      m_snap[i].score=(1.0-m_cfg.setupWeight)*MathAbs(m_snap[i].bias)+
                      m_cfg.setupWeight*setup;
     }
   SortOrder();
  }
//+------------------------------------------------------------------+
//| Queue a message when a symbol becomes qualified                  |
//+------------------------------------------------------------------+
void CMarketScanner::DetectSignals(void)
  {
   for(int i=0;i<m_count;i++)
     {
      if(!m_snap[i].valid)
         continue;
      const bool qualifiedNow=(m_snap[i].direction!=0 && m_snap[i].score>=m_cfg.minScore);
      if(qualifiedNow && !m_qualified[i] && m_settled)
        {
         const string side=(m_snap[i].direction>0)?"LONG":"SHORT";
         const string text=StringFormat("%s %s setup | score %.1f | bias %.0f | RS rank %.0f",
                                        m_snap[i].symbol,side,m_snap[i].score,
                                        m_snap[i].bias,m_snap[i].rsRank);
         const int n=ArraySize(m_alerts);
         ArrayResize(m_alerts,n+1);
         m_alerts[n]=text;
        }
      m_qualified[i]=qualifiedNow;
     }
  }
//+------------------------------------------------------------------+
void CMarketScanner::SetSortKey(const ENUM_SCAN_SORT key)
  {
   m_sortKey=key;
   SortOrder();
   m_changed=true;
  }
//+------------------------------------------------------------------+
bool CMarketScanner::Row(const int rank,SSnapshot &out) const
  {
   if(rank<0 || rank>=m_ranked)
      return false;
   out=m_snap[m_order[rank]];
   return true;
  }
//+------------------------------------------------------------------+
bool CMarketScanner::ConsumeChanged(void)
  {
   const bool was=m_changed;
   m_changed=false;
   return was;
  }

#endif