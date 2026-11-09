#+------------------------------------------------------------------+
#| Imports                                                          |
#+------------------------------------------------------------------+
from dataclasses import dataclass              # lightweight settings container
from typing import Optional                    # explicit optional types

import MetaTrader5 as mt5                      # official MetaTrader 5 package


#+------------------------------------------------------------------+
#| ConnectionSettings                                               |
#+------------------------------------------------------------------+
@dataclass(frozen=True)
class ConnectionSettings:
    terminal_path: Optional[str] = None        # path to terminal64.exe, None = auto-detect
    login: Optional[int] = None                # account number, None = use the logged-in account
    password: Optional[str] = None             # account password, None = use the saved one
    server: Optional[str] = None               # broker server name
    timeout_ms: int = 60000                    # connection timeout in milliseconds


#+------------------------------------------------------------------+
#| MT5Link                                                          |
#+------------------------------------------------------------------+
class MT5Link:
    #+------------------------------------------------------------------+
    #| __init__                                                         |
    #+------------------------------------------------------------------+
    def __init__(self, settings: ConnectionSettings) -> None:
        self._settings = settings              # keep the settings for later reconnects
        self._connected = False                # True after a successful initialize()

    #+------------------------------------------------------------------+
    #| connect                                                          |
    #+------------------------------------------------------------------+
    def connect(self) -> bool:
        s = self._settings                     # short alias for readability
        kwargs: dict[str, object] = {"timeout": s.timeout_ms}   # timeout is always passed
        if s.login is not None and s.password is not None and s.server is not None:
            kwargs["login"] = s.login          # explicit account credentials
            kwargs["password"] = s.password
            kwargs["server"] = s.server
        if s.terminal_path:
            ok = mt5.initialize(s.terminal_path, **kwargs)   # start or attach to a given terminal
        else:
            ok = mt5.initialize(**kwargs)      # attach to the default terminal
        if not ok:
            print("initialize() failed, error:", mt5.last_error())
            return False
        self._connected = True
        return True

    #+------------------------------------------------------------------+
    #| disconnect                                                       |
    #+------------------------------------------------------------------+
    def disconnect(self) -> None:
        if self._connected:                    # shut down only what we started
            mt5.shutdown()                     # close the channel to the terminal
            self._connected = False

    #+------------------------------------------------------------------+
    #| account_summary                                                  |
    #+------------------------------------------------------------------+
    def account_summary(self) -> dict[str, object]:
        info = mt5.account_info()              # None if there is no account session
        if info is None:
            raise RuntimeError(f"account_info() failed: {mt5.last_error()}")
        return {
            "login": info.login,               # account number
            "server": info.server,             # trade server name
            "currency": info.currency,         # deposit currency
            "balance": info.balance,           # balance without floating profit
            "equity": info.equity,             # balance plus floating profit
            "leverage": info.leverage,         # account leverage
        }

    #+------------------------------------------------------------------+
    #| is_trading_allowed                                               |
    #+------------------------------------------------------------------+
    def is_trading_allowed(self) -> bool:
        info = mt5.terminal_info()             # terminal-wide state
        return bool(info is not None and info.trade_allowed)   # the Algo Trading button state


#+------------------------------------------------------------------+
#| main                                                             |
#+------------------------------------------------------------------+
def main() -> int:
    link = MT5Link(ConnectionSettings())       # default settings: use the running terminal
    if not link.connect():
        return 1                               # non-zero exit code signals failure
    try:
        print(link.account_summary())          # quick sanity check of the session
        print("Algo trading allowed:", link.is_trading_allowed())
    finally:
        link.disconnect()                      # always release the connection
    return 0


if __name__ == "__main__":
    raise SystemExit(main())