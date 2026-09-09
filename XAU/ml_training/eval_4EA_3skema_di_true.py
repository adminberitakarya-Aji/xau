"""
Evaluasi Varian InpADX_UseDI=TRUE — 4 EA x 3 Skema Probabilitas ML
===================================================================
Mereplikasi perilaku keempat EA ketika InpADX_UseDI=true:
  - Node 1 (FOLLOW TREND) diperketat: BUY butuh +DI > -DI, SELL butuh -DI > +DI
  - Node 2 (REVERSAL: RSI ekstrem + pinbar/engulfing, threshold .set 35/65) TIDAK terpengaruh DI

Klasifikasi baris dataset (mengikuti else-if chain Export_ML_Dataset.mq5):
  - Follow Buy  : signal_type=1 & dist_to_ema_atr > 0
  - Follow Sell : signal_type=2 & dist_to_ema_atr < 0
  - Reversal    : sisanya (sinyal RSI ekstrem + pola candle)

Baris dipertahankan jika:
  (follow & DI searah) ATAU (kondisi reversal EA terpenuhi)
"""
import os
import sys
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_4EA_3skema import (
    load_model_probs, run_ea, DATASET, MODEL_MAIN, MODEL_PB
)

OUT_CSV = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results_4EA_3skema_di_true.csv')


def main():
    df = pd.read_csv(DATASET)
    print(f"Dataset: {len(df)} baris sinyal ({df['time'].iloc[0]} s/d {df['time'].iloc[-1]})")

    # --- Replikasi filter InpADX_UseDI=true (Node 1 saja) ---
    di_bull = df['adx_pdi'] > df['adx_mdi']
    di_bear = df['adx_mdi'] > df['adx_pdi']
    follow_buy = (df['signal_type'] == 1) & (df['dist_to_ema_atr'] > 0)
    follow_sell = (df['signal_type'] == 2) & (df['dist_to_ema_atr'] < 0)
    # Kondisi reversal menurut EA (.set: RSI 35/65 + pinbar/engulfing) — bebas DI
    rev_buy = (df['signal_type'] == 1) & (df['rsi'] <= 35) & ((df['is_pinbar'] == 1) | (df['is_engulfing'] == 1))
    rev_sell = (df['signal_type'] == 2) & (df['rsi'] >= 65) & ((df['is_pinbar'] == -1) | (df['is_engulfing'] == -1))

    keep = (follow_buy & di_bull) | (follow_sell & di_bear) | rev_buy | rev_sell
    print(f"Baris lolos UseDI=true: {keep.sum()} dari {len(df)} (gugur: {(~keep).sum()})")
    print(f"  - Follow Buy gugur : {(follow_buy & ~di_bull).sum()}")
    print(f"  - Follow Sell gugur: {(follow_sell & ~di_bear).sum()}")

    df2 = df[keep].reset_index(drop=True)

    print("Inferensi model_xau.onnx ...")
    pb1, ps1 = load_model_probs(MODEL_MAIN, df2)
    print("Inferensi model_xau_pullback.onnx ...")
    pb2, ps2 = load_model_probs(MODEL_PB, df2)

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
            print(f"Simulasi: {ea_name} | Skema {sk_name} [UseDI=true] ...")
            st = run_ea(df2, thr, prob_buy, prob_sell, mode)
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
