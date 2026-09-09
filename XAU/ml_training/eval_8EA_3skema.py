"""
Evaluasi Final: 4 EA Lama vs 4 EA DI x 3 Skema Probabilitas ML
==============================================================
Basis data yang sama untuk semua varian: xauusd_ml_dataset_di.csv
(DI-agnostic: merekam SEMUA sinyal follow termasuk yang melawan DI,
 parameter deteksi selaras .set live: ADX>=15, RSI 65/35)

Varian:
  - 4 EA LAMA : model lama (model_xau.onnx / model_xau_pullback.onnx),
                tanpa filter DI (InpADX_UseDI=false)
  - 4 EA DI   : model baru (model_xau_DI.onnx / model_xau_pullback_DI.onnx),
                filter DI aktif (InpADX_UseDI=true):
                follow butuh DI searah, reversal (RSI 35/65 + pola) bebas DI

Mesin basket martingale identik untuk semua (400 poin, 6 step, TP $3).
"""
import os
import sys
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_4EA_3skema import (
    load_model_probs, run_ea, MODEL_MAIN, MODEL_PB
)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATASET_DI = os.path.join(HERE, 'xauusd_ml_dataset_di.csv')
MODEL_DI_MAIN = os.path.join(ROOT, 'model_xau_DI.onnx')
MODEL_DI_PB = os.path.join(ROOT, 'model_xau_pullback_DI.onnx')
OUT_CSV = os.path.join(HERE, 'results_8EA_3skema.csv')


def main():
    df = pd.read_csv(DATASET_DI)
    print(f"Dataset DI-agnostic: {len(df)} baris sinyal ({df['time'].iloc[0]} s/d {df['time'].iloc[-1]})")

    print("[1/4] Inferensi model LAMA (model_xau.onnx) pada populasi penuh ...")
    pb1, ps1 = load_model_probs(MODEL_MAIN, df)
    print("[2/4] Inferensi model LAMA (model_xau_pullback.onnx) pada populasi penuh ...")
    pb2, ps2 = load_model_probs(MODEL_PB, df)

    # --- Filter InpADX_UseDI=true untuk varian DI (logika Node1/Node2 EA) ---
    di_bull = df['adx_pdi'] > df['adx_mdi']
    di_bear = df['adx_mdi'] > df['adx_pdi']
    follow_buy = (df['signal_type'] == 1) & (df['dist_to_ema_atr'] > 0)
    follow_sell = (df['signal_type'] == 2) & (df['dist_to_ema_atr'] < 0)
    rev_buy = (df['signal_type'] == 1) & (df['rsi'] <= 35) & ((df['is_pinbar'] == 1) | (df['is_engulfing'] == 1))
    rev_sell = (df['signal_type'] == 2) & (df['rsi'] >= 65) & ((df['is_pinbar'] == -1) | (df['is_engulfing'] == -1))
    keep = (follow_buy & di_bull) | (follow_sell & di_bear) | rev_buy | rev_sell
    df_di = df[keep].reset_index(drop=True)
    print(f"Varian DI (UseDI=true): {len(df_di)} baris lolos dari {len(df)} "
          f"(tersaring {len(df) - len(df_di)} sinyal follow melawan DI)")

    print("[3/4] Inferensi model DI (model_xau_DI.onnx) ...")
    dpb1, dps1 = load_model_probs(MODEL_DI_MAIN, df_di)
    print("[4/4] Inferensi model DI (model_xau_pullback_DI.onnx) ...")
    dpb2, dps2 = load_model_probs(MODEL_DI_PB, df_di)

    variants = [
        ('XAU_Phase1', 'phase1', pb1, ps1, df),
        ('XAU_Phase1_Reversal', 'phase_reversal', pb1, ps1, df),
        ('XAU_PullBack', 'pullback', pb2, ps2, df),
        ('XAU_PullBack_Reversal', 'reversal_pullback', pb2, ps2, df),
        ('XAU_Phase1_DI', 'phase1', dpb1, dps1, df_di),
        ('XAU_Phase1_Reversal_DI', 'phase_reversal', dpb1, dps1, df_di),
        ('XAU_PullBack_DI', 'pullback', dpb2, dps2, df_di),
        ('XAU_PullBack_Reversal_DI', 'reversal_pullback', dpb2, dps2, df_di),
    ]
    skemas = [('A (prob 0.35)', 0.35), ('B (prob 0.45)', 0.45), ('C (prob 0.55)', 0.55)]

    rows = []
    for ea_name, mode, prob_buy, prob_sell, data in variants:
        for sk_name, thr in skemas:
            print(f"Simulasi: {ea_name} | Skema {sk_name} ...")
            st = run_ea(data, thr, prob_buy, prob_sell, mode)
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
