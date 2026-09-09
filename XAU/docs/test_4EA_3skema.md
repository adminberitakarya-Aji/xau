# Laporan Uji 4 EA × 3 Skema Probabilitas ML — XAUUSD M15 (Basket Martingale 400 Poin)

Laporan ini menyajikan hasil simulasi kuantitatif komparatif untuk **4 EA** (`XAU_Phase1`, `XAU_Phase1_Reversal`, `XAU_PullBack`, `XAU_PullBack_Reversal`) menggunakan **3 Skema Probabilitas ML** dari file setting (`skema_A_prob35.set`, `skema_B_prob45.set`, `skema_C_prob55.set`) terhadap data historis XAUUSD M15 (**46.345 bar sinyal**, periode 2023.02.02 – 2026.09.04).

- **Script simulasi**: [`ml_training/eval_4EA_3skema.py`](ml_training/eval_4EA_3skema.py)
- **Data mentah**: [`ml_training/results_4EA_3skema.csv`](ml_training/results_4EA_3skema.csv)

---

## 🎯 Parameter Pengujian

**Setting umum (identik di ketiga file .set):**

| Parameter | Nilai |
| :--- | :--- |
| Lot Awal (Base Lot) | `0.01` |
| Pengali Martingale | `2.0x` |
| Ladder Lot | `0.01` → `0.02` → `0.04` → `0.08` → `0.16` → `0.32` → `0.64` (Maks 6 Step, akumulasi 1.27 lot) |
| Jarak Grid Martingale | `400 poin` ($4.00) |
| Target Profit Basket (TP) | `$3.0` |
| Maks Posisi Terbuka | `1` (siklus tidak tumpang tindih — sinyal baru diabaikan selama basket berjalan) |

**Yang membedakan ketiga skema hanya threshold ML filter (`InpMLMinWinProb`):**

| Skema | Threshold ML | Karakter |
| :--- | :--- | :--- |
| 🔵 Skema A | `0.35` | Paling longgar, sinyal terbanyak |
| 🟡 Skema B | `0.45` | Moderat |
| 🔴 Skema C | `0.55` | Paling ketat, sinyal paling sedikit |

**Karakteristik eksekusi tiap EA (direplikasi dari source .mq5):**

| EA | Model ONNX | Arah Trade | Eksekusi Entry |
| :--- | :--- | :--- | :--- |
| `XAU_Phase1` | `model_xau.onnx` | Searah kondisi (trend/momentum) | Instan di open bar berikutnya |
| `XAU_Phase1_Reversal` | `model_xau.onnx` | **Dibalik** (bullish → SELL, bearish → BUY), ML menguji prob arah yang dibuka | Instan di open bar berikutnya |
| `XAU_PullBack` | `model_xau_pullback.onnx` | Searah kondisi | Diskon pullback `0.20×ATR`; batal anti-FOMO jika harga lari `0.25×ATR`; hangus jika retest tidak tercapai |
| `XAU_PullBack_Reversal` | `model_xau_pullback.onnx` | **Dibalik** (contrarian), ML menguji prob arah yang dibuka | Konfirmasi bounce `0.20×ATR` searah trade; batal jika harga melawan `0.25×ATR` |

---

## 📊 1. XAU_Phase1 (Trend-Following + Entry Instan)

| Metrik / Level | 🔵 Skema A (0.35) | 🟡 Skema B (0.45) | 🔴 Skema C (0.55) |
| :--- | :---: | :---: | :---: |
| **Total Siklus** | 6.096 | 5.642 | 2.484 |
| **Level 0 (Langsung TP tanpa Marti)** | 62,73% (3.824) | 63,06% (3.558) | 68,36% (1.698) |
| **Level 1 (Lot 0.02)** | 20,75% (1.265) | 20,52% (1.158) | 19,52% (485) |
| **Level 2 (Lot 0.04)** | 7,51% (458) | 7,66% (432) | 5,76% (143) |
| **Level 3 (Lot 0.08)** | 3,74% (228) | 3,63% (205) | 2,70% (67) |
| **Level 4 (Lot 0.16)** | 1,94% (118) | 1,75% (99) | 1,29% (32) |
| **Level 5 (Lot 0.32)** | 1,03% (63) | 0,96% (54) | 0,68% (17) |
| **Level 6 (Max Step - Lot 0.64)** | **2,30% (140)** | **2,41% (136)** | **1,69% (42)** |
| **Rata-rata Drawdown/Siklus** | $172,29 | $200,70 | $102,04 |
| **P95 Drawdown (95% Siklus Aman)** | **$123,20** | **$121,23** | **$67,52** |
| **Profit Estimasi (siklus × $3)** | **$18.258** | $16.890 | $7.446 |
| **Siklus Tak Selesai (Horizon 600 bar)** | 10 | 12 | 2 |

> 📌 **Catatan**: Hasil Skema A/B/C baseline ini konsisten dengan laporan [`test_3skema.md`](test_3skema.md) sebelumnya (P95 DD $123–$126, Level 6 ~2,3%). Threshold `0.45` tidak memperbaiki kualitas sinyal secara signifikan dibanding `0.35` (L6 justru naik tipis), sedangkan `0.55` memangkas siklus lebih dari separuh dengan P95 DD turun ke $67,52.

---

## 📊 2. XAU_Phase1_Reversal (Contrarian + Entry Instan)

| Metrik / Level | 🔵 Skema A (0.35) | 🟡 Skema B (0.45) | 🔴 Skema C (0.55) |
| :--- | :---: | :---: | :---: |
| **Total Siklus** | 5.620 | 5.307 | 1.275 |
| **Level 0 (Langsung TP tanpa Marti)** | 56,37% (3.168) | 55,89% (2.966) | 50,82% (648) |
| **Level 1 (Lot 0.02)** | 26,26% (1.476) | 26,44% (1.403) | 26,98% (344) |
| **Level 2 (Lot 0.04)** | 9,25% (520) | 9,23% (490) | 9,57% (122) |
| **Level 3 (Lot 0.08)** | 3,47% (195) | 3,64% (193) | 4,78% (61) |
| **Level 4 (Lot 0.16)** | 1,60% (90) | 1,49% (79) | 2,51% (32) |
| **Level 5 (Lot 0.32)** | 0,96% (54) | 1,07% (57) | 1,57% (20) |
| **Level 6 (Max Step - Lot 0.64)** | **2,08% (117)** | **2,24% (119)** | **3,76% (48)** |
| **Rata-rata Drawdown/Siklus** | $230,06 | $241,90 | **$422,85** ⚠️ |
| **P95 Drawdown (95% Siklus Aman)** | **$98,98** | **$101,90** | **$340,83** ⚠️ |
| **Profit Estimasi (siklus × $3)** | **$16.824** | $15.882 | $3.813 |
| **Siklus Tak Selesai (Horizon 600 bar)** | 12 | 13 | 4 |

> ⚠️ **Peringatan Skema C**: Pada EA Reversal, threshold `0.55` justru **berbahaya**. Filter hanya melewatkan ~1.275 setup contrarian yang oleh model dinilai sangat yakin — namun justru kelompok ini paling sering berujung floating dalam (P95 DD melonjak ke **$340,83**, naik 3,4× dibanding Skema A, dan persentase Level 0 terendah 50,82%). Probabilitas model dihitung untuk arah yang *dibalik* (out-of-distribution bagi model), sehingga prob tinggi ≠ setup bagus untuk mode contrarian.


---

## 📊 3. XAU_PullBack (Trend-Following + Entry Diskon Retest)

| Metrik / Level | 🔵 Skema A (0.35) | 🟡 Skema B (0.45) | 🔴 Skema C (0.55) |
| :--- | :---: | :---: | :---: |
| **Sinyal Batal Anti-FOMO (harga lari duluan)** | 6.924 | 6.935 | 6.937 |
| **Sinyal Hangus (retest tak tercapai)** | 313 | 298 | 296 |
| **Total Siklus Tereksekusi** | 3.081 | 3.078 | 3.072 |
| **Level 0 (Langsung TP tanpa Marti)** | 56,77% (1.749) | 56,82% (1.749) | 56,77% (1.744) |
| **Level 1 (Lot 0.02)** | 21,91% (675) | 21,90% (674) | 21,90% (673) |
| **Level 2 (Lot 0.04)** | 10,78% (332) | 10,75% (331) | 10,77% (331) |
| **Level 3 (Lot 0.08)** | 4,35% (134) | 4,35% (134) | 4,36% (134) |
| **Level 4 (Lot 0.16)** | 2,11% (65) | 2,11% (65) | 2,12% (65) |
| **Level 5 (Lot 0.32)** | 1,49% (46) | 1,49% (46) | 1,50% (46) |
| **Level 6 (Max Step - Lot 0.64)** | **2,60% (80)** | **2,57% (79)** | **2,57% (79)** |
| **Rata-rata Drawdown/Siklus** | $209,02 | $207,65 | $208,05 |
| **P95 Drawdown (95% Siklus Aman)** | **$163,59** | **$158,32** | **$158,51** |
| **Profit Estimasi (siklus × $3)** | **$9.228** | $9.219 | $9.201 |
| **Siklus Tak Selesai (Horizon 600 bar)** | 5 | 5 | 5 |

> 📌 **Catatan penting**: Ketiga skema menghasilkan angka yang **hampir identik**. Distribusi probabilitas model `model_xau_pullback.onnx` condong ke nilai tinggi (model dilatih khusus pada outcome eksekusi diskon), sehingga threshold `0.35 / 0.45 / 0.55` hampir tidak memfilter apa pun. Artinya: **pada EA PullBack, pemilihan skema probabilitas praktis tidak berpengaruh** — faktor penentu hasilnya adalah mekanisme diskon/cancel itu sendiri (±15% sinyal gugur oleh filter anti-FOMO, ±1% hangus).

---

## 📊 4. XAU_PullBack_Reversal (Contrarian + Entry Konfirmasi Bounce)

| Metrik / Level | 🔵 Skema A (0.35) | 🟡 Skema B (0.45) | 🔴 Skema C (0.55) |
| :--- | :---: | :---: | :---: |
| **Sinyal Batal Anti-FOMO (harga melawan)** | 7.408 | 7.397 | 7.403 |
| **Sinyal Hangus (bounce tak tercapai)** | 326 | 318 | 316 |
| **Total Siklus Tereksekusi** | 3.371 | 3.367 | 3.363 |
| **Level 0 (Langsung TP tanpa Marti)** | **69,42% (2.340)** | 69,38% (2.336) | 69,46% (2.336) |
| **Level 1 (Lot 0.02)** | 18,84% (635) | 18,86% (635) | 18,88% (635) |
| **Level 2 (Lot 0.04)** | 6,14% (207) | 6,15% (207) | 6,15% (207) |
| **Level 3 (Lot 0.08)** | 2,02% (68) | 2,02% (68) | 2,02% (68) |
| **Level 4 (Lot 0.16)** | 1,19% (40) | 1,19% (40) | 1,19% (40) |
| **Level 5 (Lot 0.32)** | 0,59% (20) | 0,59% (20) | 0,56% (19) |
| **Level 6 (Max Step - Lot 0.64)** | **1,81% (61)** | **1,81% (61)** | **1,81% (61)** |
| **Rata-rata Drawdown/Siklus** | **$149,49** | $149,68 | $149,72 |
| **P95 Drawdown (95% Siklus Aman)** | **$54,72** 🏆 | $54,77 | $54,57 |
| **Profit Estimasi (siklus × $3)** | **$10.092** | $10.080 | $10.068 |
| **Siklus Tak Selesai (Horizon 600 bar)** | 7 | 7 | 7 |

> 🏆 **Catatan**: Meski model pullback membuat threshold probabilitas nyaris tak berpengaruh, **kombinasi contrarian + konfirmasi bounce terbukti paling defensif dari semua kombinasi**: Level 0 tertinggi kedua (69,42%), kejadian Level 6 terendah kedua (61×), dan **P95 DD terendah dari seluruh 12 kombinasi ($54,72)** — lebih aman ~2× dibanding XAU_Phase1 pada skema yang sama, bahkan dengan profit yang lebih tinggi dari XAU_PullBack.

---

## 🔍 Matriks Perbandingan Lintas EA (12 Kombinasi)

### Peringkat Risiko — P95 Drawdown (semakin kecil semakin aman)

| Peringkat | EA + Skema | P95 DD | Kejadian Level 6 | Rata-rata DD |
| :---: | :--- | :---: | :---: | :---: |
| 🥇 1 | **XAU_PullBack_Reversal (A/B/C)** | **$54,72** | 61× | $149,49 |
| 🥈 2 | XAU_Phase1 C | $67,52* | 42× | $102,04 |
| 🥉 3 | XAU_Phase1_Reversal A | $98,98 | 117× | $230,06 |
| 4 | XAU_Phase1_Reversal B | $101,90 | 119× | $241,90 |
| 5 | XAU_Phase1 B | $121,23 | 136× | $200,70 |
| 6 | XAU_Phase1 A | $123,20 | 140× | $172,29 |
| 7 | XAU_PullBack B | $158,32 | 79× | $207,65 |
| 8 | XAU_PullBack C | $158,51 | 79× | $208,05 |
| 9 | XAU_PullBack A | $163,59 | 80× | $209,02 |
| ⚠️ 10 | **XAU_Phase1_Reversal C** | **$340,83** | 48× | **$422,85** |

*\*XAU_Phase1 C secara P95 DD sangat kecil, tetapi volume siklusnya hanya 2.484 sehingga akumulasi profit juga kecil.*

### Peringkat Profitabilitas & Efisiensi Risiko (Profit Est / P95 DD)

| EA | Skema A | Skema B | Skema C |
| :--- | :---: | :---: | :---: |
| **XAU_Phase1** | $18.258 (148,2) | $16.890 (139,3) | $7.446 (110,3) |
| **XAU_Phase1_Reversal** | $16.824 (170,0) | $15.882 (156,0) | $3.813 (11,2) ⚠️ |
| **XAU_PullBack** | $9.228 (56,4) | $9.219 (58,2) | $9.201 (58,0) |
| **XAU_PullBack_Reversal** | $10.092 (**184,4**) 🏆 | $10.080 (184,1) | $10.068 (184,5) |

> Format: `Profit Estimasi (Profit per $1 P95 DD)`

---

## 💡 Kesimpulan Kunci Pengujian

1. **🏆 Kombinasi Terbaik Secara Risk-Adjusted: `XAU_PullBack_Reversal` (skema mana pun)**
   - P95 DD terendah dari seluruh 12 kombinasi (**$54,72**), kejadian Level 6 hanya 61× dari 3.371 siklus, dengan profit estimasi $10.092 — melebihi XAU_PullBack biasa.
   - Efisiensi risiko tertinggi: **$184 profit per $1 P95 DD** (XAU_Phase1 hanya $110–148).
   - Threshold ML tidak sensitif pada EA ini, jadi Skema A direkomendasikan (sinyal sedikit lebih banyak).

2. **💰 Profit Absolut Tertinggi: `XAU_Phase1` Skema A ($18.258)**
   - Volume siklus terbesar (6.096) dengan P95 DD $123,20 yang masih wajar. Pilihan jika prioritas adalah pertumbuhan equity aktif, dengan konsekuensi eksposur drawdown ±2,3× dari PullBack_Reversal.

3. **⚠️ Kombinasi Terburuk: `XAU_Phase1_Reversal` Skema C (prob 0.55)**
   - Threshold ketat pada mode contrarian justru menyaring HANYA setup berisiko: P95 DD meledak ke **$340,83** (3,4× Skema A), rata-rata DD $422,85, dan Level 0 anjlok ke 50,82%. **Hindari kombinasi ini.**

4. **Threshold `0.45` (Skema B) hampir tidak memberi nilai tambah** pada semua EA — hasilnya selalu menengah dan tidak pernah menjadi pilihan terbaik.

5. **Pada EA PullBack, skema probabilitas praktis netral** — model `model_xau_pullback.onnx` menghasilkan probabilitas yang terdistribusi tinggi sehingga threshold 0.35–0.55 jarang memfilter. Yang benar-benar mengurangi risiko adalah mekanisme **Cancel Anti-FOMO 0.25×ATR** yang menggugurkan ±15% sinyal buruk sebelum entry.

6. **Rekomendasi Final**:
   - Untuk akun defensif/konservatif → **XAU_PullBack_Reversal + skema_A_prob35.set**
   - Untuk akun agresif/pertumbuhan cepat → **XAU_Phase1 + skema_A_prob35.set** (atau skema_C jika ingin risiko minimal di EA ini)
   - Jangan jalankan skema_C_prob55.set pada EA Reversal mana pun.

---

## 📋 Metodologi & Catatan Keterbatasan

1. **Sumber data**: `ml_training/xauusd_ml_dataset.csv` — 46.345 bar sinyal XAUUSD M15 (2023.02.02 – 2026.09.04), diekspor via `Export_ML_Dataset.mq5`.
2. **Replikasi ML filter**: Probabilitas dihitung per bar untuk KEDUA arah (`signal_type=1` dan `2`) dari kedua model ONNX, lalu difilter sesuai logika tiap EA — termasuk perilaku Reversal yang menguji probabilitas arah trade yang *dibalik*.
3. **Simulasi basket martingale**: grid 400 poin, maks 6 step, lot 0.01×2ⁿ, TP basket $3, horizon evaluasi 600 bar; siklus tidak tumpang tindih (mengikuti `InpMaxOpenPositions=1`). Terdapat sedikit perbedaan angka vs `test_3skema.md` (±20% siklus) akibat perlakuan siklus yang tidak selesai dalam horizon — arah kesimpulan tetap identik.
4. **Aproksimasi pullback pada level bar M15**: fill/cancel dievaluasi pada bar pertama setelah sinyal (aproksimasi timeout 120 detik). Jika level cancel dan level fill tersentuh di bar yang sama, dihitung **batal** (asumsi konservatif). Eksekusi nyata berbasis tick dapat sedikit berbeda.
5. **Profit estimasi = jumlah siklus selesai × $3.0** — belum memperhitungkan spread, komisi, swap, slippage, dan kemungkinan margin call pada siklus floating dalam; angka absolut sebaiknya dipakai untuk perbandingan relatif antar kombinasi, bukan proyeksi profit nyata.
6. **Parameter sinyal dataset** menggunakan deteksi kandidat rule-based bawaan script ekspor (ADX≥20 + konfirmasi DI, RSI 30/70), sedangkan file .set memakai `InpADX_Strength=15`, `InpADX_UseDI=false`, RSI 65/35 — variasi kecil yang berlaku sama untuk keempat EA sehingga perbandingan antar kombinasi tetap valid.

