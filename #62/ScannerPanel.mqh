//+------------------------------------------------------------------+
//|                                                 ScannerPanel.mqh |
//|        Dashboard made of pooled chart objects, click handling    |
//+------------------------------------------------------------------+
#ifndef SCANNER_PANEL_MQH
#define SCANNER_PANEL_MQH

#include "ScannerEngine.mqh"

#define PANEL_COLS         10
#define PANEL_ROW_H        18
#define PANEL_COL_RANK     0
#define PANEL_COL_SYMBOL   1
#define PANEL_COL_DIR      2
#define PANEL_COL_SCORE    3
#define PANEL_COL_TREND    4
#define PANEL_COL_MOM      5
#define PANEL_COL_RS       6
#define PANEL_COL_SQUEEZE  7
#define PANEL_COL_VOLUME   8
#define PANEL_COL_ATR      9

//--- what a click on the panel means
enum ENUM_PANEL_HIT
  {
   HIT_NONE = 0,
   HIT_SORT_SCORE,
   HIT_SORT_RS,
   HIT_SORT_ATR,
   HIT_SYMBOL
  };

//+------------------------------------------------------------------+
string PanelHeaderText(const int col)
  {
   switch(col)
     {
      case PANEL_COL_RANK:    return "#";
      case PANEL_COL_SYMBOL:  return "Symbol";
      case PANEL_COL_DIR:     return "Dir";
      case PANEL_COL_SCORE:   return "Score";
      case PANEL_COL_TREND:   return "Trend";
      case PANEL_COL_MOM:     return "Mom";
      case PANEL_COL_RS:      return "RS%";
      case PANEL_COL_SQUEEZE: return "Sqz";
      case PANEL_COL_VOLUME:  return "Vol";
      case PANEL_COL_ATR:     return "ATR%";
     }
   return "";
  }
//+------------------------------------------------------------------+
color SignColor(const double value)
  {
   if(value>0.0)
      return clrLime;
   if(value<0.0)
      return clrTomato;
   return clrSilver;
  }

//+------------------------------------------------------------------+
class CScannerPanel
  {
private:
   string            m_prefix;
   int               m_rows;
   int               m_x;
   int               m_y;
   int               m_colX[PANEL_COLS];
   int               m_colW[PANEL_COLS];

   string            HeaderName(const int col) const { return m_prefix+"h"+IntegerToString(col); }
   string            CellName(const int col,const int row) const
                       { return m_prefix+"c"+IntegerToString(col)+"_"+IntegerToString(row); }
   string            StatusName(void) const          { return m_prefix+"status"; }
   bool              MakeLabel(const string name,const int x,const int y,const string text);
   bool              MakeButton(const string name,const int x,const int y,const int w,
                                const string text,const color bgColor);
   void              SetCell(const string name,const string text,const color clr);
public:
                     CScannerPanel(void);
   bool              Create(const string prefix,const int x,const int y,const int rows);
   void              Destroy(void);
   void              Update(CMarketScanner &scanner,const string status);
   ENUM_PANEL_HIT    Hit(const string objectName,int &row);
  };

//+------------------------------------------------------------------+
CScannerPanel::CScannerPanel(void)
  {
   m_prefix="";
   m_rows=0;
   m_x=0;
   m_y=0;
  }
//+------------------------------------------------------------------+
bool CScannerPanel::MakeLabel(const string name,const int x,const int y,const string text)
  {
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))
      return false;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   return true;
  }
//+------------------------------------------------------------------+
bool CScannerPanel::MakeButton(const string name,const int x,const int y,const int w,
                               const string text,const color bgColor)
  {
   if(!ObjectCreate(0,name,OBJ_BUTTON,0,0,0))
      return false;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,PANEL_ROW_H-2);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bgColor);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,bgColor);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   return true;
  }
//+------------------------------------------------------------------+
void CScannerPanel::SetCell(const string name,const string text,const color clr)
  {
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
  }
//+------------------------------------------------------------------+
//| Create the whole object pool once                                |
//+------------------------------------------------------------------+
bool CScannerPanel::Create(const string prefix,const int x,const int y,const int rows)
  {
   m_prefix=prefix;
   Destroy();                              // remove leftovers of a previous run
   m_prefix=prefix;
   m_rows=rows;
   m_x=x;
   m_y=y;

   const int xs[PANEL_COLS]={0,30,106,152,206,254,302,350,398,446};
   const int ws[PANEL_COLS]={28,74,44,52,46,46,46,46,46,52};
   for(int c=0;c<PANEL_COLS;c++)
     {
      m_colX[c]=xs[c];
      m_colW[c]=ws[c];
     }

   //--- background
   const string backName=m_prefix+"bg";
   if(!ObjectCreate(0,backName,OBJ_RECTANGLE_LABEL,0,0,0))
      return false;
   ObjectSetInteger(0,backName,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,backName,OBJPROP_XDISTANCE,m_x);
   ObjectSetInteger(0,backName,OBJPROP_YDISTANCE,m_y);
   ObjectSetInteger(0,backName,OBJPROP_XSIZE,m_colX[PANEL_COLS-1]+m_colW[PANEL_COLS-1]+16);
   ObjectSetInteger(0,backName,OBJPROP_YSIZE,PANEL_ROW_H*(m_rows+2)+16);
   ObjectSetInteger(0,backName,OBJPROP_BGCOLOR,C'20,24,32');
   ObjectSetInteger(0,backName,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,backName,OBJPROP_COLOR,C'60,68,84');
   ObjectSetInteger(0,backName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,backName,OBJPROP_HIDDEN,true);

   //--- header row
   for(int c=0;c<PANEL_COLS;c++)
      if(!MakeButton(HeaderName(c),m_x+6+m_colX[c],m_y+4,m_colW[c],
                     PanelHeaderText(c),C'45,52,66'))
         return false;

   //--- data rows
   for(int r=0;r<m_rows;r++)
     {
      const int rowY=m_y+4+PANEL_ROW_H*(r+1)+2;
      for(int c=0;c<PANEL_COLS;c++)
        {
         const bool created=(c==PANEL_COL_SYMBOL)
                            ?MakeButton(CellName(c,r),m_x+6+m_colX[c],rowY,m_colW[c],"",C'28,33,44')
                            :MakeLabel(CellName(c,r),m_x+10+m_colX[c],rowY+2,"");
         if(!created)
            return false;
        }
     }

   //--- status line below the table
   return MakeLabel(StatusName(),m_x+10,m_y+4+PANEL_ROW_H*(m_rows+1)+6,"");
  }
//+------------------------------------------------------------------+
void CScannerPanel::Destroy(void)
  {
   if(m_prefix=="")
      return;
   ObjectsDeleteAll(0,m_prefix);
  }
//+------------------------------------------------------------------+
//| Refresh texts and colors from the ranked list                    |
//+------------------------------------------------------------------+
void CScannerPanel::Update(CMarketScanner &scanner,const string status)
  {
   for(int r=0;r<m_rows;r++)
     {
      SSnapshot s;
      if(!scanner.Row(r,s))
        {
         for(int c=0;c<PANEL_COLS;c++)
            SetCell(CellName(c,r),"",clrSilver);
         continue;
        }

      color sideColor=clrSilver;
      string sideText="-";
      if(s.direction>0)
        {
         sideColor=clrLime;
         sideText="LONG";
        }
      else if(s.direction<0)
        {
         sideColor=clrTomato;
         sideText="SHORT";
        }

      SetCell(CellName(PANEL_COL_RANK,r),IntegerToString(r+1),clrSilver);
      SetCell(CellName(PANEL_COL_SYMBOL,r),s.symbol,clrWhite);
      SetCell(CellName(PANEL_COL_DIR,r),sideText,sideColor);
      SetCell(CellName(PANEL_COL_SCORE,r),DoubleToString(s.score,1),sideColor);
      SetCell(CellName(PANEL_COL_TREND,r),DoubleToString(s.trend,0),SignColor(s.trend));
      SetCell(CellName(PANEL_COL_MOM,r),DoubleToString(s.momentum,0),SignColor(s.momentum));
      SetCell(CellName(PANEL_COL_RS,r),DoubleToString(s.rsRank,0),SignColor(s.rsRank-50.0));
      SetCell(CellName(PANEL_COL_SQUEEZE,r),DoubleToString(s.squeeze,0),
              (s.squeeze>=80.0)?clrGold:clrSilver);
      SetCell(CellName(PANEL_COL_VOLUME,r),DoubleToString(s.volumeSurge,0),
              (s.volumeSurge>=50.0)?clrDeepSkyBlue:clrSilver);
      SetCell(CellName(PANEL_COL_ATR,r),DoubleToString(s.atrPct,2),clrSilver);
     }
   SetCell(StatusName(),status,clrSilver);
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
//| Translate a clicked object name into an action                   |
//+------------------------------------------------------------------+
ENUM_PANEL_HIT CScannerPanel::Hit(const string objectName,int &row)
  {
   row=-1;
   if(m_prefix=="" || StringFind(objectName,m_prefix)!=0)
      return HIT_NONE;
   ObjectSetInteger(0,objectName,OBJPROP_STATE,false);   // release the button

   if(objectName==HeaderName(PANEL_COL_SCORE))
      return HIT_SORT_SCORE;
   if(objectName==HeaderName(PANEL_COL_RS))
      return HIT_SORT_RS;
   if(objectName==HeaderName(PANEL_COL_ATR))
      return HIT_SORT_ATR;
   for(int r=0;r<m_rows;r++)
      if(objectName==CellName(PANEL_COL_SYMBOL,r))
        {
         row=r;
         return HIT_SYMBOL;
        }
   return HIT_NONE;
  }

#endif