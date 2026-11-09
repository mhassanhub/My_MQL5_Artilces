//+------------------------------------------------------------------+
//|                                                SuperTrend-EA.mq5 |
//+------------------------------------------------------------------+
#property copyright   "Author: Your Name"
#property link        "https://www.mql5.com"
#property version     "1.00"
#property description "Three Supertrend strategies in one Expert Advisor"
#property tester_indicator "Custom-SuperTrend.ex5"

#include <Trade\\Trade.mqh>

//+------------------------------------------------------------------+
//| Strategy selector                                                |
//+------------------------------------------------------------------+
enum ENUM_ST_STRATEGY
  {
   STRATEGY_REVERSAL   = 0,   // 1: stop-and-reverse
   STRATEGY_EMA_FILTER = 1,   // 2: EMA filter + fixed R:R
   STRATEGY_DUAL       = 2    // 3: dual Supertrend pullback
  };

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "Strategy"
input ENUM_ST_STRATEGY InpStrategy         = STRATEGY_REVERSAL;  // Strategy to run
input group "Main Supertrend"
input int              InpATRPeriod        = 10;                 // ATR period
input double           InpMultiplier       = 3.0;                // ATR multiplier
input group "Fast Supertrend (strategy 3)"
input int              InpFastPeriod       = 7;                  // Fast ATR period
input double           InpFastMultiplier   = 1.5;                // Fast ATR multiplier
input group "EMA filter (strategy 2)"
input int              InpEMAPeriod        = 200;                // EMA period
input double           InpRewardRisk       = 2.0;                // Take profit as a multiple of risk
input group "Money management"
input double           InpRiskPercent      = 1.0;                // Risk per trade, % of balance
input group "Trade settings"
input ulong            InpMagic            = 20261026;           // Magic number
input int              InpDeviation        = 20;                 // Maximum slippage, points

//+------------------------------------------------------------------+
//| Global objects and handles                                       |
//+------------------------------------------------------------------+
CTrade   g_trade;                       // trade execution object
int      g_slowHandle = INVALID_HANDLE; // main Supertrend handle
int      g_fastHandle = INVALID_HANDLE; // fast Supertrend handle (strategy 3)
int      g_emaHandle  = INVALID_HANDLE; // EMA handle (strategy 2)
datetime g_lastBar    = 0;              // open time of the last processed bar

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRiskPercent<=0.0 || InpRiskPercent>10.0 || InpRewardRisk<=0.0 ||
      InpATRPeriod<1 || InpMultiplier<=0.0 ||
      InpFastPeriod<1 || InpFastMultiplier<=0.0)                                // reject invalid inputs
     {
      Print("Supertrend EA: invalid input parameters");                         // explain the refusal
      return(INIT_PARAMETERS_INCORRECT);                                        // stop initialization
     }
   g_slowHandle=iCustom(_Symbol,_Period,"Custom-SuperTrend",InpATRPeriod,InpMultiplier); // main Supertrend
   if(g_slowHandle==INVALID_HANDLE)                                             // handle creation failed
     {
      Print("Cannot create Supertrend handle, error ",GetLastError());          // report the cause
      return(INIT_FAILED);                                                      // abort loading
     }
   if(InpStrategy==STRATEGY_DUAL)                                               // only strategy 3 needs it
     {
      g_fastHandle=iCustom(_Symbol,_Period,"Custom-SuperTrend",InpFastPeriod,InpFastMultiplier); // fast Supertrend
      if(g_fastHandle==INVALID_HANDLE)                                          // fast handle failed
         return(INIT_FAILED);                                                   // abort loading
     }
   if(InpStrategy==STRATEGY_EMA_FILTER)                                         // only strategy 2 needs it
     {
      g_emaHandle=iMA(_Symbol,_Period,InpEMAPeriod,0,MODE_EMA,PRICE_CLOSE);     // EMA of closes
      if(g_emaHandle==INVALID_HANDLE)                                           // EMA handle failed
         return(INIT_FAILED);                                                   // abort loading
     }
   g_trade.SetExpertMagicNumber(InpMagic);                                      // tag our orders
   g_trade.SetDeviationInPoints(InpDeviation);                                  // allowed slippage
   g_trade.SetTypeFillingBySymbol(_Symbol);                                     // broker-compatible filling
   return(INIT_SUCCEEDED);                                                      // EA is ready
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_slowHandle!=INVALID_HANDLE)                                             // main handle exists
      IndicatorRelease(g_slowHandle);                                           // free it
   if(g_fastHandle!=INVALID_HANDLE)                                             // fast handle exists
      IndicatorRelease(g_fastHandle);                                           // free it
   if(g_emaHandle!=INVALID_HANDLE)                                              // EMA handle exists
      IndicatorRelease(g_emaHandle);                                            // free it
  }

//+------------------------------------------------------------------+
//| New bar detection                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime barTime=iTime(_Symbol,_Period,0);                                   // open time of the current bar
   if(barTime==0 || barTime==g_lastBar)                                         // no data, or same bar as before
      return(false);                                                            // not a new bar
   g_lastBar=barTime;                                                           // remember this bar
   return(true);                                                                // new bar detected
  }

//+------------------------------------------------------------------+
//| Read direction from the Supertrend buffer                        |
//+------------------------------------------------------------------+
int GetDirection(const int handle,const int shift)
  {
   double v[1];                                                                 // one-element receive array
   if(CopyBuffer(handle,2,shift,1,v)!=1)                                        // buffer 2 = direction
      return(0);                                                                // 0 = unknown
   if(v[0]>0.0)                                                                 // positive means up trend
      return(1);                                                                // up
   if(v[0]<0.0)                                                                 // negative means down trend
      return(-1);                                                               // down
   return(0);                                                                   // nothing calculated yet
  }

//+------------------------------------------------------------------+
//| Read the Supertrend line value                                   |
//+------------------------------------------------------------------+
double GetLine(const int handle,const int shift)
  {
   double v[1];                                                                 // one-element receive array
   if(CopyBuffer(handle,0,shift,1,v)!=1)                                        // buffer 0 = Supertrend value
      return(0.0);                                                              // 0.0 = unknown
   return(v[0]);                                                                // line value
  }

//+------------------------------------------------------------------+
//| Read the EMA value                                               |
//+------------------------------------------------------------------+
double GetEMA(const int shift)
  {
   double v[1];                                                                 // one-element receive array
   if(CopyBuffer(g_emaHandle,0,shift,1,v)!=1)                                   // buffer 0 = EMA value
      return(0.0);                                                              // 0.0 = unknown
   return(v[0]);                                                                // EMA value
  }

//+------------------------------------------------------------------+
//| Find and select our position                                     |
//+------------------------------------------------------------------+
bool SelectOwnPosition(ENUM_POSITION_TYPE &type,ulong &ticket)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)                                       // scan open positions
     {
      ulong id=PositionGetTicket(i);                                            // selects the position
      if(id==0)                                                                 // selection failed
         continue;                                                              // skip it
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)                           // other symbol
         continue;                                                              // skip it
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic)                    // other EA or manual trade
         continue;                                                              // skip it
      type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);               // buy or sell
      ticket=id;                                                                // return the ticket
      return(true);                                                             // found our position
     }
   return(false);                                                               // none found
  }

//+------------------------------------------------------------------+
//| Check for our open position                                      |
//+------------------------------------------------------------------+
bool HasOwnPosition()
  {
   ENUM_POSITION_TYPE type=POSITION_TYPE_BUY;                                   // dummy value for the call
   ulong ticket=0;                                                              // dummy value for the call
   return(SelectOwnPosition(type,ticket));                                      // true when a position exists
  }

//+------------------------------------------------------------------+
//| Broker minimum stop distance                                     |
//+------------------------------------------------------------------+
double MinStopDistance()
  {
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);              // minimum stop distance, points
   long freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);            // freeze distance, points
   return((double)MathMax(stops,freeze)*_Point);                                // larger one, in price units
  }

//+------------------------------------------------------------------+
//| Risk-based lot size                                              |
//+------------------------------------------------------------------+
double CalcLots(const double slDistance,const ENUM_ORDER_TYPE type,const double price)
  {
   double riskMoney=AccountInfoDouble(ACCOUNT_BALANCE)*InpRiskPercent/100.0;                       // money we accept to lose
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);                        // loss per tick per lot
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);                               // tick size in price units
   double lossPerLot = (slDistance / tickSize) * tickValue;                                        // Calculate monetary loss per single lot
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);                                       // lot step
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);                                      // minimum lot
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);                                      // maximum lot
   if(tickValue<=0.0 || tickSize<=0.0 || step<=0.0 || slDistance<=0.0 || lossPerLot <= 0.0)        // unusable symbol data
      return(0.0);                                                                                 // do not trade
   lossPerLot=slDistance/tickSize*tickValue;                                                       // loss at the stop, 1 lot
   double lots=riskMoney/lossPerLot;                                                               // raw volume
   lots=MathFloor(lots/step+1e-9)*step;                                                            // round down to the lot step
   if(lots<minLot)                                                                                 // risk budget too small
      return(0.0);                                                                                 // do not trade
   lots=MathMin(maxLot,lots);                                                                      // cap at broker maximum
   int digits=(int)MathMax(0.0,MathCeil(-MathLog10(step)));                                        // decimals in the step
   lots=NormalizeDouble(lots,digits);                                                              // clean floating noise
   double margin=0.0;                                                                              // required margin
   if(!OrderCalcMargin(type,_Symbol,lots,price,margin))                                            // margin calculation failed
      return(0.0);                                                                                 // do not trade
   if(margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))                                               // not enough free margin
      return(0.0);                                                                                 // do not trade
   return(lots);                                                                                   // final volume
  }

//+------------------------------------------------------------------+
//| Open a market position                                           |
//+------------------------------------------------------------------+
bool OpenPosition(const ENUM_ORDER_TYPE type,const double stopPrice,const double rewardRisk)
  {
   if(HasOwnPosition())                                                         // one position at a time
      return(false);                                                            // skip the signal
   double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);                           // buy at the ask
   if(type==ORDER_TYPE_SELL)                                                    // sells use the bid
      price=SymbolInfoDouble(_Symbol,SYMBOL_BID);                               // sell at the bid
   double slDistance=MathAbs(price-stopPrice);                                  // risk distance in price units
   if(slDistance<=MinStopDistance())                                            // stop too close for the broker
      return(false);                                                            // skip the signal
   if(type==ORDER_TYPE_BUY && stopPrice>=price)                                 // stop must be below a buy
      return(false);                                                            // invalid stop side
   if(type==ORDER_TYPE_SELL && stopPrice<=price)                                // stop must be above a sell
      return(false);                                                            // invalid stop side
   double takeProfit=0.0;                                                       // 0.0 = no target
   if(rewardRisk>0.0)                                                           // a target was requested
     {
      if(type==ORDER_TYPE_BUY)                                                  // target above a long entry
         takeProfit=price+rewardRisk*slDistance;                                // entry + R multiple
      else                                                                      // target below a short entry
         takeProfit=price-rewardRisk*slDistance;                                // entry - R multiple
     }
   double lots=CalcLots(slDistance,type,price);                                 // risk-based volume
   if(lots<=0.0)                                                                // sizing refused the trade
      return(false);                                                            // skip the signal
   double sl=NormalizeDouble(stopPrice,_Digits);                                // broker-precision stop
   double tp=NormalizeDouble(takeProfit,_Digits);                               // broker-precision target
   bool sent=false;                                                             // order result
   if(type==ORDER_TYPE_BUY)                                                     // long signal
      sent=g_trade.Buy(lots,_Symbol,price,sl,tp,"Supertrend");                  // market buy
   else                                                                         // short signal
      sent=g_trade.Sell(lots,_Symbol,price,sl,tp,"Supertrend");                 // market sell
   if(!sent)                                                                    // order rejected
      Print("Order failed: ",g_trade.ResultRetcodeDescription());               // log the reason
   return(sent);                                                                // report the outcome
  }

//+------------------------------------------------------------------+
//| Close our position of a given type                               |
//+------------------------------------------------------------------+
void CloseOwn(const ENUM_POSITION_TYPE type)
  {
   ENUM_POSITION_TYPE found=POSITION_TYPE_BUY;                                  // type of our position
   ulong ticket=0;                                                              // ticket of our position
   if(SelectOwnPosition(found,ticket) && found==type)                           // exists and has the given type
      g_trade.PositionClose(ticket);                                            // close at market
  }

//+------------------------------------------------------------------+
//| Trail the stop on the Supertrend line                            |
//+------------------------------------------------------------------+
void TrailStop(const int handle)
  {
   ENUM_POSITION_TYPE type=POSITION_TYPE_BUY;                                   // our position type
   ulong ticket=0;                                                              // our position ticket
   if(!SelectOwnPosition(type,ticket))                                          // nothing to trail
      return;                                                                   // leave
   int dir=GetDirection(handle,1);                                              // direction, last closed bar
   double line=GetLine(handle,1);                                               // line value, last closed bar
   if(dir==0 || line<=0.0)                                                      // no valid reading
      return;                                                                   // leave
   double currentSL=PositionGetDouble(POSITION_SL);                             // existing stop
   double currentTP=PositionGetDouble(POSITION_TP);                             // existing target
   double minDist=MinStopDistance();                                            // broker minimum distance
   if(type==POSITION_TYPE_BUY && dir>0)                                         // long in an up trend
     {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);                          // current bid
      if((currentSL==0.0 || line>currentSL) && line<bid-minDist)                // raise only, at a legal distance
         g_trade.PositionModify(ticket,NormalizeDouble(line,_Digits),currentTP); // move the stop up
     }
   else if(type==POSITION_TYPE_SELL && dir<0)                                   // short in a down trend
     {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);                          // current ask
      if((currentSL==0.0 || line<currentSL) && line>ask+minDist)                // lower only, at a legal distance
         g_trade.PositionModify(ticket,NormalizeDouble(line,_Digits),currentTP); // move the stop down
     }
  }

//+------------------------------------------------------------------+
//| Strategy 1: stop-and-reverse                                     |
//+------------------------------------------------------------------+
void RunReversal()
  {
   int dirNow=GetDirection(g_slowHandle,1);                                     // direction, last closed bar
   int dirPrev=GetDirection(g_slowHandle,2);                                    // direction, bar before it
   if(dirNow==0 || dirPrev==0)                                                  // indicator not ready
      return;                                                                   // wait
   double line=GetLine(g_slowHandle,1);                                         // stop level for new trades
   if(dirPrev<0 && dirNow>0)                                                    // flip: down to up
     {
      CloseOwn(POSITION_TYPE_SELL);                                             // close the short
      if(!HasOwnPosition())
      OpenPosition(ORDER_TYPE_BUY,line,0.0);                                    // open long, no target
     }
   else if(dirPrev>0 && dirNow<0)                                               // flip: up to down
     {
      CloseOwn(POSITION_TYPE_BUY);                                              // close the long
      if(!HasOwnPosition())
      OpenPosition(ORDER_TYPE_SELL,line,0.0);                                   // open short, no target
     }
   else                                                                         // no flip on this bar
      TrailStop(g_slowHandle);                                                  // trail the open trade
  }

//+------------------------------------------------------------------+
//| Strategy 2: EMA filter with fixed R:R                            |
//+------------------------------------------------------------------+
void RunEmaFilter()
  {
   if(HasOwnPosition())                                                         // stop and target manage the trade
      return;                                                                   // wait for it to finish
   int dirNow=GetDirection(g_slowHandle,1);                                     // direction, last closed bar
   int dirPrev=GetDirection(g_slowHandle,2);                                    // direction, bar before it
   if(dirNow==0 || dirPrev==0)                                                  // indicator not ready
      return;                                                                   // wait
   double ema=GetEMA(1);                                                        // EMA on the last closed bar
   double closePrice=iClose(_Symbol,_Period,1);                                 // close of the last closed bar
   if(ema<=0.0 || closePrice<=0.0)                                              // data not ready
      return;                                                                   // wait
   double line=GetLine(g_slowHandle,1);                                         // stop level for new trades
   if(dirPrev<0 && dirNow>0 && closePrice>ema)                                  // up flip above the EMA
      OpenPosition(ORDER_TYPE_BUY,line,InpRewardRisk);                          // long with an R target
   else if(dirPrev>0 && dirNow<0 && closePrice<ema)                             // down flip below the EMA
      OpenPosition(ORDER_TYPE_SELL,line,InpRewardRisk);                         // short with an R target
  }

//+------------------------------------------------------------------+
//| Strategy 3: dual Supertrend pullback                             |
//+------------------------------------------------------------------+
void RunDual()
  {
   int slowDir=GetDirection(g_slowHandle,1);                                    // trend direction
   int fastNow=GetDirection(g_fastHandle,1);                                    // fast direction, last closed bar
   int fastPrev=GetDirection(g_fastHandle,2);                                   // fast direction, bar before it
   if(slowDir==0 || fastNow==0 || fastPrev==0)                                  // indicators not ready
      return;                                                                   // wait
   ENUM_POSITION_TYPE type=POSITION_TYPE_BUY;                                   // open position type
   ulong ticket=0;                                                              // open position ticket
   if(SelectOwnPosition(type,ticket))                                           // manage the open trade
     {
      if((type==POSITION_TYPE_BUY && slowDir<0) ||
         (type==POSITION_TYPE_SELL && slowDir>0))                               // slow trend turned against us
         g_trade.PositionClose(ticket);                                         // exit at market
      else                                                                      // trend still intact
         TrailStop(g_slowHandle);                                               // trail on the slow line
      return;                                                                   // no new entry while in a trade
     }
   double slowLine=GetLine(g_slowHandle,1);                                     // stop level for new trades
   if(slowDir>0 && fastPrev<0 && fastNow>0)                                     // pullback over in an up trend
      OpenPosition(ORDER_TYPE_BUY,slowLine,0.0);                                // long, trailed stop
   else if(slowDir<0 && fastPrev>0 && fastNow<0)                                // pullback over in a down trend
      OpenPosition(ORDER_TYPE_SELL,slowLine,0.0);                               // short, trailed stop
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar())                                                              // act once per closed bar
      return;                                                                   // ignore intrabar ticks
   switch(InpStrategy)                                                          // run the selected system
     {
      case STRATEGY_REVERSAL:   RunReversal();   break;                         // strategy 1
      case STRATEGY_EMA_FILTER: RunEmaFilter();  break;                         // strategy 2
      case STRATEGY_DUAL:       RunDual();       break;                         // strategy 3
     }
  }