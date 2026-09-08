# Panduan Implementasi Machine Learning (Fase 2) - EA XAUUSD v2.14

Dokumen ini menjelaskan alur lengkap pembuatan dataset, pelatihan model (*training*), dan penanaman model ONNX ke dalam EA MetaTrader 5.

---

## Langkah 1: Ekspor Dataset dari MetaTrader 5

1. Buka MetaEditor dan kompilasi script [`Export_ML_Dataset.mq5`](file:///d:/EA/XAU/Scripts/Export_ML_Dataset.mq5).
2. Di MetaTrader 5, buka chart **XAUUSD.vx** (disarankan timeframe **M15**).
3. Drag & drop script `Export_ML_Dataset` dari jendela Navigator (bagian *Scripts*) ke chart.
4. Tentukan jumlah bar yang ingin diekspor (misal: 10.000 atau 20.000 bar).
5. Klik **OK**. File CSV akan terbentuk di folder:
   ```
   <MT5 Data Folder>/MQL5/Files/xauusd_ml_dataset.csv
   ```
   *(Untuk membuka foldernya di MT5: Klik menu **File** -> **Open Data Folder** -> masuk ke **MQL5/Files**).*

---

## Langkah 2: Pelatihan Model di Python (*Training & ONNX Export*)

1. Salin file `xauusd_ml_dataset.csv` ke folder `d:\EA\XAU\ml_training\`.
2. Install library yang dibutuhkan (jika belum ada):
   ```bash
   pip install pandas numpy scikit-learn skl2onnx onnxruntime
   ```
3. Jalankan script training:
   ```bash
   python train_model.py
   ```
4. Script akan melatih model klasifikasi, menampilkan laporan performa (*Precision, Recall, ROC-AUC, Feature Importance*), dan menghasilkan file:
   ```
   model_xau.onnx
   ```

---

## Langkah 3: Integrasi ONNX ke dalam `XAU_Phase1.mq5` (Node 3)

1. Salin file `model_xau.onnx` ke folder `MQL5/Include/` atau letakkan satu folder dengan EA Anda.
2. Di dalam EA, kita tinggal mengaktifkan resource model:
   ```mql5
   #resource "\\Include\\model_xau.onnx" as uchar ExtModel[]
   ```
3. Pada **Node 3**, EA akan mengisi vektor input 13 fitur dan mengeksekusi inferensi secara instan:
   ```mql5
   long onnx_handle = OnnxCreateFromBuffer(ExtModel, ONNX_DEFAULT);
   // Jalankan OnnxRun(...) -> Dapatkan probabilitas Win
   ```
4. Jika probabilitas $\ge$ ambang batas (misal `0.60`), trade dieksekusi. Jika tidak, trade difilter.
