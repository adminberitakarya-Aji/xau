"""
Evaluasi Komparatif 4 EA x 3 Skema Probabilitas ML (0.35 / 0.45 / 0.55)
=======================================================================
Replikasi logika 4 EA pada dataset historis XAUUSD M15:
  1. XAU_Phase1            : Sinyal searah + ML model_xau.onnx + entry instan
  2. XAU_Phase_Reversal    : Sinyal dibalik (inverse mapping) + ML model_xau.onnx + entry instan
  3. XAU_PullBack          : Sinyal searah + ML model_xau_pullback.onnx + entry diskon pullback 0.20 ATR
  4. XAU_Reversal_Pullback : Sinyal dibalik (contrarian) + ML model_xau_pullback.onnx + entry konfirmasi bounce

Mesin eksekusi basket martingale identik untuk semua EA (sesuai file .set):
  - Jarak grid 400 poin, maksimal 6 step, lot 0.01 x 2^n, TP basket $3.0
"""
import os
import sys
import pandas as pd
import numpy as np
import onnxruntime as ort

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

DATASET = os.path.join(HERE, 'xauusd_ml_dataset.csv')
MODEL_MAIN = os.path.join(ROOT, 'model_xau.onnx')
MODEL_PB = os.path.join(ROOT, 'model_xau_pullback.onnx')
OUT_CSV = os.path.join(HERE, 'results_4EA_3skema.csv')

ALL_FEATURE_COLS = [
    "dist_to_ema_atr", "adx_main", "adx_pdi", "adx_mdi", "adx_di_diff",
    "rsi", "atr_normalized", "body_atr", "upper_shadow_atr", "lower_shadow_atr",
    "hour", "day_of_week", "signal_type",
    "ema_slope_atr", "htf_trend", "volatility_ratio", "vol_ratio",
    "is_pinbar", "is_engulfing"
]

# Parameter basket martingale (identik utk semua skema .set)
STEP_PTS = 400.0
POINT = 0.01
MAX_MARTI = 6
TP_USD = 3.0
BASE_LOT = 0.01
MULT = 2.0
HORIZON = 600

# Parameter pullback engine (default EA)
PB_ATR_MULT = 0.20      # diskon / konfirmasi
CANCEL_ATR_MULT = 0.25  # batas anti-FOMO


def load_model_probs(model_path: str, df: pd.DataFrame):
    """Hitung probabilitas win untuk kedua arah (signal_type=1 Buy, 2 Sell) di setiap bar."""
    sess = ort.InferenceSession(model_path)
    cols = [c for c in ALL_FEATURE_COLS if c in df.columns]
    X_base = df[cols].astype(np.float32).reset_index(drop=True)

    out = {}
    for st in (1, 2):
        X = X_base.copy()
        X["signal_type"] = np.float32(st)
        probs = []
        for i in range(0, len(X), 2000):
            chunk = X.iloc[i:i + 2000].values
            probs.extend(sess.run(None, {'float_input': chunk})[1][:, 1])
        out[st] = np.array(probs, dtype=np.float64)
    return out[1], out[2]


def simulate_basket(opens, highs, lows, entry_idx, direction, entry_price):
    """Simulasi basket martingale dari satu entry. Return dict hasil siklus."""
    step_dist = STEP_PTS * POINT
    lots = [round(BASE_LOT * (MULT ** s), 2) for s in range(MAX_MARTI + 1)]
    N = len(opens)

    positions = [(entry_price, lots[0])]
    cur_level = 0
    max_level = 0
    max_dd = 0.0
    resolved = False
    bars_used = 0

    for k in range(entry_idx, min(entry_idx + HORIZON, N)):
        h = highs[k]
        l = lows[k]
        bars_used = k - entry_idx + 1

        best_p = h if direction == 1 else l
        tot_tp = sum((best_p - p) * 100 * lt * direction for p, lt in positions)
        if tot_tp >= TP_USD:
            resolved = True
            break

        worst_p = l if direction == 1 else h
        worst_dd = sum((worst_p - p) * 100 * lt * direction for p, lt in positions)
        if worst_dd < max_dd:
            max_dd = worst_dd

        last_entry_p = positions[-1][0]
        if cur_level < MAX_MARTI:
            trigger = last_entry_p - step_dist if direction == 1 else last_entry_p + step_dist
            hit = (l <= trigger) if direction == 1 else (h >= trigger)
            if hit:
                cur_level += 1
                if cur_level > max_level:
                    max_level = cur_level
                positions.append((trigger, lots[cur_level]))

    return {
        'max_level': max_level,
        'max_dd': abs(max_dd),
        'resolved': resolved,
        'bars': bars_used,
    }


def run_ea(df, min_prob, prob_buy, prob_sell, mode):
    """
    mode: 'phase1' | 'phase_reversal' | 'pullback' | 'reversal_pullback'
    Mengembalikan dict statistik agregat.
    """
    opens = df['open'].values
    highs = df['high'].values
    lows = df['low'].values
    sig = df['signal_type'].values
    atr_price = df['atr_normalized'].values * df['close'].values / 1000.0
    N = len(df)

    cycles = []
    n_cancel = 0   # batal anti-FOMO (harga lari duluan)
    n_nofill = 0   # hangus timeout (tidak pernah menyentuh target pullback)

    i = 0
    while i < N:
        st = sig[i]
        if st == 0:
            i += 1
            continue

        # --- Penentuan arah & filter ML (sesuai logika tiap EA) ---
        if mode in ('phase1', 'pullback'):
            direction = 1 if st == 1 else -1
            prob = prob_buy[i] if st == 1 else prob_sell[i]
        else:  # reversal: kondisi bullish -> SELL, bearish -> BUY
            direction = -1 if st == 1 else 1
            prob = prob_sell[i] if st == 1 else prob_buy[i]

        if prob < min_prob:
            i += 1
            continue

        entry_idx = i + 1
        if entry_idx >= N:
            break

        # --- Eksekusi entry ---
        ref = opens[entry_idx]
        atrv = atr_price[i]
        if mode in ('pullback', 'reversal_pullback'):
            disc = atrv * PB_ATR_MULT
            cancel = atrv * CANCEL_ATR_MULT
            if mode == 'pullback':
                # BUY: diskon di bawah; batal jika harga lari ke atas
                if direction == 1:
                    target = ref - disc
                    cancel_lvl = ref + cancel
                    if highs[entry_idx] >= cancel_lvl:
                        n_cancel += 1; i += 1; continue
                    if opens[entry_idx] <= target:
                        entry_price = opens[entry_idx]      # gap turun: fill lebih murah
                    elif lows[entry_idx] <= target:
                        entry_price = target                # retest tercapai
                    else:
                        n_nofill += 1; i += 1; continue     # hangus (timeout)
                # SELL: diskon di atas; batal jika harga dump ke bawah
                else:
                    target = ref + disc
                    cancel_lvl = ref - cancel
                    if lows[entry_idx] <= cancel_lvl:
                        n_cancel += 1; i += 1; continue
                    if opens[entry_idx] >= target:
                        entry_price = opens[entry_idx]
                    elif highs[entry_idx] >= target:
                        entry_price = target
                    else:
                        n_nofill += 1; i += 1; continue
            else:
                # Contrarian: BUY menunggu bounce NAIK dulu; SELL menunggu turun dulu
                if direction == 1:
                    target = ref + disc
                    cancel_lvl = ref - cancel
                    if lows[entry_idx] <= cancel_lvl:
                        n_cancel += 1; i += 1; continue
                    if opens[entry_idx] >= target:
                        entry_price = opens[entry_idx]
                    elif highs[entry_idx] >= target:
                        entry_price = target                # konfirmasi bounce
                    else:
                        n_nofill += 1; i += 1; continue
                else:
                    target = ref - disc
                    cancel_lvl = ref + cancel
                    if highs[entry_idx] >= cancel_lvl:
                        n_cancel += 1; i += 1; continue
                    if opens[entry_idx] <= target:
                        entry_price = opens[entry_idx]
                    elif lows[entry_idx] <= target:
                        entry_price = target
                    else:
                        n_nofill += 1; i += 1; continue
        else:
            entry_price = ref  # entry instan di open bar berikutnya

        res = simulate_basket(opens, highs, lows, entry_idx, direction, entry_price)
        res['start_time'] = df['time'].iloc[i]
        cycles.append(res)
        # EA hanya izinkan 1 posisi terbuka (InpMaxOpenPositions=1):
        # sinyal baru diabaikan selama basket siklus ini masih berjalan.
        i = max(i, entry_idx + res['bars'] - 1)
        i += 1

    if len(cycles) == 0:
        return None
    cdf = pd.DataFrame(cycles)
    counts = cdf['max_level'].value_counts().sort_index()
    total = len(cdf)
    stats = {
        'total_cycles': total,
        'pb_cancelled': n_cancel,
        'pb_nofill': n_nofill,
        'l0': counts.get(0, 0), 'l1': counts.get(1, 0), 'l2': counts.get(2, 0),
        'l3': counts.get(3, 0), 'l4': counts.get(4, 0), 'l5': counts.get(5, 0),
        'l6': counts.get(6, 0),
        'l0_pct': counts.get(0, 0) / total * 100,
        'l6_pct': counts.get(6, 0) / total * 100,
        'deepest': int(cdf['max_level'].max()),
        'mean_dd': cdf['max_dd'].mean(),
        'median_dd': cdf['max_dd'].median(),
        'p95_dd': cdf['max_dd'].quantile(0.95),
        'max_dd': cdf['max_dd'].max(),
        'resolved_pct': cdf['resolved'].mean() * 100,
        'unresolved': int((~cdf['resolved']).sum()),
        'avg_bars': cdf['bars'].mean(),
        'est_profit': cdf['resolved'].sum() * TP_USD,
    }
    return stats



def main():
    df = pd.read_csv(DATASET)
    print(f"Dataset: {len(df)} baris sinyal ({df['time'].iloc[0]} s/d {df['time'].iloc[-1]})")

    print("Inferensi model_xau.onnx ...")
    pb1, ps1 = load_model_probs(MODEL_MAIN, df)
    print("Inferensi model_xau_pullback.onnx ...")
    pb2, ps2 = load_model_probs(MODEL_PB, df)

    eas = [
        ('XAU_Phase1', 'phase1', pb1, ps1),
        ('XAU_Phase1_Reversal', 'phase_reversal', pb1, ps1),
        ('XAU_PullBack', 'pullback', pb2, ps2),
        ('XAU_PullBack_Reversal', 'reversal_pullback', pb2, ps2),
    ]
    skemas = [('A (prob 0.35)', 0.35), ('B (prob 0.45)', 0.45), ('C (prob 0.55)', 0.55)]

    rows = []
    for ea_name, mode, prob_buy, prob_sell in eas:
        for sk_name, thr in skemas:
            print(f"Simulasi: {ea_name} | Skema {sk_name} ...")
            st = run_ea(df, thr, prob_buy, prob_sell, mode)
            st.update({'ea': ea_name, 'skema': sk_name, 'min_prob': thr})
            rows.append(st)
            print(f"   -> Siklus: {st['total_cycles']}, L6: {st['l6']}x, "
                  f"P95 DD: ${st['p95_dd']:.2f}, Profit est: ${st['est_profit']:.0f}")

    out = pd.DataFrame(rows)[[
        'ea', 'skema', 'min_prob', 'total_cycles', 'pb_cancelled', 'pb_nofill',
        'l0', 'l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'l0_pct', 'l6_pct',
        'deepest', 'mean_dd', 'median_dd', 'p95_dd', 'max_dd',
        'resolved_pct', 'unresolved', 'avg_bars', 'est_profit']]
    out.to_csv(OUT_CSV, index=False)
    print(f"\nHasil disimpan: {OUT_CSV}")
    print(out.to_string(index=False))


if __name__ == '__main__':
    main()

