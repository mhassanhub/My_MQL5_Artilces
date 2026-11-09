#+------------------------------------------------------------------+
#| Imports                                                          |
#+------------------------------------------------------------------+
import MetaTrader5 as mt5                      # official MetaTrader 5 package
import numpy as np                             # numerical helpers
import pandas as pd                            # tabular data structures


#+------------------------------------------------------------------+
#| Module constants                                                 |
#+------------------------------------------------------------------+
TIMEFRAMES = {                                 # readable names mapped to MT5 constants
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
}
FEATURE_COLUMNS = ["ema_spread", "rsi", "ret_1"]   # model inputs, same order in training and serving
RSI_PERIOD = 14                                # Wilder smoothing length
EMA_FAST = 12                                  # fast EMA span
EMA_SLOW = 26                                  # slow EMA span


#+------------------------------------------------------------------+
#| load_rates                                                       |
#+------------------------------------------------------------------+
def load_rates(symbol: str, timeframe: str, count: int) -> pd.DataFrame:
    if timeframe not in TIMEFRAMES:            # reject unknown timeframe names early
        raise ValueError(f"Unsupported timeframe: {timeframe}")
    if not mt5.symbol_select(symbol, True):    # make sure the symbol is in Market Watch
        raise RuntimeError(f"symbol_select failed for {symbol}: {mt5.last_error()}")
    rates = mt5.copy_rates_from_pos(symbol, TIMEFRAMES[timeframe], 1, count)   # start at bar 1 = last closed bar
    if rates is None or len(rates) == 0:       # None means an error, empty means no data
        raise RuntimeError(f"copy_rates_from_pos failed: {mt5.last_error()}")
    frame = pd.DataFrame(rates)                # structured numpy array to DataFrame
    frame["time"] = pd.to_datetime(frame["time"], unit="s")   # broker server time, kept naive
    return frame.set_index("time")             # time becomes the index


#+------------------------------------------------------------------+
#| add_features                                                     |
#+------------------------------------------------------------------+
def add_features(frame: pd.DataFrame) -> pd.DataFrame:
    out = frame.copy()                         # never modify the caller's data
    close = out["close"]                       # the only column the features need
    ema_fast = close.ewm(span=EMA_FAST, adjust=False).mean()   # fast exponential average
    ema_slow = close.ewm(span=EMA_SLOW, adjust=False).mean()   # slow exponential average
    out["ema_spread"] = (ema_fast - ema_slow) / close          # trend strength, scale-free
    delta = close.diff()                       # bar-to-bar price change
    gain = delta.clip(lower=0.0)               # positive moves only
    loss = -delta.clip(upper=0.0)              # negative moves as positive numbers
    avg_gain = gain.ewm(alpha=1.0 / RSI_PERIOD, adjust=False).mean()   # Wilder smoothing of gains
    avg_loss = loss.ewm(alpha=1.0 / RSI_PERIOD, adjust=False).mean()   # Wilder smoothing of losses
    rs = avg_gain / avg_loss.replace(0.0, np.nan)              # avoid division by zero
    out["rsi"] = 100.0 - 100.0 / (1.0 + rs)    # relative strength index
    out["ret_1"] = close.pct_change()          # one-bar return
    return out.dropna()                        # drop warm-up rows with undefined values