#+------------------------------------------------------------------+
#| Imports                                                          |
#+------------------------------------------------------------------+
import joblib                                  # model persistence
from sklearn.linear_model import LogisticRegression    # simple, well-behaved classifier
from sklearn.pipeline import Pipeline          # bundles scaling and model together
from sklearn.preprocessing import StandardScaler       # standardizes the features

from market_data import FEATURE_COLUMNS, add_features, load_rates
from mt5_link import ConnectionSettings, MT5Link


#+------------------------------------------------------------------+
#| train                                                            |
#+------------------------------------------------------------------+
def train(symbol: str, timeframe: str, bars: int, model_path: str) -> float:
    data = add_features(load_rates(symbol, timeframe, bars)).copy()   # features on closed bars only
    data["target"] = (data["close"].shift(-1) > data["close"]).astype(int)   # 1 if the next close is higher
    data = data.iloc[:-1]                      # the last row has no next bar, so drop it
    split = int(len(data) * 0.8)               # chronological 80/20 split, no shuffling
    train_part = data.iloc[:split]             # older data for fitting
    test_part = data.iloc[split:]              # newer data for honest evaluation
    model = Pipeline([
        ("scaler", StandardScaler()),          # zero mean, unit variance per feature
        ("clf", LogisticRegression(max_iter=1000)),   # linear probabilistic classifier
    ])
    model.fit(train_part[FEATURE_COLUMNS], train_part["target"])
    accuracy = float(model.score(test_part[FEATURE_COLUMNS], test_part["target"]))   # out-of-sample accuracy
    joblib.dump(model, model_path)             # persist the whole pipeline
    return accuracy


#+------------------------------------------------------------------+
#| main                                                             |
#+------------------------------------------------------------------+
def main() -> int:
    link = MT5Link(ConnectionSettings())       # reuse the connection helper
    if not link.connect():
        return 1
    try:
        accuracy = train("EURUSD", "M15", 20000, "model.joblib")   # 20000 M15 bars of history
    finally:
        link.disconnect()
    print(f"Out-of-sample directional accuracy: {accuracy:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())