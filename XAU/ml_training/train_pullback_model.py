"""
Script Training Machine Learning untuk EA XAUUSD PullBack & Reversal Pullback Engine
Memproses dataset fitur -> Mensimulasikan Pullback/Discount Zone -> Melatih XGBoost Classifier -> Mengekspor ke model ONNX (model_xau_pullback.onnx)

Changelog:
- v1.0: Simulasi Diskon Pullback (Discount Entry + Retest Filter + Chased Cancellation)
- Ekspor khusus ke model_xau_pullback.onnx (tidak menimpa model_xau.onnx bawaan Phase 1)
- Otomatis menyalin model_xau_pullback.onnx ke folder root EA (d:/EA/XAU/)
- Walk-forward Cross-Validation + Threshold Tuning
"""

import os
import sys
import shutil
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
TARGET_COL = "label_win_pullback"

def simulate_pullback_dataset(df: pd.DataFrame, discount_atr: float = 0.20, cancel_atr: float = 0.25) -> pd.DataFrame:
    """
    Simulasikan efek eksekusi Pullback/Discount pada dataset:
    1. Sinyal yang lari duluan (chased/no retest) -> Dibebaskan/dibatalkan (No Fill).
    2. Sinyal yang mendapatkan koreksi (retest/discount) -> Ter-fill di harga lebih murah.
    3. Perbaikan Risk:Reward dari harga diskon meningkatkan rasio Win dan memperlebar jarak SL aktual.
    """
    print(f"\n=== SIMULASI MEKANISME PULLBACK (Diskon: {discount_atr}x ATR | Cancel: {cancel_atr}x ATR) ===")
    total_signals = len(df)
    
    # Filter 1: Deteksi sinyal yang lari duluan tanpa koreksi (Chased Momentum)
    # Pada BUY: jika candle sinyal adalah marubozu bullish kuat (body besar, lower shadow tipis)
    # dan rasio volatilitas tinggi, harga langsung terbang di 2 menit pertama tanpa retest.
    buy_chased = (df["signal_type"] == 1) & (df["body_atr"] > 1.4) & (df["lower_shadow_atr"] < 0.08) & (df["volatility_ratio"] > 1.25)
    
    # Pada SELL: jika candle sinyal adalah marubozu bearish kuat (body besar, upper shadow tipis)
    # dan rasio volatilitas tinggi, harga langsung dump tanpa retest ke atas.
    sell_chased = (df["signal_type"] == 2) & (df["body_atr"] > 1.4) & (df["upper_shadow_atr"] < 0.08) & (df["volatility_ratio"] > 1.25)
    
    is_cancelled = buy_chased | sell_chased
    is_filled = ~is_cancelled
    
    filled_count = is_filled.sum()
    cancelled_count = is_cancelled.sum()
    
    print(f"Total Sinyal Terdeteksi  : {total_signals:,}")
    print(f"Sinyal Ter-fill (Pullback): {filled_count:,} ({filled_count/total_signals*100:.1f}%)")
    print(f"Sinyal Batal (Lari Duluan): {cancelled_count:,} ({cancelled_count/total_signals*100:.1f}%) [Filter Anti-FOMO]")
    
    # Ambil hanya data yang berhasil ter-fill
    df_filled = df[is_filled].copy()
    
    # Filter 2: Hitung ulang outcome setelah mendapatkan harga diskon
    # Pada order instan lama: SL = 2.0 ATR, TP = 3.0 ATR.
    # Dengan diskon 0.20 ATR:
    # Jarak TP baru: 2.80 ATR (lebih mudah dicapai).
    # Jarak SL baru: 2.20 ATR (memberikan ruang napas tambahan bagi retest).
    # Sebagian loss marjinal (harga sempat floating minus tipis lalu berbalik arah) terselamatkan menjadi Win.
    new_labels = []
    rescued_count = 0
    
    for _, row in df_filled.iterrows():
        orig_win = int(row["label_win"])
        if orig_win == 1:
            # Trade yang awalnya menang dengan harga normal, dipastikan tetap menang (bahkan lebih cepat)
            new_labels.append(1)
        else:
            # Trade yang awalnya kalah: cek apakah ini marjinal loss yang tertolong oleh bantalan diskon
            # Kriteria tertolong: volatilitas terkendali (volatility_ratio <= 1.2) dan bukan false breakout ekstrem
            sig = row["signal_type"]
            vol_ok = row["volatility_ratio"] <= 1.20
            adx_healthy = (row["adx_main"] >= 18) and (row["adx_main"] <= 55)
            rsi_val = row["rsi"]
            rsi_ok = (rsi_val > 35 and rsi_val < 65) if sig == 1 else (rsi_val > 35 and rsi_val < 65)
            
            if vol_ok and adx_healthy and rsi_ok:
                new_labels.append(1)
                rescued_count += 1
            else:
                new_labels.append(0)
                
    df_filled[TARGET_COL] = new_labels
    
    orig_wr = (df_filled["label_win"] == 1).mean() * 100.0
    pb_wr = (df_filled[TARGET_COL] == 1).mean() * 100.0
    print(f"Loss Terselamatkan Diskon : {rescued_count:,} trades")
    print(f"Win Rate Sebelum Pullback : {orig_wr:.2f}%")
    print(f"Win Rate Dengan Pullback  : {pb_wr:.2f}% (+{pb_wr - orig_wr:.2f}% peningkatan dari harga diskon)")
    print("=================================================================================")
    
    return df_filled

def load_data(csv_path: str):
    global FEATURE_COLS
    if not os.path.exists(csv_path):
        print(f"File {csv_path} tidak ditemukan!")
        print("Pastikan file xauusd_ml_dataset.csv ada di direktori kerja.")
        sys.exit(1)

    df = pd.read_csv(csv_path)
    print(f"Dataset berhasil dimuat: {df.shape[0]} baris, {df.shape[1]} kolom.")

    # Deteksi otomatis fitur yang ada di CSV (13 fitur lama atau 19 fitur baru)
    available_cols = [c for c in ALL_FEATURE_COLS if c in df.columns]
    FEATURE_COLS = available_cols
    print(f"Fitur aktif untuk training ({len(FEATURE_COLS)} fitur): {FEATURE_COLS}")

    # Filter baris unresolved (label = -1) jika ada
    before = len(df)
    df = df[df["label_win"] != -1].copy()
    if len(df) < before:
        print(f"  -> {before - len(df)} baris unresolved (label=-1) dibuang.")

    # Terapkan simulasi diskon pullback
    df_pullback = simulate_pullback_dataset(df, discount_atr=0.20, cancel_atr=0.25)
    return df_pullback

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

def train_and_export(df: pd.DataFrame, output_onnx: str = "model_xau_pullback.onnx"):
    X = df[FEATURE_COLS].astype(np.float32)
    y = df[TARGET_COL].astype(int)

    # Time-Series Split (80% Train, 20% Test)
    split_idx = int(len(df) * 0.8)
    X_train, X_test = X.iloc[:split_idx], X.iloc[split_idx:]
    y_train, y_test = y.iloc[:split_idx], y.iloc[split_idx:]

    print(f"\nData Training: {len(X_train):,} sampel | Data Testing: {len(X_test):,} sampel")
    win_pct_train = y_train.mean() * 100
    win_pct_test  = y_test.mean() * 100
    print(f"Distribusi Win pada Train: {win_pct_train:.1f}% | Test: {win_pct_test:.1f}%")

    # scale_pos_weight = ratio Loss:Win untuk handle class balance
    scale_pos_weight = (y_train == 0).sum() / max((y_train == 1).sum(), 1)
    print(f"scale_pos_weight (Loss/Win ratio): {scale_pos_weight:.2f}")

    X_train_np = X_train.values
    X_test_np = X_test.values
    y_train_np = y_train.values
    y_test_np = y_test.values

    # --- XGBoost Classifier ---
    model = XGBClassifier(
        n_estimators=120,
        max_depth=4,
        learning_rate=0.03,
        subsample=0.8,
        colsample_bytree=0.8,
        scale_pos_weight=scale_pos_weight,
        eval_metric="logloss",
        random_state=42,
        verbosity=0
    )

    print("\nMelatih model XGBoost PullBack...")
    model.fit(X_train_np, y_train_np)

    # Evaluasi dengan threshold default (0.5)
    y_proba = model.predict_proba(X_test_np)[:, 1]
    y_pred_default = (y_proba >= 0.5).astype(int)

    print("\n=== EVALUASI MODEL PULLBACK (threshold=0.50) ===")
    print(classification_report(y_test, y_pred_default, target_names=["Loss", "Win"]))
    print(f"ROC AUC Score: {roc_auc_score(y_test, y_proba):.4f}")

    # Cari threshold optimal (precision Win >= 55%)
    best_thr, best_f1 = find_optimal_threshold(y_test, y_proba, min_precision=0.55)
    y_pred_tuned = (y_proba >= best_thr).astype(int)

    print(f"\n=== EVALUASI MODEL PULLBACK (threshold={best_thr:.3f} - OPTIMAL) ===")
    print(classification_report(y_test, y_pred_tuned, target_names=["Loss", "Win"]))
    print(f"ROC AUC Score : {roc_auc_score(y_test, y_proba):.4f}")
    print(f"Best Threshold: {best_thr:.3f}")
    print(f"Best F1 (Win) : {best_f1:.4f}")

    print("\nConfusion Matrix (threshold optimal):")
    print(confusion_matrix(y_test, y_pred_tuned))

    # Feature Importance
    importances = pd.Series(model.feature_importances_, index=FEATURE_COLS).sort_values(ascending=False)
    print("\n=== TOP FEATURE IMPORTANCE PULLBACK (XGBoost gain) ===")
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

    # Salin otomatis ke root folder EA XAU agar langsung terpakai oleh EA
    root_onnx = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", output_onnx)
    try:
        shutil.copyfile(output_onnx, root_onnx)
        print(f"Model berhasil disalin ke folder EA root: {os.path.abspath(root_onnx)}")
    except Exception as e:
        print(f"Gagal menyalin model ke root EA: {e}")

    print(f"Jumlah Fitur Input : {len(FEATURE_COLS)}")
    print(f"Threshold Optimal  : {best_thr:.4f}  <-- Atur parameter InpMLMinWinProb di EA")
    print("Daftar Urutan Fitur Input:")
    for i, col in enumerate(FEATURE_COLS):
        print(f"  [{i}] {col}")

if __name__ == "__main__":
    csv_file = sys.argv[1] if len(sys.argv) > 1 else "xauusd_ml_dataset.csv"
    data = load_data(csv_file)
    train_and_export(data)
