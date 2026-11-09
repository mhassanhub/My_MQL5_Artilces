//+------------------------------------------------------------------+
//|                                                    PySignalEA.mq5 |
//|                         Python signal client for MetaTrader 5     |
//+------------------------------------------------------------------+
#property copyright "MQL5 article example"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Requests a trading signal from a local Python server over a TCP socket."

//+------------------------------------------------------------------+
//| Includes, inputs and globals                                     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>                     // CTrade class for order management

input group "Python server"
input string InpHost       = "0.0.0.0";      // Server host
input uint   InpPort       = 0000;             // Server port
input uint   InpTimeoutMs  = 3000;             // Network timeout, ms
input int    InpBars       = 300;              // Closed bars sent to Python

input group "Trading"
input double InpLots       = 0.10;             // Lot size
input int    InpStopPoints = 300;              // Stop loss, points
input int    InpTakePoints = 600;              // Take profit, points
input long   InpMagic      = 26110101;         // Magic number
input uint   InpDeviation  = 20;               // Max slippage, points

CTrade   g_trade;                              // trade helper
datetime g_lastBarTime = 0;                    // open time of the last processed bar

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBars < 200)                           // the server needs at least 200 closes
     {
      Print("InpBars must be at least 200");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpLots <= 0.0 || InpStopPoints <= 0 || InpTakePoints <= 0)
     {
      Print("Lot size, stop loss and take profit must be positive");
      return(INIT_PARAMETERS_INCORRECT);
     }
   g_trade.SetExpertMagicNumber((ulong)InpMagic);        // tag all orders of this EA
   g_trade.SetDeviationInPoints((ulong)InpDeviation);    // slippage tolerance
   PrintFormat("PySignalEA started on %s, server %s:%u", _Symbol, InpHost, InpPort);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   PrintFormat("PySignalEA stopped, reason code %d", reason);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   const datetime barTime = iTime(_Symbol, _Period, 0);  // open time of the current bar
   if(barTime == 0 || barTime == g_lastBarTime)
      return;                                  // act once per new bar only
   g_lastBarTime = barTime;                    // mark first, so a failure is not retried on every tick
   string signal      = "";                    // BUY, SELL or FLAT from Python
   double probability = 0.0;                   // model probability of an up move
   if(!QuerySignal(signal, probability))
      return;                                  // any failure means no trade on this bar
   PrintFormat("Python signal for %s: %s (p_up = %.4f)", _Symbol, signal, probability);
   ApplySignal(signal);
  }

//+------------------------------------------------------------------+
//| BuildRequest                                                     |
//+------------------------------------------------------------------+
string BuildRequest()
  {
   double closes[];                            // oldest close first
   const int copied = CopyClose(_Symbol, _Period, 1, InpBars, closes);   // start at bar 1, the last closed bar
   if(copied != InpBars)
     {
      PrintFormat("CopyClose returned %d of %d bars, error %d", copied, InpBars, GetLastError());
      return("");
     }
   string request = _Symbol + "|";             // header: the symbol name
   for(int i = 0; i < copied; i++)
     {
      request += DoubleToString(closes[i], _Digits);     // price with the symbol precision
      if(i < copied - 1)
         request += ",";                       // comma-separated list
     }
   request += "\n";                            // newline terminates the request
   return(request);
  }

//+------------------------------------------------------------------+
//| SendRequest                                                      |
//+------------------------------------------------------------------+
bool SendRequest(const int handle, const string request)
  {
   uchar data[];                               // request as bytes
   const int size = StringToCharArray(request, data, 0, WHOLE_ARRAY, CP_ACP) - 1;   // minus the terminating zero
   if(size <= 0)
      return(false);
   return(SocketSend(handle, data, (uint)size) == size);  // true if every byte was sent
  }

//+------------------------------------------------------------------+
//| ReadReply                                                        |
//+------------------------------------------------------------------+
bool ReadReply(const int handle, string &reply)
  {
   reply = "";
   const ulong deadline = GetTickCount64() + (ulong)InpTimeoutMs;   // absolute deadline
   while(GetTickCount64() < deadline && !IsStopped())
     {
      const uint available = SocketIsReadable(handle);   // bytes waiting in the buffer
      if(available > 0)
        {
         uchar chunk[];                        // receives the bytes
         const int got = SocketRead(handle, chunk, available, 100);
         if(got < 0)
            return(false);                     // read error
         reply += CharArrayToString(chunk, 0, got, CP_ACP);
         if(StringFind(reply, "\n") >= 0)
            return(true);                      // full line received
        }
      else
        {
         if(!SocketIsConnected(handle))
            return(false);                     // server closed without a full reply
         Sleep(10);                            // short pause before polling again
        }
     }
   return(false);                              // deadline reached
  }

//+------------------------------------------------------------------+
//| ParseReply                                                       |
//+------------------------------------------------------------------+
bool ParseReply(string reply, string &signal, double &probability)
  {
   StringTrimLeft(reply);                      // strip whitespace and the newline
   StringTrimRight(reply);
   string parts[];                             // expected: signal and probability
   if(StringSplit(reply, '|', parts) != 2)
      return(false);
   if(parts[0] == "ERROR")
     {
      PrintFormat("Python server error: %s", parts[1]);
      return(false);
     }
   signal      = parts[0];
   probability = StringToDouble(parts[1]);
   return(signal == "BUY" || signal == "SELL" || signal == "FLAT");   // accept known signals only
  }

//+------------------------------------------------------------------+
//| QuerySignal                                                      |
//+------------------------------------------------------------------+
bool QuerySignal(string &signal, double &probability)
  {
   signal      = "";
   probability = 0.0;
   const string request = BuildRequest();
   if(request == "")
      return(false);
   const int handle = SocketCreate();          // one short-lived connection per request
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("SocketCreate failed, error %d", GetLastError());
      return(false);
     }
   bool ok = false;                            // result of the whole exchange
   if(!SocketConnect(handle, InpHost, InpPort, InpTimeoutMs))
      PrintFormat("SocketConnect to %s:%u failed, error %d", InpHost, InpPort, GetLastError());
   else
      if(!SendRequest(handle, request))
         PrintFormat("SocketSend failed, error %d", GetLastError());
      else
        {
         string reply = "";                    // raw reply line
         if(ReadReply(handle, reply))
            ok = ParseReply(reply, signal, probability);
         else
            Print("No complete reply from the Python server");
        }
   SocketClose(handle);                        // always release the socket
   return(ok);
  }

//+------------------------------------------------------------------+
//| FindPosition                                                     |
//+------------------------------------------------------------------+
bool FindPosition(ulong &ticket, ENUM_POSITION_TYPE &type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong t = PositionGetTicket(i);    // also selects the position
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;                             // other symbol
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;                             // other EA or manual trade
      ticket = t;
      type   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| NormalizeLots                                                    |
//+------------------------------------------------------------------+
double NormalizeLots(const double lots)
  {
   const double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);    // smallest allowed volume
   const double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);    // largest allowed volume
   const double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);   // volume increment
   if(stepLot <= 0.0)
      return(minLot);
   double volume = MathFloor(lots / stepLot) * stepLot;  // round down to a valid step
   volume = MathMax(minLot, MathMin(maxLot, volume));    // clamp to broker limits
   return(NormalizeDouble(volume, 2));
  }

//+------------------------------------------------------------------+
//| OpenPosition                                                     |
//+------------------------------------------------------------------+
void OpenPosition(const bool isBuy)
  {
   const double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);   // execution price side
   if(price <= 0.0)
      return;                                  // no valid quote yet
   const long   minPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);   // broker minimum distance
   const double slDist    = (double)MathMax((long)InpStopPoints, minPoints) * _Point;
   const double tpDist    = (double)MathMax((long)InpTakePoints, minPoints) * _Point;
   const double sl = NormalizeDouble(isBuy ? price - slDist : price + slDist, _Digits);
   const double tp = NormalizeDouble(isBuy ? price + tpDist : price - tpDist, _Digits);
   const double volume = NormalizeLots(InpLots);
   const bool ok = isBuy ? g_trade.Buy(volume, _Symbol, price, sl, tp, "PySignalEA")
                         : g_trade.Sell(volume, _Symbol, price, sl, tp, "PySignalEA");
   if(!ok)
      PrintFormat("Order failed: retcode %u (%s)",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| ApplySignal                                                      |
//+------------------------------------------------------------------+
void ApplySignal(const string signal)
  {
   if(signal == "FLAT")
      return;                                  // no edge, keep the current state
   ulong              ticket = 0;              // ticket of our position, if any
   ENUM_POSITION_TYPE type   = POSITION_TYPE_BUY;
   const bool hasPosition = FindPosition(ticket, type);
   const bool wantBuy     = (signal == "BUY");
   if(hasPosition)
     {
      if((wantBuy && type == POSITION_TYPE_BUY) || (!wantBuy && type == POSITION_TYPE_SELL))
         return;                               // already aligned with the signal
      if(!g_trade.PositionClose(ticket))       // opposite signal: close first
        {
         PrintFormat("PositionClose failed: retcode %u", g_trade.ResultRetcode());
         return;
        }
     }
   OpenPosition(wantBuy);
  }