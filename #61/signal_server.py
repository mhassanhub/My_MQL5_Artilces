#+------------------------------------------------------------------+
#| Imports                                                          |
#+------------------------------------------------------------------+
import math                                    # finite-number checks
import socketserver                            # standard-library TCP server framework
from typing import Any                         # type of the loaded model

import joblib                                  # model loading
import pandas as pd                            # DataFrame for feature computation

from market_data import FEATURE_COLUMNS, add_features


#+------------------------------------------------------------------+
#| Server settings                                                  |
#+------------------------------------------------------------------+
HOST = "127.0.0.1"                             # listen on the loopback interface only
PORT = 9090                                    # must match the EA input
MODEL_PATH = "model.joblib"                    # artifact produced by train_model.py
BUY_THRESHOLD = 0.55                           # probability above this gives BUY
SELL_THRESHOLD = 0.45                          # probability below this gives SELL
MIN_CLOSES = 200                               # minimum history for stable indicators
MAX_REQUEST_BYTES = 65536                      # hard limit on the request line


#+------------------------------------------------------------------+
#| SignalHandler                                                    |
#+------------------------------------------------------------------+
class SignalHandler(socketserver.StreamRequestHandler):
    timeout = 5                                # seconds to wait for the request line
    model: Any = None                          # trained pipeline, injected in main()

    #+------------------------------------------------------------------+
    #| handle                                                           |
    #+------------------------------------------------------------------+
    def handle(self) -> None:
        raw = self.rfile.readline(MAX_REQUEST_BYTES)           # read one newline-terminated request
        line = raw.decode("ascii", errors="ignore").strip()    # tolerate stray bytes
        reply = self.build_reply(line)         # never raises, always returns a string
        self.wfile.write((reply + "\n").encode("ascii"))       # one-line reply

    #+------------------------------------------------------------------+
    #| build_reply                                                      |
    #+------------------------------------------------------------------+
    def build_reply(self, line: str) -> str:
        try:
            symbol, payload = line.split("|", 1)               # split header and data
            closes = [float(x) for x in payload.split(",") if x]   # parse the price list
        except ValueError:
            return "ERROR|bad request"
        if len(closes) < MIN_CLOSES:
            return "ERROR|not enough data"
        if not all(math.isfinite(c) for c in closes):          # reject nan and inf
            return "ERROR|invalid prices"
        features = add_features(pd.DataFrame({"close": closes}))   # same code path as training
        if features.empty:
            return "ERROR|no features"
        last_row = features[FEATURE_COLUMNS].iloc[[-1]]        # keep a DataFrame to preserve names
        probability_up = float(self.model.predict_proba(last_row)[0][1])   # P(next close is higher)
        if probability_up >= BUY_THRESHOLD:
            signal = "BUY"
        elif probability_up <= SELL_THRESHOLD:
            signal = "SELL"
        else:
            signal = "FLAT"                    # no edge, stay out
        print(f"{symbol}: {signal} (p_up={probability_up:.4f})")   # simple audit trail
        return f"{signal}|{probability_up:.4f}"


#+------------------------------------------------------------------+
#| main                                                             |
#+------------------------------------------------------------------+
def main() -> None:
    SignalHandler.model = joblib.load(MODEL_PATH)              # load once, reuse for every request
    socketserver.TCPServer.allow_reuse_address = True          # allow fast restarts
    with socketserver.TCPServer((HOST, PORT), SignalHandler) as server:
        print(f"Signal server listening on {HOST}:{PORT}")
        server.serve_forever()                 # runs until interrupted


if __name__ == "__main__":
    main()