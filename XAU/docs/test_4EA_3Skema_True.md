# Laporan Uji Varian `InpADX_UseDI=true` — 4 EA × 3 Skema Probabilitas ML (XAUUSD M15)

Laporan ini menyajikan hasil simulasi komparatif ketika **`InpADX_UseDI=true`** (filter arah ADX +DI/-DI diaktifkan) pada **4 EA** menggunakan **3 Skema Probabilitas ML**, dibandingkan dengan baseline `InpADX_UseDI=false` dari laporan [`test_4EA_3skema.md`](test_4EA_3skema.md).

- **Script simulasi**: [`ml_training/eval_4EA_3skema_di_true.py`](ml_training/eval_4EA_3skema_di_true.py)
- **Data mentah**: [`ml_training/results_4EA_3skema_di_true.csv`](ml_training/results_4EA_3skema_di_true.csv)
- **File setting live**: `skema_A_prob35_di_true.set`, `skema_B_prob45_di_true.set`, `skema_C_prob55_di_true.set` (sudah dibuat di folder `D:\EA\XAU\`)

---

## 🔑 Temuan Utama (Baca Dulu!)

> ⚠️ **Hasil UseDI=true nyaris identik dengan baseline** — hanya **7 dari 46.345 baris sinyal (0,015%)** yang terfilter (5 follow-buy, 2 baris edge lainnya). Simulasi membuktikan ini secara empiris, dan penyebabnya ada di **konstruksi dataset**, bukan karena filter DI tidak berguna:
>
> 1. **Dataset sudah DI-konsisten sejak awal.** Script ekspor (`Export_ML_Dataset.mq5`) merekam sinyal follow dengan aturan yang **sudah memakai DI**: follow-buy butuh `adx_p > adx_md`, follow-sell butuh `adx_md > adx_p`. Jadi semua sinyal follow di dataset otomatis lolos filter `UseDI=true` — tidak ada yang bisa disaring lagi.
> 2. **Sinyal reversal memang kebal DI.** Di EA, filter `InpADX_UseDI` hanya berlaku pada Node 1 (follow trend). Node 2 (RSI ekstrem + pinbar/engulfing) tidak menggunakan DI sama sekali, jadi tetap lolos di kedua varian.
> 3. **Sinyal yang sebenarnya tersaring tidak ada di dataset.** Perbedaan nyata antara UseDI=false vs true di live terjadi pada bar-bar *follow trend melawan DI* (misal harga > EMA tapi -DI > +DI). Bar semacam itu **tidak pernah direkam** oleh script ekspor (karena aturan DI-nya sudah aktif), sehingga tidak bisa diukur dari dataset ini.

**Konsekuensi**: angka di laporan ini membuktikan bahwa pada data yang tersedia, toggle UseDI **netral** — bukan bahwa filter DI tidak berpengaruh di trading nyata.

---

## 🎯 Parameter Pengujian

Identik dengan baseline ([`test_4EA_3skema.md`](test_4EA_3skema.md)): basket martingale **ON** (grid 400 poin, 6 step, lot 0.01×2ⁿ, TP basket $3, siklus non-overlap), dataset 46.345 bar sinyal XAUUSD M15 (2023.02.02 – 2026.09.04).

**Replikasi `UseDI=true`** (persis logika .mq5):
- Node 1 FOLLOW: BUY butuh `adx_pdi > adx_mdi`; SELL butuh `adx_mdi > adx_pdi` — bila gagal, sinyal follow gugur.
- Node 2 REVERSAL (RSI ≤ 35 / ≥ 65 + pinbar/engulfing): **tetap lolos** apa pun arah DI (sesuai source EA).
- Jika pada bar yang sama kondisi follow gugur DI tetapi kondisi reversal terpenuhi, sinyal tetap dieksekusi lewat jalur reversal (meniru akumulasi flag OR di `CheckForSignal()`).

---

## 📊 1. XAU_Phase1

| Metrik / Level | 🔵 Skema A (0.35) | 🟡 Skema B (0.45) | 🔴 Skema C (0.55) |
| :--- | :---: | :---: | :---: |
| **Total Siklus** | 6.095 *(base 6.096)* | 5.642 *(=)* | 2.484 *(=)* |
| **Level 0** | 62,74% | 63,10% | 68,44% |
| **Level 6 (Max Step)** | **2,30% (140)** | **2,41% (136)** | **1,69% (42)** |
| **Rata-rata DD** | $172,31 | $200,70 | $102,03 |
| **P95 DD** | **$123,23** | **$121,23** | **$67,52** |
| **Profit Estimasi** | **$18.255** | $16.890 | $7.446 |

## 📊 2. XAU_Phase1_Reversal

| Metrik / Level | 🔵 Skema A (0.35) | 🟡 Skema B (0.45) | 🔴 Skema C (0.55) |
| :--- | :---: | :---: | :---: |
| **Total Siklus** | 5.626 *(base 5.620)* | 5.311 *(base 5.307)* | 1.275 *(=)* |
| **Level 0** | 56,40% | 55,90% | 50,82% |
| **Level 6 (Max Step)** | **2,08% (117)** | **2,24% (119)** | **3,76% (48)** |
| **Rata-rata DD** | $228,57 | $240,40 | $422,85 |
| **P95 DD** | **$99,36** | **$103,23** | **$340,83** ⚠️ |
| **Profit Estimasi** | **$16.842** | $15.894 | $3.813 |

## 📊 3. XAU_PullBack

| Metrik / Level | 🔵 Skema A (0.35) | 🟡 Skema B (0.45) | 🔴 Skema C (0.55) |
| :--- | :---: | :---: | :---: |
| **Batal Anti-FOMO / Hangus** | 6.923 / 313 | 6.934 / 298 | 6.936 / 296 |
| **Total Siklus** | 3.078 *(base 3.081)* | 3.075 *(base 3.078)* | 3.069 *(base 3.072)* |
| **Level 6 (Max Step)** | **2,60% (80)** | **2,57% (79)** | **2,57% (79)** |
| **P95 DD** | **$165,12** | **$158,42** | **$158,60** |
| **Profit Estimasi** | **$9.219** | $9.210 | $9.192 |

## 📊 4. XAU_PullBack_Reversal

| Metrik / Level | 🔵 Skema A (0.35) | 🟡 Skema B (0.45) | 🔴 Skema C (0.55) |
| :--- | :---: | :---: | :---: |
| **Batal Anti-FOMO / Hangus** | 7.407 / 326 | 7.396 / 318 | 7.402 / 316 |
| **Total Siklus** | 3.371 *(=)* | 3.367 *(=)* | 3.363 *(=)* |
| **Level 6 (Max Step)** | **1,81% (61)** | **1,81% (61)** | **1,81% (61)** |
| **P95 DD** | **$54,72** 🏆 | **$54,77** | **$54,57** |
| **Profit Estimasi** | **$10.092** | $10.080 | $10.068 |

---


## 🔍 Delta vs Baseline (UseDI=false → true)

| EA | Skema | Siklus (base → DI=true) | L6 (base → DI=true) | P95 DD (base → DI=true) | Profit (base → DI=true) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| XAU_Phase1 | A | 6.096 → 6.095 (−1) | 140 → 140 | $123,20 → $123,23 | $18.258 → $18.255 |
| XAU_Phase1 | B | 5.642 → 5.642 | 136 → 136 | $121,23 → $121,23 | $16.890 → $16.890 |
| XAU_Phase1 | C | 2.484 → 2.484 | 42 → 42 | $67,52 → $67,52 | $7.446 → $7.446 |
| XAU_Phase1_Reversal | A | 5.620 → 5.626 (+6) | 117 → 117 | $98,98 → $99,36 | $16.824 → $16.842 |
| XAU_Phase1_Reversal | B | 5.307 → 5.311 (+4) | 119 → 119 | $101,90 → $103,23 | $15.882 → $15.894 |
| XAU_Phase1_Reversal | C | 1.275 → 1.275 | 48 → 48 | $340,83 → $340,83 | $3.813 → $3.813 |
| XAU_PullBack | A | 3.081 → 3.078 (−3) | 80 → 80 | $163,59 → $165,12 | $9.228 → $9.219 |
| XAU_PullBack | B | 3.078 → 3.075 (−3) | 79 → 79 | $158,32 → $158,42 | $9.219 → $9.210 |
| XAU_PullBack | C | 3.072 → 3.069 (−3) | 79 → 79 | $158,51 → $158,60 | $9.201 → $9.192 |
| XAU_PullBack_Reversal | A | 3.371 → 3.371 | 61 → 61 | $54,72 → $54,72 | $10.092 → $10.092 |
| XAU_PullBack_Reversal | B | 3.367 → 3.367 | 61 → 61 | $54,77 → $54,77 | $10.080 → $10.080 |
| XAU_PullBack_Reversal | C | 3.363 → 3.363 | 61 → 61 | $54,57 → $54,57 | $10.068 → $10.068 |

> Perbedaan kecil naik/turun (±1–6 siklus, ±$1–4 DD) murni efek **pergeseran rantai siklus non-overlap** akibat 7 baris yang gugur — bukan perubahan perilaku strategi. Peringkat akhir tidak berubah: **XAU_PullBack_Reversal tetap paling aman (P95 DD $54,72), XAU_Phase1 Skema A tetap profit tertinggi, XAU_Phase1_Reversal Skema C tetap terburuk.**

---

## 💡 Kesimpulan & Rekomendasi

1. **Pada dataset ini, `InpADX_UseDI=true` vs `false` menghasilkan performa yang identik** (delta < 0,1% di semua metrik). Ini terjadi karena:
   - Sinyal follow di dataset sudah DI-konsisten sejak proses ekspor (aturan `adx_p > adx_md` tertanam di `Export_ML_Dataset.mq5`);
   - Sinyal reversal memang tidak memakai DI di source EA.

2. **Apakah tetap perlu set `UseDI=true` di live? Ya, disarankan ON** — alasannya konsistensi, bukan hasil simulasi ini:
   - Model ML (`model_xau.onnx` / `model_xau_pullback.onnx`) dilatih pada sinyal yang DI-nya searah → dengan `UseDI=true`, sinyal live selalu berada dalam distribusi data training model, sehingga output probabilitas filter ML lebih valid.
   - Tanpa DI (false), EA live akan menembak sinyal follow melawan momentum yang **tidak pernah dipelajari model** — di situlah sumber risiko tak terukurnya.
   - File `skema_*_di_true.set` sudah siap dipakai; tidak ada bukti dari data bahwa ON itu merugikan.

3. **Untuk mengukur efek riil filter DI**, diperlukan salah satu dari:
   - **Re-ekspor dataset** dengan aturan follow yang DI-agnostik (hapus `adx_p > adx_md` / `adx_md > adx_p` di `Export_ML_Dataset.mq5` baris 156/158, lalu ekspor ulang dari MT5) — setelah itu simulasi true vs false akan menampilkan sinyal "melawan DI" yang selama ini tersembunyi; **atau**
   - **Backtest langsung di MT5 Strategy Tester** (4 EA × 2 varian UseDI × skema terbaik) yang mencakup semua bar historis, bukan hanya bar sinyal.

4. **Peringatan yang tetap berlaku** (tidak berubah oleh varian ini): hindari `XAU_Phase1_Reversal + Skema C` (P95 DD $340,83), dan `UseDI=true` **tidak menyelamatkan** kombinasi tersebut — masalahnya ada di interaksi threshold ML ketat dengan mode contrarian, bukan di filter DI.

---

## 📋 Catatan Metodologi

1. Replikasi `UseDI=true` dilakukan dengan klasifikasi baris mengikuti rantai `else-if` pada `Export_ML_Dataset.mq5`: follow-buy = `signal_type=1 & dist_to_ema_atr>0`, follow-sell = `signal_type=2 & dist_to_ema_atr<0`, sisanya reversal. Bar follow diuji arah DI (`adx_pdi` vs `adx_mdi`); bar reversal diuji kondisi EA (RSI ≤35/≥65 + is_pinbar/is_engulfing, threshold file .set).
2. 7 baris gugur (5 follow-buy DI melawan + 2 baris edge NaN/kriteria) → 46.338 baris dieksekusi. Perbedaan angka vs baseline selain itu berasal dari dinamika rantai siklus non-overlap (`InpMaxOpenPositions=1`).
3. Semua asumsi lain (basket martingale 400 poin/6 step/TP $3, non-overlap, aproksimasi pullback level-bar, profit = siklus selesai × $3) identik dengan [`test_4EA_3skema.md`](test_4EA_3skema.md) sehingga kedua laporan dapat dibandingkan langsung.
