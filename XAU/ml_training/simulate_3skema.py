import pandas as pd
import numpy as np
import onnxruntime as ort

session = ort.InferenceSession('model_xau.onnx')
df = pd.read_csv('xauusd_ml_dataset.csv')
from train_model import ALL_FEATURE_COLS
cols = [c for c in ALL_FEATURE_COLS if c in df.columns]
X = df[cols].astype(np.float32).values

probs = []
for i in range(0, len(X), 1000):
    probs.extend(session.run(None, {'float_input': X[i:i+1000]})[1][:, 1])
df['prob'] = np.array(probs)

def run_simulation(data, min_prob, step_pts=400, max_marti=6, tp_usd=3.0, base_lot=0.01, mult=2.0, point=0.01):
    opens = data['open'].values
    highs = data['high'].values
    lows = data['low'].values
    closes = data['close'].values
    sig_types = data['signal_type'].values
    prob_vals = data['prob'].values
    times = data['time'].values
    N = len(data)

    step_dist = step_pts * point  # 400 * 0.01 = 4.0 USD harga emas
    lots = [round(base_lot * (mult ** s), 2) for s in range(max_marti + 1)]

    cycles = []
    i = 0
    while i < N - 1:
        if prob_vals[i] < min_prob or sig_types[i] == 0:
            i += 1
            continue

        direction = 1 if sig_types[i] == 1 else -1
        entry_idx = i + 1
        if entry_idx >= N:
            break

        positions = [(opens[entry_idx], lots[0])]
        cur_level = 0
        max_level_reached = 0
        cycle_start_time = times[entry_idx]
        resolved = False
        max_floating_dd = 0.0

        for k in range(entry_idx, min(entry_idx + 600, N)):
            h = highs[k]
            l = lows[k]
            c = closes[k]

            best_p = h if direction == 1 else l
            tot_tp_usd = sum((best_p - p) * 100 * lt * direction for p, lt in positions)
            if tot_tp_usd >= tp_usd:
                resolved = True
                i = k
                break

            worst_p = l if direction == 1 else h
            worst_dd = sum((worst_p - p) * 100 * lt * direction for p, lt in positions)
            if worst_dd < max_floating_dd:
                max_floating_dd = worst_dd

            last_entry_p = positions[-1][0]
            if cur_level < max_marti:
                next_trigger_p = last_entry_p - step_dist if direction == 1 else last_entry_p + step_dist
                is_triggered = (l <= next_trigger_p) if direction == 1 else (h >= next_trigger_p)
                if is_triggered:
                    cur_level += 1
                    if cur_level > max_level_reached:
                        max_level_reached = cur_level
                    positions.append((next_trigger_p, lots[cur_level]))

        cycles.append({
            'max_level': max_level_reached,
            'max_dd': abs(max_floating_dd),
            'resolved': resolved,
            'start_time': cycle_start_time
        })
        if not resolved:
            i += 1
        else:
            i += 1

    cdf = pd.DataFrame(cycles)
    print(f"=== SKEMA (Prob >= {min_prob}) ===")
    print(f"Total Siklus Selesai: {len(cdf)}")
    print(f"Level Terdalam: Level {cdf['max_level'].max()}")
    print(f"Max Floating Drawdown: ${cdf['max_dd'].max():.2f}")
    print(f"Rata-rata Drawdown: ${cdf['max_dd'].mean():.2f}")
    counts = cdf['max_level'].value_counts().sort_index()
    for lvl in range(max_marti + 1):
        cnt = counts.get(lvl, 0)
        pct = (cnt / len(cdf)) * 100 if len(cdf) > 0 else 0
        print(f"  Level {lvl}: {cnt} ({pct:.2f}%)")
    print(f"Hit Max Step (Level 6): {(cdf['max_level'] == max_marti).sum()} kali\n")
    return cdf

res_a = run_simulation(df, 0.35)
res_b = run_simulation(df, 0.45)
res_c = run_simulation(df, 0.55)
