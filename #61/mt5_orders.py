#+------------------------------------------------------------------+
#| Imports                                                          |
#+------------------------------------------------------------------+
import math                                    # rounding helpers
from typing import Optional                    # explicit optional return type

import MetaTrader5 as mt5                      # official MetaTrader 5 package


#+------------------------------------------------------------------+
#| pick_filling                                                     |
#+------------------------------------------------------------------+
def pick_filling(info) -> int:                 # info is a SymbolInfo structure
    modes = info.filling_mode                  # bit mask of modes supported by the symbol
    if modes & 2:                              # bit 2 = Immediate or Cancel
        return mt5.ORDER_FILLING_IOC
    if modes & 1:                              # bit 1 = Fill or Kill
        return mt5.ORDER_FILLING_FOK
    return mt5.ORDER_FILLING_RETURN            # fallback for exchange-style execution


#+------------------------------------------------------------------+
#| normalize_volume                                                 |
#+------------------------------------------------------------------+
def normalize_volume(info, lots: float) -> float:
    step = info.volume_step                    # allowed volume increment
    volume = math.floor(lots / step) * step    # round down to a valid step
    volume = max(info.volume_min, min(info.volume_max, volume))   # clamp to broker limits
    decimals = max(0, -int(math.floor(math.log10(step))))         # precision implied by the step
    return round(volume, decimals)


#+------------------------------------------------------------------+
#| send_market_order                                                |
#+------------------------------------------------------------------+
def send_market_order(symbol: str, is_buy: bool, lots: float,
                      sl_points: int, tp_points: int,
                      magic: int = 26110102, deviation: int = 20) -> Optional[int]:
    info = mt5.symbol_info(symbol)             # static symbol properties
    if info is None or not mt5.symbol_select(symbol, True):
        print("Symbol unavailable:", symbol, mt5.last_error())
        return None
    tick = mt5.symbol_info_tick(symbol)        # latest quote
    if tick is None:
        print("No tick for", symbol, mt5.last_error())
        return None
    price = tick.ask if is_buy else tick.bid   # execution price side
    sign = 1.0 if is_buy else -1.0             # +1 for long, -1 for short
    request = {
        "action": mt5.TRADE_ACTION_DEAL,       # immediate market execution
        "symbol": symbol,
        "volume": normalize_volume(info, lots),
        "type": mt5.ORDER_TYPE_BUY if is_buy else mt5.ORDER_TYPE_SELL,
        "price": price,
        "sl": round(price - sign * sl_points * info.point, info.digits),   # stop loss
        "tp": round(price + sign * tp_points * info.point, info.digits),   # take profit
        "deviation": deviation,                # maximum slippage in points
        "magic": magic,                        # identifies orders of this script
        "comment": "py-direct",
        "type_time": mt5.ORDER_TIME_GTC,       # good till cancelled
        "type_filling": pick_filling(info),
    }
    check = mt5.order_check(request)           # dry run on the server side
    if check is None or check.retcode != 0:    # 0 means the request would be accepted
        print("order_check failed:", None if check is None else check.comment)
        return None
    result = mt5.order_send(request)           # the real order
    if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
        print("order_send failed:", None if result is None else result.comment)
        return None
    return int(result.order)                   # ticket of the executed order