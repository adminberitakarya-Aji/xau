"""
Script Training Machine Learning DI-AGNOSTIC untuk EA XAUUSD (Fase 2)
Copy dari train_model.py — perbedaan hanya sumber dataset & nama output ONNX.

Sumber dataset : xauusd_ml_dataset_di.csv (hasil Export_ML_Dataset_DI_Agnostic.mq5)
                 - Sinyal follow TANPA syarat arah DI (DI-agnostic)
                 - Deteksi selaras .set live (ADX >= 15, RSI 65/35)
Output         : model_xau_DI.onnx (19 fitur, skema & urutan sama -> kompatibel EA)

Model ini belajar dari sinyal searah DI DAN melawan DI, sehingga probabilitas
win bermakna untuk SEMUA segmen sinyal (menutup Out-Of-Distribution gap).

Hyperparameter identik dengan train_model.py agar perbandingan model lama vs
baru murni disebabkan perbedaan dataset.
"""

import os
import sys
import numpy as np
import pandas as pd
from sklearn.metrics import classification_report, roc_auc_score, confusion_matrix, precision_recall_curve
from xgboost import XGBClassifier
from onnxmltools import convert_xgboost
from onnxmltools.convert.common.data_types import FloatTensorType

# Fitur lengkap yang didukung (13 fitur dasar + 6 fitur konteks pasar baru)
ALL_FEATURE_COLS = [
    "dist_to_ema_atr",
    "adx_main",
    "adx_pdi",
    "adx_mdi",
    "adx_di_diff",
    "rsi",
    "atr_normalized",
    "body_atr",
    "upper_shadow_atr",
    "lower_shadow_atr",
    "hour",
    "day_of_week",
    "signal_type",
    # 6 Fitur Baru Konteks Pasar:
    "ema_slope_atr",
    "htf_trend",
    "volatility_ratio",
    "vol_ratio",
    "is_pinbar",
    "is_engulfing"
]

FEATURE_COLS = []

TARGET_COL = "label_win"

def load_data(csv_path: str):
    global FEATURE_COLS
    if not os.path.exists(csv_path):
        print(f"File {csv_path} tidak ditemukan!")
        print("Silakan jalankan script MQL5 Export_ML_Dataset_DI_Agnostic.mq5 terlebih dahulu,")
        print("lalu salin hasilnya (MQL5/Files/xauusd_ml_dataset_di.csv) ke folder ml_training/.")
        sys.exit(1)

    df = pd.read_csv(csv_path)
    print(f"Dataset berhasil dimuat: {df.shape[0]} baris, {df.shape[1]} kolom.")

    # Diagnostik segmen DI (hanya ada di dataset DI-agnostic):
    di_bull = df["adx_pdi"] > df["adx_mdi"]
    follow_buy = (df["signal_type"] == 1) & (df["dist_to_ema_atr"] > 0)
    follow_sell = (df["signal_type"] == 2) & (df["dist_to_ema_atr"] < 0)
    n_against = int(((follow_buy & ~di_bull) | (follow_sell & di_bull)).sum())
    print(f"  -> Sinyal follow MELAWAN DI yang kini terekam: {n_against:,} baris "
          f"(segmen yang sebelumnya Out-Of-Distribution)")

    # Deteksi otomatis fitur yang ada di CSV (13 fitur lama atau 19 fitur baru)
    available_cols = [c for c in ALL_FEATURE_COLS if c in df.columns]
    FEATURE_COLS = available_cols
    print(f"Fitur aktif untuk training ({len(FEATURE_COLS)} fitur): {FEATURE_COLS}")

    # Filter baris unresolved (label = -1) jika ada
    before = len(df)
    df = df[df[TARGET_COL] != -1].copy()
    if len(df) < before:
        print(f"  -> {before - len(df)} baris unresolved (label=-1) dibuang.")

    return df

def find_optimal_threshold(y_true, y_proba, min_precision=0.50):
    """
    Cari threshold optimal yang memaksimalkan F1 Win
    dengan syarat precision Win >= min_precision.
    """
    precisions, recalls, thresholds = precision_recall_curve(y_true, y_proba)
    best_threshold = 0.5
    best_f1 = 0.0

    for p, r, t in zip(precisions[:-1], recalls[:-1], thresholds):
        if p >= min_precision and (p + r) > 0:
            f1 = 2 * p * r / (p + r)
            if f1 > best_f1:
                best_f1 = f1
                best_threshold = t

    return best_threshold, best_f1

def walk_forward_cv(df, n_splits=5):
    """Walk-forward cross-validation untuk evaluasi time-series."""
    print(f"\n=== WALK-FORWARD CROSS VALIDATION ({n_splits} folds) ===")
    fold_size = len(df) // (n_splits + 1)
    auc_scores = []

    for fold in range(1, n_splits + 1):
        train_end = fold * fold_size
        test_end  = train_end + fold_size

        X_tr = df[FEATURE_COLS].iloc[:train_end].astype(np.float32)
        y_tr = df[TARGET_COL].iloc[:train_end].astype(int)
        X_te = df[FEATURE_COLS].iloc[train_end:test_end].astype(np.float32)
        y_te = df[TARGET_COL].iloc[train_end:test_end].astype(int)

        if len(y_te) == 0 or y_te.nunique() < 2:
            continue

        ratio = (y_tr == 0).sum() / max((y_tr == 1).sum(), 1)
        mdl = XGBClassifier(
            n_estimators=300,
            max_depth=5,
            learning_rate=0.05,
            subsample=0.8,
            colsample_bytree=0.8,
            scale_pos_weight=ratio,
            eval_metric="logloss",
            random_state=42,
            verbosity=0
        )
        mdl.fit(X_tr, y_tr)
        proba = mdl.predict_proba(X_te)[:, 1]
        auc = roc_auc_score(y_te, proba)
        auc_scores.append(auc)
        print(f"  Fold {fold}: train={len(X_tr):>6} | test={len(X_te):>5} | ROC AUC={auc:.4f}")

    print(f"  Mean AUC: {np.mean(auc_scores):.4f} +/- {np.std(auc_scores):.4f}")
    return np.mean(auc_scores)

def train_and_export(df: pd.DataFrame, output_onnx: str = "model_xau_DI.onnx"):
    X = df[FEATURE_COLS].astype(np.float32)
    y = df[TARGET_COL].astype(int)

    # Time-Series Split (80% Train, 20% Test)
    split_idx = int(len(df) * 0.8)
    X_train, X_test = X.iloc[:split_idx], X.iloc[split_idx:]
    y_train, y_test = y.iloc[:split_idx], y.iloc[split_idx:]

    print(f"Data Training: {len(X_train)} sampel | Data Testing: {len(X_test)} sampel")
    win_pct_train = y_train.mean() * 100
    win_pct_test  = y_test.mean() * 100
    print(f"Distribusi Win pada Train: {win_pct_train:.1f}% | Test: {win_pct_test:.1f}%")

    # scale_pos_weight = ratio Loss:Win untuk handle class imbalance
    scale_pos_weight = (y_train == 0).sum() / max((y_train == 1).sum(), 1)
    print(f"scale_pos_weight (Loss/Win ratio): {scale_pos_weight:.2f}")

    # Convert to numpy arrays for ONNX compatibility (onnxmltools expects f0..fn)
    X_train_np = X_train.values
    X_test_np = X_test.values
    y_train_np = y_train.values
    y_test_np = y_test.values

    # --- XGBoost Classifier (hyperparameter identik dengan train_model.py) ---
    model = XGBClassifier(
        n_estimators=100,
        max_depth=4,
        learning_rate=0.03,
        subsample=0.8,
        colsample_bytree=0.8,
        scale_pos_weight=scale_pos_weight,
        eval_metric="logloss",
        random_state=42,
        verbosity=0
    )

    print("\nMelatih model XGBoost DI-Agnostic...")
    model.fit(X_train_np, y_train_np)

    # Evaluasi dengan threshold default (0.5)
    y_proba = model.predict_proba(X_test_np)[:, 1]
    y_pred_default = (y_proba >= 0.5).astype(int)

    print("\n=== EVALUASI MODEL DI-AGNOSTIC (threshold=0.50) ===")
    print(classification_report(y_test, y_pred_default, target_names=["Loss", "Win"]))
    print(f"ROC AUC Score: {roc_auc_score(y_test, y_proba):.4f}")

    # Cari threshold optimal (precision Win >= 50%)
    best_thr, best_f1 = find_optimal_threshold(y_test, y_proba, min_precision=0.50)
    y_pred_tuned = (y_proba >= best_thr).astype(int)

    print(f"\n=== EVALUASI MODEL DI-AGNOSTIC (threshold={best_thr:.3f} - OPTIMAL) ===")
    print(classification_report(y_test, y_pred_tuned, target_names=["Loss", "Win"]))
    print(f"ROC AUC Score : {roc_auc_score(y_test, y_proba):.4f}")
    print(f"Best Threshold: {best_thr:.3f}")
    print(f"Best F1 (Win) : {best_f1:.4f}")

    print("\nConfusion Matrix (threshold optimal):")
    print(confusion_matrix(y_test, y_pred_tuned))

    # Feature Importance
    importances = pd.Series(model.feature_importances_, index=FEATURE_COLS).sort_values(ascending=False)
    print("\n=== TOP FEATURE IMPORTANCE (XGBoost gain) ===")
    for feat, imp in importances.items():
        bar = "=" * int(imp * 200)
        print(f"  - {feat:20s}: {imp*100:5.2f}% {bar}")

    # Walk-Forward Validation
    walk_forward_cv(df)

    # Ekspor ke ONNX
    print(f"\nMengekspor model ke format ONNX: {output_onnx} ...")
    initial_type = [('float_input', FloatTensorType([None, len(FEATURE_COLS)]))]
    onnx_model = convert_xgboost(model, initial_types=initial_type, target_opset=12)

    with open(output_onnx, "wb") as f:
        f.write(onnx_model.SerializeToString())

    print(f"Sukses! Model ONNX tersimpan di: {os.path.abspath(output_onnx)}")
    print(f"Jumlah Fitur Input : {len(FEATURE_COLS)}")
    print(f"Threshold Optimal  : {best_thr:.4f}  <-- update di EA jika perlu")
    print("Daftar Urutan Fitur Input:")
    for i, col in enumerate(FEATURE_COLS):
        print(f"  [{i}] {col}")

if __name__ == "__main__":
    csv_file = sys.argv[1] if len(sys.argv) > 1 else "xauusd_ml_dataset_di.csv"
    data = load_data(csv_file)
    train_and_export(data)

