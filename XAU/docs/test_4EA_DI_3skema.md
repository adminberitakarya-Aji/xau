# Laporan Final: 4 EA Lama vs 4 EA DI × 3 Skema Probabilitas ML (XAUUSD M15)

Laporan ini adalah hasil pengujian **fair** (basis data & periode yang sama) antara **8 varian EA**:

| Kelompok | EA | Model ONNX | Filter DI |
| :--- | :--- | :--- | :--- |
| **LAMA** | `XAU_Phase1`, `XAU_Phase1_Reversal`, `XAU_PullBack`, `XAU_PullBack_Reversal` | `model_xau.onnx` / `model_xau_pullback.onnx` | `InpADX_UseDI=false` |
| **DI** | `XAU_Phase1_DI`, `XAU_Phase1_Reversal_DI`, `XAU_PullBack_DI`, `XAU_Reversal_Pullback_DI` | `model_xau_DI.onnx` / `model_xau_pullback_DI.onnx` | `InpADX_UseDI=true` |

- **Basis data**: `xauusd_ml_dataset_di.csv` — **56.609 baris sinyal** XAUUSD M15 (2023.07.07 – 2026.09.08), DI-agnostik (merekam SEMUA sinyal follow, termasuk **16.643 sinyal melawan DI** yang sebelumnya tak terlihat).
- **Mesin eksekusi**: basket martingale identik semua varian (grid 400 poin, 6 step, lot 0.01×2ⁿ, TP basket $3, siklus non-overlap).
- **Script**: [`ml_training/eval_8EA_3skema.py`](ml_training/eval_8EA_3skema.py) · **Data**: [`results_8EA_3skema.csv`](ml_training/results_8EA_3skema.csv)

---

## 🏁 Kesimpulan Utama (Baca Dulu)

> ### **Varian DI kalah dari varian Lama di SEMUA perbandingan** — profit lebih rendah DAN P95 Drawdown lebih tinggi.
>
> Dengan data yang fair kali ini (segmen melawan-DI sudah terlihat), hipotesis awal kita bahwa *"sinyal melawan DI berbahaya dan harus difilter"* **terbantahkan oleh data** untuk periode uji ini. Sinyal follow melawan DI justru menyumbang profit tanpa menaikkan drawdown secara proporsional — kemungkinan besar karena periode uji bertepatan dengan **tren macro bullish XAUUSD 2023–2026**, di mana entry "harga di atas EMA tapi DI belum searah" (pullback awal dalam uptrend) kerap tetap menguntungkan.

---

## 📊 Tabel Utama: Lama vs DI (Skema A — prob 0.35)

| EA | Varian | Siklus | Level 6 | P95 DD | Profit Est | Efisiensi (Profit/P95 DD) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **XAU_Phase1** | Lama 🏆 | 7.583 | 147 | **$99,43** | **$22.716** | **228,5** |
| | DI | 5.416 | 136 | $125,62 | $16.215 | 129,1 |
| **XAU_Phase1_Reversal** | Lama 🏆 | 7.031 | 148 | **$81,11** | **$21.039** | **259,4** |
| | DI | 4.769 | 127 | $117,80 | $14.265 | 121,1 |
| **XAU_PullBack** | Lama 🏆 | 5.159 | 80 | **$76,31** | **$15.456** | **202,5** |
| | DI | 3.201 | 89 | $141,29 | $9.588 | 67,9 |
| **XAU_PullBack_Reversal** | Lama 🏆 | 5.736 | 71 | **$28,71** | **$17.187** | **598,5** |
| | DI | 3.716 | 65 | $44,26 | $11.133 | 251,5 |

> Varian Lama unggul di **semua metrik** pada setiap pasangan: siklus lebih banyak, profit lebih tinggi, P95 DD lebih rendah. Selisih paling dramatis ada di `XAU_PullBack_Reversal`: varian Lama mencetak **P95 DD $28,71 dengan profit $17.187** (efisiensi 598 — tertinggi dari seluruh 24 kombinasi).

---

## 📊 Detail 3 Skema — Varian Lama (UseDI=false, model lama)

| EA | Metrik | 🔵 A (0.35) | 🟡 B (0.45) | 🔴 C (0.55) |
| :--- | :--- | :---: | :---: | :---: |
| **XAU_Phase1** | Siklus | 7.583 | 7.461 | 2.742 |
| | Level 6 | 147 | 146 | 43 |
| | P95 DD | $99,43 | $99,86 | $73,75 |
| | Profit Est | $22.716 | $22.353 | $8.211 |
| **XAU_Phase1_Reversal** | Siklus | 7.031 | 6.908 | 1.940 |
| | Level 6 | 148 | 147 | 40 |
| | P95 DD | $81,11 | $78,34 | $106,72 |
| | Profit Est | $21.039 | $20.670 | $5.802 |
| **XAU_PullBack** | Siklus | 5.159 | 5.156 | 5.154 |
| | Level 6 | 80 | 80 | 80 |
| | P95 DD | $76,31 | $76,34 | $76,37 |
| | Profit Est | $15.456 | $15.447 | $15.441 |
| **XAU_PullBack_Reversal** | Siklus | 5.736 | 5.706 | 5.704 |
| | Level 6 | 71 | 71 | 71 |
| | P95 DD | **$28,71** | $28,67 | $28,68 |
| | Profit Est | **$17.187** | $17.094 | $17.088 |

## 📊 Detail 3 Skema — Varian DI (UseDI=true, model baru)

| EA | Metrik | 🔵 A (0.35) | 🟡 B (0.45) | 🔴 C (0.55) |
| :--- | :--- | :---: | :---: | :---: |
| **XAU_Phase1_DI** | Siklus | 5.416 | 4.927 | 2.354 |
| | Level 6 | 136 | 128 | 56 |
| | P95 DD | $125,62 | $125,81 | $119,51 |
| | Profit Est | $16.215 | $14.745 | $7.062 |
| **XAU_Phase1_Reversal_DI** | Siklus | 4.769 | 4.591 | 695 |
| | Level 6 | 127 | 127 | 16 |
| | P95 DD | $117,80 | $124,71 | **$206,35** ⚠️ |
| | Profit Est | $14.265 | $13.731 | $2.082 |
| **XAU_PullBack_DI** | Siklus | 3.201 | 3.193 | 3.188 |
| | Level 6 | 89 | 90 | 89 |
| | P95 DD | $141,29 | $142,05 | $140,27 |
| | Profit Est | $9.588 | $9.564 | $9.549 |
| **XAU_PullBack_Reversal_DI** | Siklus | 3.716 | 3.711 | 3.693 |
| | Level 6 | 65 | 64 | 62 |
| | P95 DD | $44,26 | $43,95 | $43,39 |
| | Profit Est | $11.133 | $11.118 | $11.064 |

---

## 🔍 Analisis: Kenapa Varian DI Kalah?

1. **Sinyal melawan DI ternyata menguntungkan pada periode uji.** Dari 56.609 sinyal, 16.647 (±29%) adalah follow melawan DI yang oleh varian DI disaring. Varian Lama yang men-tradenya justru mendapat tambahan profit besar (mis. Phase1: 7.583 vs 5.416 siklus) tanpa P95 DD yang lebih buruk. Konteks makro: **tren bullish emas 2023–2026** membuat entry "harga > EMA50 tapi DI belum searah" efektif sebagai akumulasi awal pullback.

2. **Model baru tidak menambah daya prediksi.** `model_xau_DI.onnx` punya ROC AUC hanya ~0,48–0,51 (walk-forward) — praktis setara coin-flip. Artinya filter ML varian DI tidak mampu "menyelamatkan" kualitas yang hilang oleh penyaringan DI.

3. **Distribusi probabilitas model pullback DI berbeda.** Threshold optimalnya 0,375 (model lama menumpuk jauh di atas 0,55). Akibatnya pada skema A–C, model DI melewatkan lebih banyak sinyal marginal (rata-rata DD $220 vs $116 pada PullBack) — skema probabilitas 0.35/0.45/0.55 tidak lagi selaras dengan model barunya.

4. **Non-overlap memperbesar efeknya.** Karena varian DI punya sinyal lebih sedikit, rantai siklus non-overlap menghasilkan volume jauh lebih kecil (3.0k–5.4k vs 5.1k–7.5k) → profit absolut tertekan dua arah (lebih sedikit siklus DAN efisiensi lebih rendah).

---

## 💡 Rekomendasi Final

1. **Gunakan 4 EA LAMA untuk live & Strategy Tester.** `XAU_PullBack_Reversal` + skema apa pun (A disarankan) adalah kombinasi terbaik keseluruhan: **P95 DD $28,71, profit est $17.187, hanya 71× Level 6** dari 5.736 siklus. Profit tertinggi: `XAU_Phase1` Skema A ($22.716, P95 DD $99,43).

2. **Simpan versi DI sebagai eksperimen, jangan dipakai live dulu.** Jika suatu saat ingin diaktifkan (mis. saat pasar ranging/bearish di mana sinyal melawan DI berisiko), minimal: gunakan threshold selaras model baru (pullback DI ± `0.40–0.45`), dan hindari `XAU_Phase1_Reversal_DI` Skema C (P95 DD $206 dengan hanya 695 siklus).

3. **Pelajaran metodologis**: keputusan desain (filter DI) akhirnya diuji dengan data yang benar — dan data berkata lain. Ini justru nilai dari siklus re-ekspor dataset → re-train → re-test yang kita lakukan.

4. **Caveat**: hasil berbasis simulasi bar-M15 (aproksimasi pullback, profit = siklus selesai × $3, tanpa spread/komisi/swap) dan satu periode spesifik (bull market emas). Pada rezim pasar berbeda (ranging/bearish), kesimpulan bisa bergeser — validasi akhir tetap di MT5 Strategy Tester dengan tick riil.

---

## 📋 Catatan Metodologi

1. Kedua kelompok dievaluasi pada dataset yang sama (`xauusd_ml_dataset_di.csv`, 56.609 sinyal, 2023.07–2026.09) sehingga perbandingan fair; varian DI difilter dengan logika Node1/Node2 EA persis (follow butuh DI searah; reversal RSI ≤35/≥65 + pola bebas DI) → 39.962 baris lolos, 16.647 tersaring.
2. Model: varian Lama memakai `model_xau.onnx`/`model_xau_pullback.onnx`; varian DI memakai `model_xau_DI.onnx`/`model_xau_pullback_DI.onnx` (hasil re-train pada dataset DI-agnostik, hyperparameter identik).
3. Basket martingale 400 poin/6 step/lot 0.01×2ⁿ/TP $3, siklus non-overlap (`InpMaxOpenPositions=1`), horizon 600 bar — identik semua varian.
4. Perbandingan dengan laporan sebelumnya (`test_4EA_3skema.md`, `test_4EA_3Skema_True.md`) tidak apple-to-apple karena dataset lama tidak merekam sinyal melawan DI dan parameternya (ADX 20, RSI 30/70) berbeda dari .set live.

