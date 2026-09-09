# Laporan Uji Coba Jarak Martingale (350 vs 400 vs 450 Poin) - EA XAUUSD v2.14

Laporan ini menyajikan hasil simulasi kuantitatif komparatif untuk menguji pengaruh **Jarak Grid Martingale** (**350 poin**, **400 poin**, dan **450 poin**) pada **3 Skema Probabilitas ML** (`0.35`, `0.45`, dan `0.55`) terhadap data historis XAUUSD M15 (46.345 bar).

---

## 🎯 Parameter Pengujian
- **Lot Awal (Base Lot)**: `0.01`
- **Pengali Martingale (Multiplier)**: `2.0x`
- **Ladder Lot**: `0.01` $\rightarrow$ `0.02` $\rightarrow$ `0.04` $\rightarrow$ `0.08` $\rightarrow$ `0.16` $\rightarrow$ `0.32` $\rightarrow$ `0.64` (Maksimal 6 Step, akumulasi 1.27 lot)
- **Target Profit (TP)**: `$3.0`
- **Stop Loss (SL)**: `2.0x ATR`

---

## 📊 1. Tabel Perbandingan Kedalaman Level & Kejadian Max Step (Level 6)

### 🔹 Uji Jarak 350 Poin ($3.50 pergerakan emas)
> Jarak lebih sempit, posisi averaging lebih cepat terpicu.

| Metrik / Level | 🟢 Skema A (Prob 0.35) | 🟡 Skema B (Prob 0.45) | 🔴 Skema C (Prob 0.55) |
| :--- | :---: | :---: | :---: |
| **Total Siklus Sinyal** | 7.095 siklus | 6.837 siklus | 2.446 siklus |
| **Level 0 (Langsung TP tanpa Marti)** | 60.75% (4.310) | 61.58% (4.210) | 65.86% (1.611) |
| **Level 1 (Lot 0.02)** | 21.01% (1.491) | 20.54% (1.404) | 20.56% (503) |
| **Level 2 (Lot 0.04)** | 7.96% (565) | 7.77% (531) | 6.05% (148) |
| **Level 3 (Lot 0.08)** | 3.78% (268) | 3.99% (273) | 3.03% (74) |
| **Level 4 (Lot 0.16)** | 2.11% (150) | 2.12% (145) | 1.43% (35) |
| **Level 5 (Lot 0.32)** | 1.31% (93) | 1.13% (77) | 0.90% (22) |
| **Level 6 (Max Step - Lot 0.64)** | **3.07% (218 kali)** | **2.88% (197 kali)** | **2.17% (53 kali)** |
| **Level Terdalam** | **Level 6** | **Level 6** | **Level 6** |
| **P95 Drawdown (95% Siklus Aman)**| **$171.84** | **$145.37** | **$84.26** |

---

### 🔹 Uji Jarak 400 Poin ($4.00 pergerakan emas - Baseline)

| Metrik / Level | 🟢 Skema A (Prob 0.35) | 🟡 Skema B (Prob 0.45) | 🔴 Skema C (Prob 0.55) |
| :--- | :---: | :---: | :---: |
| **Total Siklus Sinyal** | 7.461 siklus | 7.128 siklus | 2.535 siklus |
| **Level 0 (Langsung TP tanpa Marti)** | 63.44% (4.733) | 64.03% (4.564) | 68.28% (1.731) |
| **Level 1 (Lot 0.02)** | 20.43% (1.524) | 19.92% (1.420) | 19.57% (496) |
| **Level 2 (Lot 0.04)** | 7.30% (545) | 7.37% (525) | 5.88% (149) |
| **Level 3 (Lot 0.08)** | 3.57% (266) | 3.63% (259) | 2.68% (68) |
| **Level 4 (Lot 0.16)** | 1.85% (138) | 1.78% (127) | 1.26% (32) |
| **Level 5 (Lot 0.32)** | 1.10% (82) | 0.94% (67) | 0.67% (17) |
| **Level 6 (Max Step - Lot 0.64)** | **2.32% (173 kali)** | **2.33% (166 kali)** | **1.66% (42 kali)** |
| **Level Terdalam** | **Level 6** | **Level 6** | **Level 6** |
| **P95 Drawdown (95% Siklus Aman)**| **$126.01** | **$116.29** | **$63.95** |

---

### 🔹 Uji Jarak 450 Poin ($4.50 pergerakan emas)
> Jarak lebih lebar, posisi averaging lebih jarang dan lebih tahan floating.

| Metrik / Level | 🟢 Skema A (Prob 0.35) | 🟡 Skema B (Prob 0.45) | 🔴 Skema C (Prob 0.55) |
| :--- | :---: | :---: | :---: |
| **Total Siklus Sinyal** | 7.245 siklus | 6.918 siklus | 2.450 siklus |
| **Level 0 (Langsung TP tanpa Marti)** | 65.48% (4.744) | 65.71% (4.546) | **69.80% (1.710)** |
| **Level 1 (Lot 0.02)** | 19.20% (1.391) | 19.14% (1.324) | 18.16% (445) |
| **Level 2 (Lot 0.04)** | 7.22% (523) | 7.27% (503) | 6.00% (147) |
| **Level 3 (Lot 0.08)** | 3.22% (233) | 3.21% (222) | 2.45% (60) |
| **Level 4 (Lot 0.16)** | 1.46% (106) | 1.37% (95) | 1.02% (25) |
| **Level 5 (Lot 0.32)** | 0.97% (70) | 0.94% (65) | 0.57% (14) |
| **Level 6 (Max Step - Lot 0.64)** | **2.46% (178 kali)** | **2.36% (163 kali)** | **2.00% (49 kali)** |
| **Level Terdalam** | **Level 6** | **Level 6** | **Level 6** |
| **P95 Drawdown (95% Siklus Aman)**| **$119.97** | **$110.75** | **$62.28** |

---

## 🔍 Matriks Perbandingan Risiko Drawdown (P95 Drawdown)

| Jarak Grid (Poin) | Skema A (Prob 0.35) | Skema B (Prob 0.45) | Skema C (Prob 0.55) |
| :---: | :---: | :---: | :---: |
| **350 Poin** | $171.84 (Paling Berisiko) | $145.37 | $84.26 |
| **400 Poin** | $126.01 | $116.29 | $63.95 |
| **450 Poin** | **$119.97** | **$110.75** | **$62.28 (Paling Aman)** |

---

## 💡 Kesimpulan Kunci Pengujian Jarak:

1. **Jarak 350 Poin Terlalu Rapat untuk XAUUSD M15**:
   - Kejadian menyentuh Level 6 naik signifikan menjadi **218 kali** di Skema A dan **53 kali** di Skema C.
   - P95 Drawdown melonjak hingga **$171.84** (naik +36.3% dibanding jarak 400 poin). Jarak 350 poin tidak disarankan karena volatilitas candle M15 emas mudah memakan jarak $3.5.

2. **Jarak 450 Poin Memberikan Ruang Nafas Terbaik**:
   - Persentase trade yang langsung selesai di **Level 0 (tanpa marti) meningkat hingga hampir 70%** (69.80% pada Skema C).
   - Drawdown 95% siklus ditekan hingga **$62.28**, menjadikan jarak 450 poin sebagai setelan paling defensif.

3. **Kombinasi Terbaik (Sweet Spot)**:
   - **Skema C (`Prob >= 0.55`) dengan Jarak 400 Poin**: Menghasilkan jumlah kejadian mentok Level 6 paling sedikit (**hanya 42 kali** sepanjang riwayat data).
   - **Skema B (`Prob >= 0.45`) dengan Jarak 450 Poin**: Pilihan terbaik jika ingin trading lebih aktif dengan risiko floating yang tetap rendah (P95 DD hanya $110.75).
