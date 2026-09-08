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

def simulate_dist(data, min_prob, step_pts, max_marti=6, tp_usd=3.0, base_lot=0.01, mult=2.0, point=0.01):
    opens = data['open'].values
    highs = data['high'].values
    lows = data['low'].values
    sig_types = data['signal_type'].values
    prob_vals = data['prob'].values
    times = data['time'].values
    N = len(data)

    step_dist = step_pts * point
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
        i += 1

    cdf = pd.DataFrame(cycles)
    counts = cdf['max_level'].value_counts().sort_index()
    
    res = {
        'prob': min_prob,
        'step_pts': step_pts,
        'total_cycles': len(cdf),
        'deepest': cdf['max_level'].max(),
        'l0_pct': counts.get(0, 0) / len(cdf) * 100,
        'l1_pct': counts.get(1, 0) / len(cdf) * 100,
        'l2_pct': counts.get(2, 0) / len(cdf) * 100,
        'l3_pct': counts.get(3, 0) / len(cdf) * 100,
        'l4_pct': counts.get(4, 0) / len(cdf) * 100,
        'l5_pct': counts.get(5, 0) / len(cdf) * 100,
        'l6_pct': counts.get(6, 0) / len(cdf) * 100,
        'l6_count': counts.get(6, 0),
        'mean_dd': cdf['max_dd'].mean(),
        'median_dd': cdf['max_dd'].median(),
        'p95_dd': cdf['max_dd'].quantile(0.95),
        'max_dd': cdf['max_dd'].max()
    }
    return res

results = []
for dist in [350, 400, 450]:
    for p in [0.35, 0.45, 0.55]:
        r = simulate_dist(df, p, dist)
        results.append(r)
        print(f"Dist: {dist} pts | Prob >= {p} -> L0: {r['l0_pct']:.1f}% | L6: {r['l6_count']} ({r['l6_pct']:.2f}%) | P95 DD: ${r['p95_dd']:.2f} | Max DD: ${r['max_dd']:.2f}")

rdf = pd.DataFrame(results)
rdf.to_csv('results_dist_comparison.csv', index=False)
print("Selesai simulasi perbandingan jarak!")
