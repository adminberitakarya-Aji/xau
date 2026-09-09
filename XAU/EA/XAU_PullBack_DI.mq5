//+------------------------------------------------------------------+
//|                                                 XAU_PullBack_DI.mq5 |
//|          Expert Advisor XAUUSD | PullBack Discount Engine - ML ONNX |
//|   EMA + ADX + RSI + Confirmed Candle + ONNX Filter + Dashboard   |
//|   + Dynamic Retest State Machine + Martingale Recovery Engine    |
//+------------------------------------------------------------------+
#property copyright   "XAU PullBack Engine"
#property link        ""
#property version     "2.15"
#property strict
#property description "EA XAUUSD PULLBACK: Trend/Reversal Signal + 2M Retest Discount State Machine + ONNX ML + Dashboard + Martingale Recovery"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//--- Resource model ONNX khusus Pullback (tertanam langsung ke dalam file .ex5)
#resource "model_xau_pullback_DI.onnx" as uchar ExtModelONNX[]

//+------------------------------------------------------------------+
//| ENUM types                                                       |
//+------------------------------------------------------------------+
enum ENUM_TRAILING_MODE
  {
   TRAIL_STEP_LOCK,  // 0: Step-Lock (Kunci profit bertahap per milestone)
   TRAIL_CLASSIC     // 1: Classic (Jarak linier dari harga running)
  };

enum ENUM_TRADE_MODE
  {
   MODE_FOLLOW_ONLY,   // 0: Hanya FOLLOW tren
   MODE_REVERSAL_ONLY, // 1: Hanya REVERSAL
   MODE_BOTH           // 2: Keduanya (default)
  };

enum ENUM_SL_MODE
  {
   SL_ATR,      // 0: SL berbasis ATR
   SL_LEVEL,    // 1: SL pada level monthly high/low + buffer
   SL_FIXED,    // 2: SL fixed (poin)
   SL_MONEY     // 3: SL nominal Dollar ($)
  };

enum ENUM_TP_MODE
  {
   TP_MONTHLY_LEVEL, // 0: Target High/Low Bulan Sebelumnya (Previous Month)
   TP_ATR_RR,        // 1: Target Risk:Reward berbasis SL ATR
   TP_FIXED,         // 2: TP fixed (poin)
   TP_MONEY          // 3: TP nominal Dollar ($)
  };

enum ENUM_LOT_MODE
  {
   LOT_RISK_PERCENT,  // 0: Lot dari persen risiko
   LOT_FIXED          // 1: Lot fixed
  };

enum ENUM_MARTI_DIST_MODE
  {
   MARTI_DIST_ATR,   // 0: Dinamis berbasis ATR
   MARTI_DIST_FIXED  // 1: Fixed Jarak (poin)
  };

enum ENUM_PULLBACK_DIST_MODE
  {
   PULLBACK_DIST_ATR,   // 0: Dinamis berbasis ATR
   PULLBACK_DIST_FIXED  // 1: Fixed Jarak (poin)
  };

enum ENUM_PULLBACK_STATE
  {
   PB_STATE_IDLE,         // Tidak ada sinyal pending
   PB_STATE_PENDING_BUY,  // Sinyal BUY terdeteksi, menunggu retest/koreksi turun ke zona diskon
   PB_STATE_PENDING_SELL  // Sinyal SELL terdeteksi, menunggu retest/koreksi naik ke zona diskon
  };

//===================================================================
//=== INPUT GROUP: SYMBOL & BROKER SETTINGS                        ===
//===================================================================
sinput group "===== SYMBOL & BROKER SETTINGS ====="
input string             InpCustomSymbol = "";             // Custom Symbol (kosongkan = otomatis chart, misal XAUUSD.vx)

//===================================================================
//=== INPUT GROUP: PULLBACK & RETEST DISCOUNT ENGINE               ===
//===================================================================
sinput group "===== PULLBACK / DISCOUNT RETEST ENGINE ====="
input bool                     InpUsePullback        = true;              // Aktifkan Eksekusi Tunggu Pullback / Retest
input int                      InpPullbackTimeoutSec = 120;               // Waktu Tunggu Koreksi (detik; default 120s = 2 menit)
input ENUM_PULLBACK_DIST_MODE  InpPullbackDistMode   = PULLBACK_DIST_ATR; // Mode Jarak Diskon Koreksi
input double                   InpPullbackATR_Mult   = 0.20;              // Multiplier ATR untuk Diskon (jika Mode ATR, misal 0.2x ATR)
input double                   InpPullbackFixedPts   = 50.0;              // Jarak Poin Diskon (jika Mode Fixed, misal 50 poin = $0.50)
input double                   InpCancelATR_Mult     = 0.25;              // Batas Batal jika Lari Duluan (ATR Mult, misal 0.25x ATR)
input double                   InpCancelFixedPts     = 60.0;              // Batas Batal jika Lari Duluan (Poin Fixed, misal 60 poin)

//===================================================================
//=== INPUT GROUP: INDIKATOR DASAR                                 ===
//===================================================================
sinput group "===== INDICATOR: EMA (arah tren) ====="
input int                InpEMA_Period   = 50;             // EMA period
input ENUM_APPLIED_PRICE InpEMA_Price    = PRICE_CLOSE;    // Applied price
input int                InpEMA_Shift    = 0;              // EMA shift

sinput group "===== INDICATOR: ADX (kekuatan & arah tren) ====="
input int                InpADX_Period   = 14;             // ADX period
input int                InpADX_Strength = 15;             // Min ADX (kekuatan)
input bool               InpADX_UseDI    = true;           // Gunakan filter +DI / -DI utk konfirmasi arah

sinput group "===== INDICATOR: RSI ====="
input int                InpRSI_Period   = 14;             // RSI period
input double             InpRSI_Overbought = 65.0;         // RSI overbought
input double             InpRSI_Oversold   = 35.0;         // RSI oversold
input ENUM_APPLIED_PRICE InpRSI_Price    = PRICE_CLOSE;    // Applied price

//===================================================================
//=== INPUT GROUP: STRATEGI / MODE                                 ===
//===================================================================
sinput group "===== STRATEGI / MODE ====="
input ENUM_TRADE_MODE    InpTradeMode     = MODE_BOTH;     // Mode trading
input bool               InpIsBuyAllowed  = true;          // Izinkan BUY
input bool               InpIsSellAllowed = true;          // Izinkan SELL
input bool               InpUsePinBar     = true;          // Pin bar terkonfirmasi (Bar 1) utk reversal
input bool               InpUseEngulfing  = true;          // Engulfing terkonfirmasi (Bar 1-2) utk reversal
input int                InpMaxOpenPositions = 1;          // Max posisi terbuka
input int                InpMagicNumber   = 20260902;      // Magic number (PullBack Engine)

//===================================================================
//=== INPUT GROUP: MACHINE LEARNING / ONNX PULLBACK                ===
//===================================================================
sinput group "===== MACHINE LEARNING / ONNX PULLBACK ====="
input bool               InpUseMLFilter   = true;          // Aktifkan Filter Machine Learning (Node 3)
input double             InpMLMinWinProb  = 0.35;          // Min Win Probability agar order dieksekusi (0.20 - 0.50)

//===================================================================
//=== INPUT GROUP: MONEY MANAGEMENT & MARTINGALE                   ===
//===================================================================
sinput group "===== MONEY MANAGEMENT ====="
input ENUM_LOT_MODE      InpLotMode       = LOT_RISK_PERCENT; // Mode lot
input double             InpRiskPercent   = 1.0;           // Risk % equity per trade
input double             InpFixedLot      = 0.10;          // Lot fixed
input double             InpMaxRiskMargin = 30.0;          // Maks % equity utk margin

sinput group "===== MARTINGALE / AVERAGING RECOVERY ====="
input bool                 InpUseMartingale       = false;          // Aktifkan Martingale Averaging Recovery
input ENUM_MARTI_DIST_MODE InpMartiDistMode       = MARTI_DIST_ATR; // Mode Jarak Averaging (ATR / Fixed)
input double               InpMartiATR_Mult       = 1.5;            // Multiplier ATR (jika mode ATR)
input double               InpMartingaleDistPts   = 150.0;          // Jarak Poin (jika mode FIXED)
input double               InpMartingaleMult      = 1.5;            // Pengali lot tiap level averaging (misal 1.5x)
input int                  InpMaxMartingaleStep   = 3;              // Maksimal level averaging tambahan (default 3)
input double               InpMartingaleProfitPts = 50.0;           // Target profit TOTAL semua posisi (poin jika trailing off)
input bool                 InpUseBasketTrailing   = true;           // Aktifkan Basket Trailing Profit (Martingale)
input double               InpBasketTrailStartUSD = 30.0;           // [Basket] Start: Profit ($) trigger aktivasi basket trailing
input double               InpBasketTrailLockUSD  = 15.0;           // [Basket] Lock: Profit ($) yang langsung dikunci saat aktif
input double               InpBasketTrailStepUSD  = 10.0;           // [Basket] Step: Jarak kenaikan profit ($) ke milestone berikutnya
input double               InpBasketTrailMoveUSD  = 5.0;            // [Basket] Move: Kenaikan nilai lock ($) per milestone

sinput group "===== TRAILING STOP (SINGLE POSITION) ====="
input bool                 InpUseTrailing         = true;           // Aktifkan Trailing Stop
input ENUM_TRAILING_MODE   InpTrailingMode        = TRAIL_STEP_LOCK;// Mode Trailing: Step-Lock (Milestone) / Classic
input double               InpTrailingStartPts    = 200.0;          // Profit trigger untuk aktifkan trailing (poin)
//--- Khusus Mode Step-Lock / Milestone:
input double               InpTrailingLockPts     = 100.0;          // [Step-Lock] SL awal yang dikunci saat aktif (poin)
input double               InpTrailingStepPoints  = 100.0;          // [Step-Lock] Jarak milestone kenaikan berikutnya (poin)
input double               InpTrailingMovePoints  = 50.0;           // [Step-Lock] Nilai pergeseran SL tiap milestone (poin)
//--- Khusus Mode Classic:
input double               InpTrailingDistPts     = 150.0;          // [Classic] Jarak SL dari harga running (poin)
input double               InpTrailingStepPts     = 30.0;           // [Classic] Step minimal pergerakan SL (poin)

//===================================================================
//=== INPUT GROUP: STOP LOSS & TAKE PROFIT                         ===
//===================================================================
sinput group "===== STOP LOSS & TAKE PROFIT ====="
input ENUM_SL_MODE       InpSLMode        = SL_ATR;        // Mode Stop Loss
input double             InpSL_MoneyUSD   = 50.0;          // Stop Loss ($) jika SL_MONEY
input int                InpATR_Period    = 14;            // ATR period
input double             InpATR_SL_Mult   = 2.0;           // ATR multiplier SL
input double             InpSL_FixedPts   = 500.0;         // SL fixed (poin)
input double             InpSLBuffer      = 0.0;           // Buffer utk SL_LEVEL (poin)

input ENUM_TP_MODE       InpTPMode        = TP_MONTHLY_LEVEL; // Mode Take Profit
input double             InpTP_MoneyUSD   = 100.0;         // Take Profit ($) jika TP_MONEY
input double             InpTP_RR_Ratio   = 1.5;           // Risk:Reward Ratio (jika TP_ATR_RR)
input double             InpTP_FixedPts   = 1000.0;        // TP fixed (poin jika TP_FIXED)
input double             InpMonthlyBuffer = 0.0;           // Buffer TP dari level monthly (poin)

//===================================================================
//=== INPUT GROUP: UTILITAS & FILTER                               ===
//===================================================================
sinput group "===== UTILITAS & FILTER ====="
input int                InpMaxSpreadPts  = 0;             // Max spread (poin); 0=off
input int                InpStartHour     = 0;             // Jam mulai; 0=off
input int                InpEndHour       = 0;             // Jam akhir; 0=off
input ulong              InpSlippagePts   = 30;            // Max slippage / deviation (poin)
input bool               InpShowDashboard = true;          // Tampilkan On-Chart Info Dashboard
input bool               InpDebugLog      = false;         // Log debug

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
string   trade_symbol = "";
int      trade_digits = 2;
double   trade_point  = 0.01;

// Indicator handles
int      handle_EMA      = INVALID_HANDLE;
int      handle_EMA_H1   = INVALID_HANDLE; // Higher Timeframe Trend
int      handle_ADX      = INVALID_HANDLE;
int      handle_RSI      = INVALID_HANDLE;
int      handle_ATR      = INVALID_HANDLE;
int      handle_ATR_Fast = INVALID_HANDLE; // ATR Cepat untuk Volatility Regime Ratio

// ONNX Model handle
long     handle_onnx     = INVALID_HANDLE;
int      onnx_feature_count = 19; // Default 19 fitur untuk model Pullback
double   last_ml_prob    = 0.0;
string   last_signal_desc = "Belum Ada Sinyal";

// Buffers for indicator values
double   ema_value[];
double   ema_h1_value[];
double   adx_value[];
double   adx_plus_di[];
double   adx_minus_di[];
double   rsi_value[];
double   atr_value[];
double   atr_fast_value[];

// Candle monthly levels (Previous Month High/Low)
double   monthly_high = 0.0;
double   monthly_low  = 0.0;

// Last processed bar (to avoid repeated signals on same bar)
datetime last_bar_time = 0;

// Basket Trailing Profit tracking
double   basket_max_profit      = 0.0;
bool     basket_trailing_active = false;

// Pullback State Machine Variables
ENUM_PULLBACK_STATE pb_state        = PB_STATE_IDLE;
datetime            pb_signal_time  = 0;
double              pb_ref_price    = 0.0;
double              pb_target_price = 0.0;
double              pb_cancel_price = 0.0;

// Trade objects
CTrade         trade;
CPositionInfo  pos_info;
CDealInfo      deal_info;

//+------------------------------------------------------------------+
//| Helper Time functions (MQL5 conversion)                          |
//+------------------------------------------------------------------+
int TimeHour(datetime time)
  {
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return dt.hour;
  }

int TimeMonth(datetime time)
  {
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return dt.mon;
  }

//+------------------------------------------------------------------+
//| Hitung jumlah posisi terbuka khusus EA ini                       |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(pos_info.SelectByIndex(i))
        {
         if(pos_info.Symbol() == trade_symbol && pos_info.Magic() == InpMagicNumber)
            count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Hitung jumlah level averaging yang sudah terbuka (open positions) |
//+------------------------------------------------------------------+
int GetMartingaleLevel()
  {
   if(!InpUseMartingale) return 0;
   return CountOpenPositions(); // jumlah posisi EA terbuka saat ini
  }

//+------------------------------------------------------------------+
//| Hitung total floating profit/loss semua posisi EA                 |
//+------------------------------------------------------------------+
double GetTotalFloatingProfit()
  {
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(pos_info.SelectByIndex(i))
        {
         if(pos_info.Symbol() == trade_symbol && pos_info.Magic() == InpMagicNumber)
            total += pos_info.Profit() + pos_info.Swap();
        }
     }
   return total;
  }

//+------------------------------------------------------------------+
//| Dapatkan harga entry dan arah posisi EA pertama yang terbuka     |
//+------------------------------------------------------------------+
bool GetFirstPosition(ENUM_POSITION_TYPE &pos_type, double &entry_price_first, double &last_entry_price)
  {
   entry_price_first = 0.0;
   last_entry_price  = 0.0;
   pos_type = POSITION_TYPE_BUY;
   
   datetime oldest_time = TimeCurrent();
   datetime newest_time = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(pos_info.SelectByIndex(i))
        {
         if(pos_info.Symbol() == trade_symbol && pos_info.Magic() == InpMagicNumber)
           {
            datetime open_time = (datetime)pos_info.Time();
            if(open_time <= oldest_time)
              {
               oldest_time       = open_time;
               entry_price_first = pos_info.PriceOpen();
               pos_type          = pos_info.PositionType();
              }
            if(open_time >= newest_time)
              {
               newest_time      = open_time;
               last_entry_price = pos_info.PriceOpen();
              }
           }
        }
     }
   return (entry_price_first > 0);
  }

//+------------------------------------------------------------------+
//| Tutup SEMUA posisi EA (untuk recovery setelah profit target hit)  |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(pos_info.SelectByIndex(i))
        {
         if(pos_info.Symbol() == trade_symbol && pos_info.Magic() == InpMagicNumber)
           {
            ulong ticket = pos_info.Ticket();
            if(!trade.PositionClose(ticket, InpSlippagePts))
               Print("Gagal menutup posisi ticket=", ticket, " | Error: ", trade.ResultRetcodeDescription());
            else if(InpDebugLog)
               Print("MARTINGALE: Posisi ticket=", ticket, " ditutup (profit target tercapai)");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Format string PnL dengan tanda +/- dan persentase               |
//+------------------------------------------------------------------+
string FormatPnL(double pnl, double base_balance, int wins, int losses)
  {
   string sign = (pnl >= 0.0) ? "+$" : "-$";
   string pnl_str = sign + DoubleToString(MathAbs(pnl), 2);
   
   double pct = (base_balance > 0.0) ? (pnl / base_balance * 100.0) : 0.0;
   string pct_sign = (pct >= 0.0) ? "(+" : "(-";
   string pct_str = pct_sign + DoubleToString(MathAbs(pct), 2) + "%)";
   
   string wr_str = IntegerToString(wins) + "W / " + IntegerToString(losses) + "L";
   int total_trades = wins + losses;
   if(total_trades > 0)
     {
      double wr = ((double)wins / (double)total_trades) * 100.0;
      wr_str += " (WR: " + DoubleToString(wr, 1) + "%)";
     }
     
   return pnl_str + " " + pct_str + " | " + wr_str;
  }

//+------------------------------------------------------------------+
//| Hitung Realized PnL & Win/Loss dari deal history EA              |
//+------------------------------------------------------------------+
void CalculateDealHistoryPnL(datetime from_time, double &out_pnl, int &out_wins, int &out_losses)
  {
   out_pnl    = 0.0;
   out_wins   = 0;
   out_losses = 0;
   
   if(!HistorySelect(from_time, TimeCurrent())) return;
   
   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != trade_symbol) continue;
      
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
        {
         double deal_profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                              HistoryDealGetDouble(ticket, DEAL_SWAP) +
                              HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                              HistoryDealGetDouble(ticket, DEAL_FEE);
         out_pnl += deal_profit;
         if(deal_profit > 0.0001)
            out_wins++;
         else if(deal_profit < -0.0001)
            out_losses++;
        }
     }
  }

//+------------------------------------------------------------------+
//| On-Chart HUD / Dashboard                                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowDashboard) return;
   
   // Guard: jika buffer indikator belum terisi, tampilkan status loading
   bool buffers_ready = (ArraySize(ema_value) > 1 && ArraySize(adx_value) > 1 &&
                         ArraySize(adx_plus_di) > 1 && ArraySize(adx_minus_di) > 1 &&
                         ArraySize(rsi_value) > 1 && ArraySize(atr_value) > 1);
   
   long spread  = (trade_symbol != "") ? SymbolInfoInteger(trade_symbol, SYMBOL_SPREAD) : 0;
   int open_pos = CountOpenPositions();
   
   string ema_trend, adx_trend, di_dir, adx_val_str, rsi_val_str;
   if(buffers_ready)
     {
      ema_trend   = (iClose(trade_symbol, _Period, 1) > ema_value[1]) ? "BULLISH [Harga > EMA] [UP]" : "BEARISH [Harga < EMA] [DOWN]";
      adx_trend   = (adx_value[1] >= InpADX_Strength) ? "TRENDING (Kuat)" : "SIDEWAYS / LEMAH";
      di_dir      = (adx_plus_di[1] > adx_minus_di[1]) ? "+DI > -DI (Buyer Dominan)" : "-DI > +DI (Seller Dominan)";
      adx_val_str = DoubleToString(adx_value[1], 1);
      rsi_val_str = DoubleToString(rsi_value[1], 1);
     }
   else
     {
      ema_trend   = "Menunggu data indikator...";
      adx_trend   = "Menunggu data indikator...";
      di_dir      = "Menunggu data indikator...";
      adx_val_str = "--";
      rsi_val_str = "--";
     }
   
   // Pullback status text
   string pb_status_desc;
   if(!InpUsePullback)
     {
      pb_status_desc = "NONAKTIF (Instant Entry di Open Bar)";
     }
   else if(pb_state == PB_STATE_IDLE)
     {
      pb_status_desc = "IDLE (Siap Menunggu Sinyal Bar Baru)";
     }
   else if(pb_state == PB_STATE_PENDING_BUY)
     {
      int elapsed = (int)(TimeCurrent() - pb_signal_time);
      int remain  = MathMax(0, InpPullbackTimeoutSec - elapsed);
      pb_status_desc = "WAITING BUY RETEST | Diskon Target <= " + DoubleToString(pb_target_price, trade_digits) +
                       " | Batal jika >= " + DoubleToString(pb_cancel_price, trade_digits) +
                       " | Sisa: " + IntegerToString(remain) + "s";
     }
   else if(pb_state == PB_STATE_PENDING_SELL)
     {
      int elapsed = (int)(TimeCurrent() - pb_signal_time);
      int remain  = MathMax(0, InpPullbackTimeoutSec - elapsed);
      pb_status_desc = "WAITING SELL RETEST | Diskon Target >= " + DoubleToString(pb_target_price, trade_digits) +
                       " | Batal jika <= " + DoubleToString(pb_cancel_price, trade_digits) +
                       " | Sisa: " + IntegerToString(remain) + "s";
     }

   string martin_status;
   int marti_level = GetMartingaleLevel();
   string marti_dist_desc;
   if(InpMartiDistMode == MARTI_DIST_ATR)
     {
      double cur_atr_pts = (ArraySize(atr_value) > 1 && atr_value[1] > 0) ?
                           (atr_value[1] * InpMartiATR_Mult / trade_point) : 0.0;
      marti_dist_desc = "ATR x" + DoubleToString(InpMartiATR_Mult, 1) +
                        (cur_atr_pts > 0 ? (" (~" + DoubleToString(cur_atr_pts, 0) + " pts)") : "");
     }
   else
      marti_dist_desc = "Fixed " + DoubleToString(InpMartingaleDistPts, 0) + " pts";

   if(!InpUseMartingale)
      martin_status = "NONAKTIF (Flat Lot)";
   else if(marti_level <= 1)
      martin_status = "AKTIF | Menunggu Sinyal (Level 0) | Grid: " + marti_dist_desc;
   else
      martin_status = "AKTIF | Averaging Level " + IntegerToString(marti_level - 1) +
                      "/" + IntegerToString(InpMaxMartingaleStep) +
                      " | Grid: " + marti_dist_desc +
                      " | Floating: $" + DoubleToString(GetTotalFloatingProfit(), 2);

   // Basket Trailing status
   string basket_status;
   if(!InpUseMartingale || !InpUseBasketTrailing)
      basket_status = "NONAKTIF";
   else if(basket_trailing_active)
     {
      // Hitung level lock saat ini (sama seperti logika di ManagePositions)
      double b_excess      = basket_max_profit - InpBasketTrailStartUSD;
      int    b_steps       = (InpBasketTrailStepUSD > 0) ? (int)MathFloor(b_excess / InpBasketTrailStepUSD) : 0;
      double b_lock_now    = InpBasketTrailLockUSD + (b_steps * InpBasketTrailMoveUSD);
      basket_status = "STEP-LOCK AKTIF | Peak: +$" + DoubleToString(basket_max_profit, 2) +
                      " | Lock: +$"  + DoubleToString(b_lock_now, 2) +
                      " | Step ke-" + IntegerToString(b_steps) +
                      " | Exit jika < +$" + DoubleToString(b_lock_now, 2);
     }
   else
      basket_status = "Menunggu | Aktivasi saat profit >= +$" + DoubleToString(InpBasketTrailStartUSD, 2) +
                      " | Lock awal: +$" + DoubleToString(InpBasketTrailLockUSD, 2);

   // Trailing Stop status
   string trailing_status;
   if(!InpUseTrailing)
      trailing_status = "NONAKTIF";
   else if(InpTrailingMode == TRAIL_STEP_LOCK)
      trailing_status = "AKTIF (Step-Lock) | Start: +" + DoubleToString(InpTrailingStartPts, 0) + " pts" +
                        " | Lock: +" + DoubleToString(InpTrailingLockPts, 0) + " pts" +
                        " | Step: +" + DoubleToString(InpTrailingStepPoints, 0) + " pts" +
                        " | Move: +" + DoubleToString(InpTrailingMovePoints, 0) + " pts";
   else
      trailing_status = "AKTIF (Classic) | Trigger: +" + DoubleToString(InpTrailingStartPts, 0) + " pts" +
                        " | Jarak SL: " + DoubleToString(InpTrailingDistPts, 0) + " pts" +
                        " | Step: " + DoubleToString(InpTrailingStepPts, 0) + " pts";

   string ml_status = InpUseMLFilter ? ("AKTIF (Min Prob: " + DoubleToString(InpMLMinWinProb * 100.0, 0) + "% | Last: " + DoubleToString(last_ml_prob * 100.0, 1) + "%)") : "NONAKTIF (Rule-Based Only)";
   
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double total_float = GetTotalFloatingProfit();
   
   //--- Hitung PnL Harian & Total Realized
   datetime today_start = iTime(trade_symbol, PERIOD_D1, 0);
   if(today_start == 0)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      today_start = StructToTime(dt);
     }
   
   double daily_pnl = 0.0, total_pnl = 0.0;
   int daily_wins = 0, daily_losses = 0;
   int total_wins = 0, total_losses = 0;
   
   CalculateDealHistoryPnL(today_start, daily_pnl, daily_wins, daily_losses);
   CalculateDealHistoryPnL(0, total_pnl, total_wins, total_losses);
   
   string sl_desc = (InpSLMode == SL_MONEY) ? ("$" + DoubleToString(InpSL_MoneyUSD, 2)) :
                    (InpSLMode == SL_ATR) ? (DoubleToString(InpATR_SL_Mult, 1) + "x ATR") :
                    (InpSLMode == SL_FIXED) ? (DoubleToString(InpSL_FixedPts, 0) + " Pts") : "Monthly Level";
   string tp_desc = (InpTPMode == TP_MONEY) ? ("$" + DoubleToString(InpTP_MoneyUSD, 2)) :
                    (InpTPMode == TP_ATR_RR) ? ("RR 1:" + DoubleToString(InpTP_RR_Ratio, 1)) :
                    (InpTPMode == TP_FIXED) ? (DoubleToString(InpTP_FixedPts, 0) + " Pts") : "Monthly Level";

   string float_sign = (total_float >= 0.0) ? "+$" : "-$";
   string float_str  = float_sign + DoubleToString(MathAbs(total_float), 2);

   string text = "";
   text += "====================================================\n";
   text += "[XAU PULLBACK DISCOUNT ENGINE v2.15 ONNX ML]\n";
   text += "====================================================\n";
   text += "- Status EA           : RUNNING [AKTIF - PULLBACK MODE]\n";
   text += "- Magic Number        : " + IntegerToString(InpMagicNumber) + "\n";
   text += "- Pair / Timeframe    : " + trade_symbol + " | " + EnumToString(_Period) + "\n";
   text += "- Spread Saat Ini     : " + IntegerToString(spread) + " Poin\n";
   text += "- Target SL / TP      : SL [" + sl_desc + "] | TP [" + tp_desc + "]\n";
   text += "- Jam Server          : " + TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS) + "\n";
   text += "----------------------------------------------------\n";
   text += "[PULLBACK / RETEST DISCOUNT STATE]\n";
   text += "- Retest Mode         : " + (InpPullbackDistMode == PULLBACK_DIST_ATR ? ("ATR x" + DoubleToString(InpPullbackATR_Mult, 2)) : (DoubleToString(InpPullbackFixedPts, 0) + " pts")) +
           " | Timeout: " + IntegerToString(InpPullbackTimeoutSec) + "s (2 Menit)\n";
   text += "- Status Pullback     : " + pb_status_desc + "\n";
   text += "----------------------------------------------------\n";
   text += "[STATUS INDIKATOR & PASAR]\n";
   text += "- EMA (" + IntegerToString(InpEMA_Period) + ") Trend    : " + ema_trend + "\n";
   text += "- ADX (" + IntegerToString(InpADX_Period) + ") Strength : " + adx_val_str + " [" + adx_trend + "]\n";
   text += "- Directional (+/-DI) : " + di_dir + "\n";
   text += "- RSI (" + IntegerToString(InpRSI_Period) + ") Value    : " + rsi_val_str + "\n";
   text += "- Monthly H/L (Prev)  : High=" + DoubleToString(monthly_high, trade_digits) + " | Low=" + DoubleToString(monthly_low, trade_digits) + "\n";
   text += "----------------------------------------------------\n";
   text += "[MACHINE LEARNING - ONNX PULLBACK]\n";
   text += "- Filter ML ONNX      : " + ml_status + "\n";
   text += "- Sinyal Terakhir     : " + last_signal_desc + "\n";
   text += "----------------------------------------------------\n";
   text += "[POSISI & MARTINGALE RECOVERY]\n";
   text += "- Posisi EA Terbuka   : " + IntegerToString(marti_level) + " / " + IntegerToString(InpMaxOpenPositions + InpMaxMartingaleStep) + "\n";
   text += "- Mode Martingale     : " + martin_status + "\n";
   text += "- Total Floating P/L  : " + float_str + "\n";
   text += "- Basket Trailing     : " + basket_status + "\n";
   text += "- Single Trailing SL  : " + trailing_status + "\n";
   text += "----------------------------------------------------\n";
   text += "[PERFORMA & PnL EA]\n";
   text += "- PnL Hari Ini (Daily): " + FormatPnL(daily_pnl, balance, daily_wins, daily_losses) + "\n";
   text += "- PnL Total Realized  : " + FormatPnL(total_pnl, balance, total_wins, total_losses) + "\n";
   text += "- Balance / Equity    : $" + DoubleToString(balance, 2) + " / $" + DoubleToString(equity, 2) + "\n";
   text += "====================================================\n";
   
   Comment(text);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Tentukan simbol trading (mendukung XAUUSD, XAUUSD.vx, atau custom pair)
   trade_symbol = (InpCustomSymbol != "") ? InpCustomSymbol : _Symbol;
   
   //--- Coba select symbol, retry 3x jika belum siap
   bool sym_ok = false;
   for(int retry = 0; retry < 3; retry++)
     {
      if(SymbolSelect(trade_symbol, true)) { sym_ok = true; break; }
      Sleep(500);
     }
   if(!sym_ok)
     {
      Alert("[XAU PULLBACK EA] Gagal memilih simbol: ", trade_symbol, ". Pastikan pair ada di Market Watch!");
      Print("OnInit FAILED: Simbol '", trade_symbol, "' tidak ditemukan di Market Watch.");
      return(INIT_FAILED);
     }
   
   trade_digits = (int)SymbolInfoInteger(trade_symbol, SYMBOL_DIGITS);
   trade_point  = SymbolInfoDouble(trade_symbol, SYMBOL_POINT);
   
   //--- Inisialisasi indikator
   handle_EMA      = iMA(trade_symbol, _Period, InpEMA_Period, InpEMA_Shift, MODE_EMA, InpEMA_Price);
   handle_EMA_H1   = iMA(trade_symbol, PERIOD_H1, InpEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   handle_ADX      = iADX(trade_symbol, _Period, InpADX_Period);
   handle_RSI      = iRSI(trade_symbol, _Period, InpRSI_Period, InpRSI_Price);
   handle_ATR      = iATR(trade_symbol, _Period, InpATR_Period);
   handle_ATR_Fast = iATR(trade_symbol, _Period, 5);
   
   if(handle_EMA==INVALID_HANDLE || handle_EMA_H1==INVALID_HANDLE || handle_ADX==INVALID_HANDLE ||
      handle_RSI==INVALID_HANDLE || handle_ATR==INVALID_HANDLE || handle_ATR_Fast==INVALID_HANDLE)
     {
      Alert("[XAU PULLBACK EA] Gagal buat handle indikator untuk pair: ", trade_symbol);
      Print("OnInit FAILED: Handle indikator invalid untuk pair '", trade_symbol, "'");
      return(INIT_FAILED);
     }
   
   //--- Buffer setup (as series agar index 0 = bar running, index 1 = bar terkonfirmasi)
   ArraySetAsSeries(ema_value, true);
   ArraySetAsSeries(ema_h1_value, true);
   ArraySetAsSeries(adx_value, true);
   ArraySetAsSeries(adx_plus_di, true);
   ArraySetAsSeries(adx_minus_di, true);
   ArraySetAsSeries(rsi_value, true);
   ArraySetAsSeries(atr_value, true);
   ArraySetAsSeries(atr_fast_value, true);
   
   //--- Inisialisasi model ONNX Pullback
   if(InpUseMLFilter)
     {
      //--- 1. Coba load langsung dari buffer tersemat di dalam file .ex5 (#resource)
      if(ArraySize(ExtModelONNX) > 0)
        {
         handle_onnx = OnnxCreateFromBuffer(ExtModelONNX, ONNX_DEFAULT);
         if(handle_onnx != INVALID_HANDLE)
            Print("OnInit: Model ONNX Pullback berhasil dimuat langsung dari resource biner tersemat (Embedded .ex5).");
        }
      
      //--- 2. Fallback: coba load dari file fisik disk MQL5/Files/
      if(handle_onnx == INVALID_HANDLE)
         handle_onnx = OnnxCreate("model_xau_pullback_DI.onnx", ONNX_DEFAULT);
      
      //--- 3. Fallback: coba dari subfolder Experts
      if(handle_onnx == INVALID_HANDLE)
         handle_onnx = OnnxCreate("Experts\\model_xau_pullback_DI.onnx", ONNX_DEFAULT);
      
      //--- 4. Fallback legacy model_xau.onnx jika pullback belum terkompilasi
      if(handle_onnx == INVALID_HANDLE)
         handle_onnx = OnnxCreate("model_xau.onnx", ONNX_DEFAULT);
      
      if(handle_onnx == INVALID_HANDLE)
        {
         last_signal_desc = "⚠️ ONNX gagal load! EA jalan tanpa filter ML";
         Print("[XAU PULLBACK EA] Peringatan: Model ONNX tidak ditemukan (error ", GetLastError(), ").",
               " EA tetap berjalan dalam mode Rule-Based (tanpa filter ML).");
        }
      else
        {
         const long input_shape_19[] = {1, 19};
         const long input_shape_13[] = {1, 13};
         bool shape_set = false;
         
         if(OnnxSetInputShape(handle_onnx, 0, input_shape_19))
           {
            onnx_feature_count = 19;
            shape_set = true;
            Print("OnInit: Terdeteksi model ONNX 19 fitur (dengan Market Context PullBack).");
           }
         else if(OnnxSetInputShape(handle_onnx, 0, input_shape_13))
           {
            onnx_feature_count = 13;
            shape_set = true;
            Print("OnInit: Terdeteksi model ONNX 13 fitur (Legacy).");
           }
         
         if(!shape_set)
           {
            Print("Gagal set input shape ONNX. Error: ", GetLastError());
            OnnxRelease(handle_onnx);
            handle_onnx = INVALID_HANDLE;
           }
         else
           {
            const long output_shape_label[] = {1};
            OnnxSetOutputShape(handle_onnx, 0, output_shape_label);
            const long output_shape_probs[] = {1, 2};
            OnnxSetOutputShape(handle_onnx, 1, output_shape_probs);
            last_signal_desc = "✅ ONNX Pullback (" + IntegerToString(onnx_feature_count) + " fitur) dimuat";
            Print("OnInit: Model ONNX Pullback berhasil dikonfigurasi dengan ", onnx_feature_count, " fitur input.");
           }
        }
     }
   else
     {
      last_signal_desc = "ML Filter dinonaktifkan (Rule-Based Only)";
     }
   
   //--- Inisialisasi trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePts);
   trade.SetTypeFillingBySymbol(trade_symbol);
   
   //--- Timer untuk refresh dashboard setiap 1 detik
   EventSetTimer(1);
   
   //--- Reset state pullback
   pb_state = PB_STATE_IDLE;
   
   //--- Ambil level bulanan awal & update dashboard
   UpdateMonthlyLevels();
   UpdateDashboard();
   
   Print("OnInit: EA XAUUSD PULLBACK v2.15 AKTIF | Symbol=", trade_symbol,
         " | Digits=", trade_digits, " | Point=", DoubleToString(trade_point, 8),
         " | MagicNumber=", InpMagicNumber,
         " | Retest Timeout=", InpPullbackTimeoutSec, "s (2 Menit)",
         " | ML=", (InpUseMLFilter ? "ON" : "OFF"));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Hapus Dashboard & timer
   Comment("");
   EventKillTimer();
   
   //--- Release indicator handles
   if(handle_EMA!=INVALID_HANDLE)      IndicatorRelease(handle_EMA);
   if(handle_EMA_H1!=INVALID_HANDLE)   IndicatorRelease(handle_EMA_H1);
   if(handle_ADX!=INVALID_HANDLE)      IndicatorRelease(handle_ADX);
   if(handle_RSI!=INVALID_HANDLE)      IndicatorRelease(handle_RSI);
   if(handle_ATR!=INVALID_HANDLE)      IndicatorRelease(handle_ATR);
   if(handle_ATR_Fast!=INVALID_HANDLE) IndicatorRelease(handle_ATR_Fast);
   
   //--- Release ONNX model
   if(handle_onnx!=INVALID_HANDLE)
     {
      OnnxRelease(handle_onnx);
      handle_onnx = INVALID_HANDLE;
     }
   
   Print("OnDeinit: EA PULLBACK dihentikan, reason=", reason);
  }

//+------------------------------------------------------------------+
//| Timer event: refresh dashboard setiap 1 detik                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Update tampilan dashboard on-chart setiap tick
   UpdateDashboard();
   
   //--- Filter spread (jika diatur)
   if(InpMaxSpreadPts > 0)
     {
      long spread = SymbolInfoInteger(trade_symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPts) return;
     }
   
   //--- Filter waktu (jika diatur)
   if(!IsTimeAllowed()) return;
   
   //--- Update indikator
   if(!UpdateIndicators()) return;
   
   //--- Hitung level candle monthly
   UpdateMonthlyLevels();
   
   //--- Deteksi sinyal entry awal (dijalankan saat bar baru M15 terbentuk)
   CheckForSignal();
   
   //--- State Machine: Pantau konfirmasi retest / pullback setiap tick
   ProcessPullbackStateMachine();
   
   //--- Manajemen posisi (trailing / break-even jika di-extend)
   ManagePositions();
  }

//+------------------------------------------------------------------+
//| Cek apakah waktu trading diizinkan (berdasar jam mulai/akhir)    |
//+------------------------------------------------------------------+
bool IsTimeAllowed()
  {
   if(InpStartHour==0 && InpEndHour==0) return(true); // filter tidak aktif
   
   datetime now  = TimeCurrent();
   int hour      = TimeHour(now);
   
   if(InpStartHour < InpEndHour)
     {
      if(hour < InpStartHour || hour >= InpEndHour) return(false);
     }
   else // melintasi tengah malam (misal 22 sampai 6)
     {
      if(hour < InpStartHour && hour >= InpEndHour) return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Perbarui nilai indikator dari buffer                             |
//+------------------------------------------------------------------+
bool UpdateIndicators()
  {
   //--- Salin data terbaru ke buffer (bar 0 = bar running, bar 1 = bar terkonfirmasi)
   if(CopyBuffer(handle_EMA, 0, 0, 4, ema_value) <= 0)         { if(InpDebugLog) Print("Gagal copy EMA"); return(false); }
   if(CopyBuffer(handle_EMA_H1, 0, 0, 4, ema_h1_value) <= 0)   { if(InpDebugLog) Print("Gagal copy EMA H1"); return(false); }
   if(CopyBuffer(handle_ADX, 0, 0, 4, adx_value) <= 0)         { if(InpDebugLog) Print("Gagal copy ADX Main"); return(false); }
   if(CopyBuffer(handle_ADX, 1, 0, 4, adx_plus_di) <= 0)      { if(InpDebugLog) Print("Gagal copy ADX +DI"); return(false); }
   if(CopyBuffer(handle_ADX, 2, 0, 4, adx_minus_di) <= 0)     { if(InpDebugLog) Print("Gagal copy ADX -DI"); return(false); }
   if(CopyBuffer(handle_RSI, 0, 0, 4, rsi_value) <= 0)         { if(InpDebugLog) Print("Gagal copy RSI"); return(false); }
   if(CopyBuffer(handle_ATR, 0, 0, 4, atr_value) <= 0)         { if(InpDebugLog) Print("Gagal copy ATR"); return(false); }
   if(CopyBuffer(handle_ATR_Fast, 0, 0, 4, atr_fast_value) <= 0) { if(InpDebugLog) Print("Gagal copy ATR Fast"); return(false); }
   
   //--- Pastikan data valid (bukan EMPTY_VALUE)
   if(ema_value[1]==EMPTY_VALUE || adx_value[1]==EMPTY_VALUE ||
      rsi_value[1]==EMPTY_VALUE || atr_value[1]==EMPTY_VALUE)
     {
      if(InpDebugLog) Print("Salah satu indikator masih tidak ada data valid");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Hitung level candle monthly (High & Low Bulan Sebelumnya Shift 1)|
//+------------------------------------------------------------------+
void UpdateMonthlyLevels()
  {
   datetime bar_time = iTime(trade_symbol, _Period, 1);
   if(bar_time == 0) return;
   
   int month_bar = TimeMonth(bar_time);
   static int last_month = -1;
   
   if(month_bar != last_month || monthly_high == 0.0)
     {
      monthly_high = iHigh(trade_symbol, PERIOD_MN1, 1);
      monthly_low  = iLow(trade_symbol, PERIOD_MN1, 1);
      last_month   = month_bar;
      
      if(InpDebugLog) Print("Level Monthly diperbarui: High=", DoubleToString(monthly_high, trade_digits),
                            " Low=", DoubleToString(monthly_low, trade_digits));
     }
  }

//+------------------------------------------------------------------+
//| Node 3: Inferensi Machine Learning (ONNX)                         |
//+------------------------------------------------------------------+
double ML_PredictWinProbability(int signal_type)
  {
   if(!InpUseMLFilter || handle_onnx == INVALID_HANDLE) return(1.0); // Bypass jika off
   
   double cur_close = iClose(trade_symbol, _Period, 1);
   double cur_open  = iOpen(trade_symbol, _Period, 1);
   double cur_high  = iHigh(trade_symbol, _Period, 1);
   double cur_low   = iLow(trade_symbol, _Period, 1);
   double cur_atr   = (atr_value[1] > 0) ? atr_value[1] : trade_point;
   
   // Fitur Vektor (13 fitur legacy atau 19 fitur dengan konteks pasar)
   float features[];
   ArrayResize(features, onnx_feature_count);
   
   features[0]  = (float)((cur_close - ema_value[1]) / cur_atr);                      // dist_to_ema_atr
   features[1]  = (float)adx_value[1];                                                // adx_main
   features[2]  = (float)adx_plus_di[1];                                              // adx_pdi
   features[3]  = (float)adx_minus_di[1];                                             // adx_mdi
   features[4]  = (float)(adx_plus_di[1] - adx_minus_di[1]);                          // adx_di_diff
   features[5]  = (float)rsi_value[1];                                                // rsi
   features[6]  = (float)(cur_atr / cur_close * 1000.0);                              // atr_normalized
   features[7]  = (float)(MathAbs(cur_close - cur_open) / cur_atr);                   // body_atr
   features[8]  = (float)((cur_high - MathMax(cur_open, cur_close)) / cur_atr);       // upper_shadow_atr
   features[9]  = (float)((MathMin(cur_open, cur_close) - cur_low) / cur_atr);       // lower_shadow_atr
   
   datetime bar_time = iTime(trade_symbol, _Period, 1);
   MqlDateTime dt;
   TimeToStruct(bar_time, dt);
   features[10] = (float)dt.hour;                                                     // hour
   features[11] = (float)dt.day_of_week;                                              // day_of_week
   features[12] = (float)signal_type;                                                 // signal_type (1=Buy, 2=Sell)
   
   if(onnx_feature_count == 19)
     {
      // Kemiringan EMA
      features[13] = (float)((ema_value[1] - ema_value[3]) / (2.0 * cur_atr));         // ema_slope_atr
      // Tren Higher Timeframe H1
      features[14] = (float)((cur_close > ema_h1_value[0]) ? 1.0 : -1.0);             // htf_trend
      // Volatility Regime Ratio (ATR 5 / ATR 14)
      double cur_atr_fast = (atr_fast_value[1] > 0) ? atr_fast_value[1] : cur_atr;
      features[15] = (float)(cur_atr_fast / cur_atr);                                 // volatility_ratio
      // Volume Ratio vs SMA Volume 20
      long vol_sum = 0;
      for(int v = 1; v <= 20; v++) vol_sum += iTickVolume(trade_symbol, _Period, v);
      double avg_vol = (double)vol_sum / 20.0;
      long bar_vol = iTickVolume(trade_symbol, _Period, 1);
      features[16] = (float)((avg_vol > 0) ? ((double)bar_vol / avg_vol) : 1.0);      // vol_ratio
      // Candlestick Pattern Flags
      int pin = IsPinBarBullish() ? 1 : (IsPinBarBearish() ? -1 : 0);
      int eng = IsEngulfingBullish() ? 1 : (IsEngulfingBearish() ? -1 : 0);
      features[17] = (float)pin;                                                      // is_pinbar
      features[18] = (float)eng;                                                      // is_engulfing
     }
   
   // Output buffers dari ONNX
   long  predicted_label[1];
   float predicted_probs[2];
   
   if(!OnnxRun(handle_onnx, ONNX_NO_CONVERSION, features, predicted_label, predicted_probs))
     {
      if(InpDebugLog) Print("OnnxRun gagal dieksekusi. Error: ", GetLastError());
      return(1.0); // Fallback bypass
     }
   
   double win_prob = (double)predicted_probs[1];
   last_ml_prob = win_prob;
   
   if(InpDebugLog)
      Print("NODE 3 (ML ONNX PULLBACK): Sinyal Type=", signal_type, " -> Win Prob=", DoubleToString(win_prob * 100.0, 1), "%");
   
   return(win_prob);
  }

//+------------------------------------------------------------------+
//| Deteksi sinyal entry berdasarkan pipeline (awal bar baru M15)    |
//+------------------------------------------------------------------+
void CheckForSignal()
  {
   //--- Hindari sinyal berulang pada bar yang sama (eksekusi pada pembukaan bar baru)
   datetime bar_time = iTime(trade_symbol, _Period, 0);
   if(bar_time == last_bar_time) return;
   last_bar_time = bar_time;
   
   //--- Jika ada pending retest dari bar sebelumnya yang belum terisi, otomatis batalkan
   if(pb_state != PB_STATE_IDLE)
     {
      if(InpDebugLog) Print("PULLBACK RESET: Bar M15 baru terbentuk. Pending sinyal lama dibatalkan.");
      pb_state = PB_STATE_IDLE;
     }

   //--- Ambil harga & indikator dari Bar 1 (bar yang sudah terkonfirmasi resmi)
   double close1      = iClose(trade_symbol, _Period, 1);
   double ema1        = ema_value[1];
   double adx1        = adx_value[1];
   double plus_di1    = adx_plus_di[1];
   double minus_di1   = adx_minus_di[1];
   double rsi1        = rsi_value[1];
   
   //--- Flag hasil tiap node
   bool follow_buy    = false;
   bool follow_sell   = false;
   bool reversal_buy  = false;
   bool reversal_sell = false;
   
   //=================================================================
   //=== NODE 1: FOLLOW TREND (EMA + ADX Trend & DI + RSI Non-Ekstrem)
   //=================================================================
   if(InpTradeMode==MODE_FOLLOW_ONLY || InpTradeMode==MODE_BOTH)
     {
      bool adx_buy_dir  = InpADX_UseDI ? (plus_di1 > minus_di1) : true;
      bool adx_sell_dir = InpADX_UseDI ? (minus_di1 > plus_di1) : true;
      
      // FOLLOW BUY: harga di atas EMA, ADX kuat + +DI > -DI, RSI tidak overbought
      if(close1 > ema1 && adx1 >= InpADX_Strength && adx_buy_dir && rsi1 < InpRSI_Overbought)
        {
         follow_buy = true;
         last_signal_desc = "FOLLOW BUY (Trend Bullish Terkonfirmasi)";
         if(InpDebugLog) Print("NODE 1: FOLLOW BUY triggered");
        }
      
      // FOLLOW SELL: harga di bawah EMA, ADX kuat + -DI > +DI, RSI tidak oversold
      if(close1 < ema1 && adx1 >= InpADX_Strength && adx_sell_dir && rsi1 > InpRSI_Oversold)
        {
         follow_sell = true;
         last_signal_desc = "FOLLOW SELL (Trend Bearish Terkonfirmasi)";
         if(InpDebugLog) Print("NODE 1: FOLLOW SELL triggered");
        }
     }
   
   //=================================================================
   //=== NODE 2: REVERSAL (RSI Ekstrem + Konfirmasi Pola Bar 1-2)  ===
   //=================================================================
   if(InpTradeMode==MODE_REVERSAL_ONLY || InpTradeMode==MODE_BOTH)
     {
      // REVERSAL BUY: RSI oversold + konfirmasi pin bar / engulfing bullish
      if(rsi1 <= InpRSI_Oversold)
        {
         bool bullish = false;
         if(InpUsePinBar && IsPinBarBullish())       bullish = true;
         if(InpUseEngulfing && IsEngulfingBullish()) bullish = true;
         if(bullish)
           {
            reversal_buy = true;
            last_signal_desc = "REVERSAL BUY (Oversold + Pola Bullish)";
            if(InpDebugLog) Print("NODE 2: REVERSAL BUY triggered");
           }
        }
      
      // REVERSAL SELL: RSI overbought + konfirmasi pin bar / engulfing bearish
      if(rsi1 >= InpRSI_Overbought)
        {
         bool bearish = false;
         if(InpUsePinBar && IsPinBarBearish())       bearish = true;
         if(InpUseEngulfing && IsEngulfingBearish()) bearish = true;
         if(bearish)
           {
            reversal_sell = true;
            last_signal_desc = "REVERSAL SELL (Overbought + Pola Bearish)";
            if(InpDebugLog) Print("NODE 2: REVERSAL SELL triggered");
           }
        }
     }
   
   //=================================================================
   //=== NODE 3: ML/ONNX Inference Filter (Fase 2)                 ===
   //=================================================================
   bool do_buy  = follow_buy  || reversal_buy;
   bool do_sell = follow_sell || reversal_sell;
   
   if(InpUseMLFilter)
     {
      if(do_buy)
        {
         double prob_buy = ML_PredictWinProbability(1);
         if(prob_buy < InpMLMinWinProb)
           {
            last_signal_desc = "BUY Terfilter ML (Prob: " + DoubleToString(prob_buy*100.0, 1) + "%)";
            if(InpDebugLog) Print("ML FILTER: BUY difilter out (Prob Win: ", DoubleToString(prob_buy*100.0, 1), "% < ", DoubleToString(InpMLMinWinProb*100.0, 1), "%)");
            do_buy = false;
           }
         else
           {
            last_signal_desc = "BUY Lolos Filter ML (Prob: " + DoubleToString(prob_buy*100.0, 1) + "%)";
           }
        }
      if(do_sell)
        {
         double prob_sell = ML_PredictWinProbability(2);
         if(prob_sell < InpMLMinWinProb)
           {
            last_signal_desc = "SELL Terfilter ML (Prob: " + DoubleToString(prob_sell*100.0, 1) + "%)";
            if(InpDebugLog) Print("ML FILTER: SELL difilter out (Prob Win: ", DoubleToString(prob_sell*100.0, 1), "% < ", DoubleToString(InpMLMinWinProb*100.0, 1), "%)");
            do_sell = false;
           }
         else
           {
            last_signal_desc = "SELL Lolos Filter ML (Prob: " + DoubleToString(prob_sell*100.0, 1) + "%)";
           }
        }
     }
   
   //=================================================================
   //=== NODE 4: Penjadwalan Masuk Posisi (Pullback vs Instant)    ===
   //=================================================================
   if(!do_buy && !do_sell) return; // tidak ada sinyal
   
   //--- Pastikan posisi belum melebihi batas (khusus simbol dan magic number EA ini)
   int total_positions = CountOpenPositions();
   if(total_positions >= InpMaxOpenPositions)
     {
      if(InpDebugLog) Print("Maks posisi tercapai (", total_positions, ")");
      return;
     }
   
   //--- Jika mode Pullback dinonaktifkan, langsung eksekusi instan di harga open bar baru
   if(!InpUsePullback)
     {
      if(do_buy && InpIsBuyAllowed)   OpenPosition(ORDER_TYPE_BUY);
      if(do_sell && InpIsSellAllowed) OpenPosition(ORDER_TYPE_SELL);
      return;
     }

   //--- MODE PULLBACK AKTIF: Hitung batas jarak diskon & batas cancel
   double cur_atr = (ArraySize(atr_value) > 1 && atr_value[1] > 0) ? atr_value[1] : (trade_point * 100.0);
   double discount_dist = 0.0;
   double cancel_dist   = 0.0;

   if(InpPullbackDistMode == PULLBACK_DIST_ATR)
     {
      discount_dist = cur_atr * InpPullbackATR_Mult;
      cancel_dist   = cur_atr * InpCancelATR_Mult;
     }
   else
     {
      discount_dist = InpPullbackFixedPts * trade_point;
      cancel_dist   = InpCancelFixedPts * trade_point;
     }

   if(do_buy && InpIsBuyAllowed)
     {
      pb_state        = PB_STATE_PENDING_BUY;
      pb_signal_time  = TimeCurrent();
      pb_ref_price    = SymbolInfoDouble(trade_symbol, SYMBOL_ASK);
      pb_target_price = NormalizeDouble(pb_ref_price - discount_dist, trade_digits); // Koreksi ke bawah (diskon beli)
      pb_cancel_price = NormalizeDouble(pb_ref_price + cancel_dist, trade_digits);   // Batal jika harga langsung lari ke atas
      last_signal_desc = "PULLBACK BUY (Menunggu Diskon <= " + DoubleToString(pb_target_price, trade_digits) + " dalam " + IntegerToString(InpPullbackTimeoutSec) + "s)";
      if(InpDebugLog)
         Print("PULLBACK ARMED [BUY]: Ref=", DoubleToString(pb_ref_price, trade_digits),
               " | Diskon Target<=", DoubleToString(pb_target_price, trade_digits),
               " | Cancel Boundary>=", DoubleToString(pb_cancel_price, trade_digits),
               " | Timeout=", InpPullbackTimeoutSec, "s");
     }
   else if(do_sell && InpIsSellAllowed)
     {
      pb_state        = PB_STATE_PENDING_SELL;
      pb_signal_time  = TimeCurrent();
      pb_ref_price    = SymbolInfoDouble(trade_symbol, SYMBOL_BID);
      pb_target_price = NormalizeDouble(pb_ref_price + discount_dist, trade_digits); // Koreksi ke atas (diskon jual)
      pb_cancel_price = NormalizeDouble(pb_ref_price - cancel_dist, trade_digits);   // Batal jika harga langsung dump ke bawah
      last_signal_desc = "PULLBACK SELL (Menunggu Diskon >= " + DoubleToString(pb_target_price, trade_digits) + " dalam " + IntegerToString(InpPullbackTimeoutSec) + "s)";
      if(InpDebugLog)
         Print("PULLBACK ARMED [SELL]: Ref=", DoubleToString(pb_ref_price, trade_digits),
               " | Diskon Target>=", DoubleToString(pb_target_price, trade_digits),
               " | Cancel Boundary<=", DoubleToString(pb_cancel_price, trade_digits),
               " | Timeout=", InpPullbackTimeoutSec, "s");
     }
  }

//+------------------------------------------------------------------+
//| State Machine PullBack: Dieksekusi setiap tick untuk memantau    |
//| harga koreksi (diskon), pembatalan lari, atau masa expired 2M    |
//+------------------------------------------------------------------+
void ProcessPullbackStateMachine()
  {
   if(!InpUsePullback || pb_state == PB_STATE_IDLE) return;
   
   // 1. Validasi batas open posisi
   if(CountOpenPositions() >= InpMaxOpenPositions)
     {
      pb_state = PB_STATE_IDLE;
      return;
     }
     
   int elapsed = (int)(TimeCurrent() - pb_signal_time);
   
   // 2. Cek Timeout (default 120 detik / 2 menit pertama candle)
   if(elapsed > InpPullbackTimeoutSec)
     {
      last_signal_desc = "Sinyal Pullback Hangus (Waktu Habis " + IntegerToString(elapsed) + "s > " + IntegerToString(InpPullbackTimeoutSec) + "s)";
      if(InpDebugLog) Print("PULLBACK TIMEOUT: Batas 2 menit habis tanpa koreksi diskon. Sinyal dibatalkan.");
      pb_state = PB_STATE_IDLE;
      return;
     }
     
   // 3. Evaluasi State BUY (Menunggu harga terkoreksi turun)
   if(pb_state == PB_STATE_PENDING_BUY)
     {
      double ask = SymbolInfoDouble(trade_symbol, SYMBOL_ASK);
      
      // Kondisi A: Harga keburu terbang ke atas melewati batas cancel (Anti-FOMO)
      if(ask >= pb_cancel_price)
        {
         last_signal_desc = "Sinyal BUY Dibatalkan (Harga Lari Duluan ke " + DoubleToString(ask, trade_digits) + " >= " + DoubleToString(pb_cancel_price, trade_digits) + ")";
         if(InpDebugLog) Print("PULLBACK CANCEL: BUY dibatalkan karena harga lari ke ", ask, " >= batas ", pb_cancel_price);
         pb_state = PB_STATE_IDLE;
         return;
        }
        
      // Kondisi B: Harga terkoreksi turun menyentuh/masuk zona diskon -> Eksekusi BUY!
      if(ask <= pb_target_price)
        {
         last_signal_desc = "PULLBACK BUY Terisi! (Diskon di " + DoubleToString(ask, trade_digits) + " | Retest +" + IntegerToString(elapsed) + "s)";
         if(InpDebugLog) Print("PULLBACK TRIGGERED: BUY dieksekusi di harga diskon ", ask, " <= target ", pb_target_price, " (waktu: ", elapsed, "s)");
         pb_state = PB_STATE_IDLE;
         if(InpIsBuyAllowed) OpenPosition(ORDER_TYPE_BUY);
         return;
        }
     }
     
   // 4. Evaluasi State SELL (Menunggu harga terkoreksi naik)
   if(pb_state == PB_STATE_PENDING_SELL)
     {
      double bid = SymbolInfoDouble(trade_symbol, SYMBOL_BID);
      
      // Kondisi A: Harga keburu dump ke bawah melewati batas cancel (Anti-FOMO)
      if(bid <= pb_cancel_price)
        {
         last_signal_desc = "Sinyal SELL Dibatalkan (Harga Lari Duluan ke " + DoubleToString(bid, trade_digits) + " <= " + DoubleToString(pb_cancel_price, trade_digits) + ")";
         if(InpDebugLog) Print("PULLBACK CANCEL: SELL dibatalkan karena harga lari ke ", bid, " <= batas ", pb_cancel_price);
         pb_state = PB_STATE_IDLE;
         return;
        }
        
      // Kondisi B: Harga terkoreksi naik menyentuh/masuk zona diskon -> Eksekusi SELL!
      if(bid >= pb_target_price)
        {
         last_signal_desc = "PULLBACK SELL Terisi! (Diskon di " + DoubleToString(bid, trade_digits) + " | Retest +" + IntegerToString(elapsed) + "s)";
         if(InpDebugLog) Print("PULLBACK TRIGGERED: SELL dieksekusi di harga diskon ", bid, " >= target ", pb_target_price, " (waktu: ", elapsed, "s)");
         pb_state = PB_STATE_IDLE;
         if(InpIsSellAllowed) OpenPosition(ORDER_TYPE_SELL);
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Deteksi pola Pin Bar bullish (Bar 1 Terkonfirmasi)               |
//+------------------------------------------------------------------+
bool IsPinBarBullish()
  {
   double open1  = iOpen(trade_symbol, _Period, 1);
   double close1 = iClose(trade_symbol, _Period, 1);
   double high1  = iHigh(trade_symbol, _Period, 1);
   double low1   = iLow(trade_symbol, _Period, 1);
   
   double body  = MathAbs(close1 - open1);
   double range = high1 - low1;
   if(range == 0) return(false);
   
   double upper_shadow = high1 - MathMax(open1, close1);
   double lower_shadow = MathMin(open1, close1) - low1;
   
   return(lower_shadow >= 2.0 * body && upper_shadow <= body);
  }

//+------------------------------------------------------------------+
//| Deteksi pola Pin Bar bearish (Bar 1 Terkonfirmasi)               |
//+------------------------------------------------------------------+
bool IsPinBarBearish()
  {
   double open1  = iOpen(trade_symbol, _Period, 1);
   double close1 = iClose(trade_symbol, _Period, 1);
   double high1  = iHigh(trade_symbol, _Period, 1);
   double low1   = iLow(trade_symbol, _Period, 1);
   
   double body  = MathAbs(close1 - open1);
   double range = high1 - low1;
   if(range == 0) return(false);
   
   double upper_shadow = high1 - MathMax(open1, close1);
   double lower_shadow = MathMin(open1, close1) - low1;
   
   return(upper_shadow >= 2.0 * body && lower_shadow <= body);
  }

//+------------------------------------------------------------------+
//| Deteksi pola Engulfing bullish (Bar 1 meng-engulf Bar 2)        |
//+------------------------------------------------------------------+
bool IsEngulfingBullish()
  {
   double open1  = iOpen(trade_symbol, _Period, 1);
   double close1 = iClose(trade_symbol, _Period, 1);
   double open2  = iOpen(trade_symbol, _Period, 2);
   double close2 = iClose(trade_symbol, _Period, 2);
   
   bool prev_bearish = (close2 < open2);
   bool curr_bullish = (close1 > open1);
   bool engulfs      = (close1 > open2) && (open1 < close2);
   
   return(prev_bearish && curr_bullish && engulfs);
  }

//+------------------------------------------------------------------+
//| Deteksi pola Engulfing bearish (Bar 1 meng-engulf Bar 2)        |
//+------------------------------------------------------------------+
bool IsEngulfingBearish()
  {
   double open1  = iOpen(trade_symbol, _Period, 1);
   double close1 = iClose(trade_symbol, _Period, 1);
   double open2  = iOpen(trade_symbol, _Period, 2);
   double close2 = iClose(trade_symbol, _Period, 2);
   
   bool prev_bullish = (close2 > open2);
   bool curr_bearish = (close1 < open1);
   bool engulfs      = (close1 < open2) && (open1 > close2);
   
   return(prev_bullish && curr_bearish && engulfs);
  }

//+------------------------------------------------------------------+
//| Hitung Stop Loss level harga                                     |
//+------------------------------------------------------------------+
double ComputeStopLoss(ENUM_ORDER_TYPE type, double entry_price, double lot = 0.0)
  {
   double sl = 0.0;
   
   if(InpSLMode == SL_ATR)
     {
      double atr = (atr_value[1] > 0) ? atr_value[1] : (InpSL_FixedPts * trade_point / InpATR_SL_Mult);
      sl = (type == ORDER_TYPE_BUY) ? (entry_price - InpATR_SL_Mult * atr)
                                    : (entry_price + InpATR_SL_Mult * atr);
     }
   else if(InpSLMode == SL_LEVEL)
     {
      double buffer_pts = InpSLBuffer * trade_point;
      if(type == ORDER_TYPE_BUY)
         sl = (monthly_low > 0) ? (monthly_low - buffer_pts) : (entry_price - InpSL_FixedPts * trade_point);
      else
         sl = (monthly_high > 0) ? (monthly_high + buffer_pts) : (entry_price + InpSL_FixedPts * trade_point);
     }
   else if(InpSLMode == SL_MONEY)
     {
      double tick_value  = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size   = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
      double point_value = (tick_size > 0) ? (tick_value * trade_point / tick_size) : 0.01;
      double trade_lot   = (lot > 0) ? lot : InpFixedLot;
      double sl_dist_pts = (trade_lot * point_value > 0) ? (InpSL_MoneyUSD / (trade_lot * point_value)) : InpSL_FixedPts;
      double sl_pts      = sl_dist_pts * trade_point;
      sl = (type == ORDER_TYPE_BUY) ? (entry_price - sl_pts) : (entry_price + sl_pts);
     }
   else // SL_FIXED
     {
      double sl_pts = InpSL_FixedPts * trade_point;
      sl = (type == ORDER_TYPE_BUY) ? (entry_price - sl_pts) : (entry_price + sl_pts);
     }
   
   return(NormalizeDouble(sl, trade_digits));
  }

//+------------------------------------------------------------------+
//| Hitung Take Profit level harga                                   |
//+------------------------------------------------------------------+
double ComputeTakeProfit(ENUM_ORDER_TYPE type, double entry_price, double sl_price, double lot = 0.0)
  {
   double tp = 0.0;
   double sl_dist = MathAbs(entry_price - sl_price);
   if(sl_dist <= 0) sl_dist = InpSL_FixedPts * trade_point;
   
   if(InpTPMode == TP_MONTHLY_LEVEL)
     {
      double buffer_pts = InpMonthlyBuffer * trade_point;
      if(type == ORDER_TYPE_BUY)
        {
         tp = monthly_high + buffer_pts;
         if(tp <= entry_price + sl_dist * 0.5)
            tp = entry_price + sl_dist * 1.5;
        }
      else
        {
         tp = monthly_low - buffer_pts;
         if(tp >= entry_price - sl_dist * 0.5 || tp <= 0)
            tp = entry_price - sl_dist * 1.5;
        }
     }
   else if(InpTPMode == TP_ATR_RR)
     {
      if(type == ORDER_TYPE_BUY)
         tp = entry_price + sl_dist * InpTP_RR_Ratio;
      else
         tp = entry_price - sl_dist * InpTP_RR_Ratio;
     }
   else if(InpTPMode == TP_MONEY)
     {
      double tick_value  = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size   = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
      double point_value = (tick_size > 0) ? (tick_value * trade_point / tick_size) : 0.01;
      double trade_lot   = (lot > 0) ? lot : InpFixedLot;
      double tp_dist_pts = (trade_lot * point_value > 0) ? (InpTP_MoneyUSD / (trade_lot * point_value)) : InpTP_FixedPts;
      double tp_pts      = tp_dist_pts * trade_point;
      tp = (type == ORDER_TYPE_BUY) ? (entry_price + tp_pts) : (entry_price - tp_pts);
     }
   else // TP_FIXED
     {
      double tp_pts = InpTP_FixedPts * trade_point;
      if(type == ORDER_TYPE_BUY)
         tp = entry_price + tp_pts;
      else
         tp = entry_price - tp_pts;
     }
   
   return(NormalizeDouble(tp, trade_digits));
  }

//+------------------------------------------------------------------+
//| Buka posisi (buy atau sell) dengan SL/TP dan lot yang sesuai    |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type)
  {
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(trade_symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(trade_symbol, SYMBOL_BID);

   //--- Hitung lot dasar berdasarkan mode terlebih dahulu
   double lot = 0.0;
   if(InpLotMode == LOT_RISK_PERCENT)
     {
      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double risk_money = equity * InpRiskPercent / 100.0;
      
      double sl_distance_pts = InpSL_FixedPts;
      if(InpSLMode == SL_ATR)
        {
         double atr = (atr_value[1] > 0) ? atr_value[1] : (InpSL_FixedPts * trade_point / InpATR_SL_Mult);
         sl_distance_pts = (atr * InpATR_SL_Mult) / trade_point;
        }
      
      double tick_value      = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size       = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
      double point_value     = (tick_size > 0) ? (tick_value * trade_point / tick_size) : 0.01;
      
      if(sl_distance_pts > 0 && point_value > 0)
         lot = risk_money / (sl_distance_pts * point_value);
      else
         lot = InpFixedLot;
     }
   else
     {
      lot = InpFixedLot;
     }
   
   // Normalisasi lot sesuai batasan broker
   double min_lot  = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_STEP);
   if(step_lot > 0) lot = MathFloor(lot / step_lot) * step_lot;
   lot = MathMax(min_lot, MathMin(max_lot, lot));
   lot = NormalizeDouble(lot, 2);

   //--- Hitung SL & TP (dengan menyertakan volume lot)
   double sl    = ComputeStopLoss(type, price, lot);
   double tp    = ComputeTakeProfit(type, price, sl, lot);
   
   //--- Validasi SL/TP sesuai StopLevel broker
   long stop_level = SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_distance = (double)stop_level * trade_point;
   if(min_distance > 0)
     {
      if(MathAbs(price - sl) < min_distance)
         sl = (type == ORDER_TYPE_BUY) ? price - min_distance : price + min_distance;
      if(tp > 0 && MathAbs(tp - price) < min_distance)
         tp = (type == ORDER_TYPE_BUY) ? price + min_distance : price - min_distance;
     }
   
   sl = NormalizeDouble(sl, trade_digits);
   tp = NormalizeDouble(tp, trade_digits);
   
   //--- Eksekusi order
   bool res = false;
   if(type == ORDER_TYPE_BUY)
      res = trade.Buy(lot, trade_symbol, price, sl, tp, "XAU PullBack BUY");
   else if(type == ORDER_TYPE_SELL)
      res = trade.Sell(lot, trade_symbol, price, sl, tp, "XAU PullBack SELL");
   
   if(!res)
     {
      Print("Gagal membuka posisi PullBack: ", trade.ResultRetcodeDescription());
      return;
     }
   
   if(InpDebugLog)
     {
      string type_str = (type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
      Print("Posisi PullBack ", type_str, " terbuka: lot=", DoubleToString(lot, 2),
            " price=", DoubleToString(price, trade_digits),
            " sl=", DoubleToString(sl, trade_digits),
            " tp=", DoubleToString(tp, trade_digits));
     }
   
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Manajemen posisi: Trailing Stop, Basket Trailing, Martingale     |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   int current_level = CountOpenPositions();

   //--- Reset basket trailing state saat tidak ada posisi terbuka
   if(current_level == 0)
     {
      if(basket_trailing_active || basket_max_profit != 0.0)
        {
         basket_trailing_active = false;
         basket_max_profit      = 0.0;
         if(InpDebugLog) Print("BASKET TRAILING: Semua posisi ditutup, state direset.");
        }
      return;
     }

   double total_float = GetTotalFloatingProfit();
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);

   //=================================================================
   //=== BAGIAN 1: Cek Real-time Protection berbasis Dollar ($)     ===
   //=================================================================
   if(InpSLMode == SL_MONEY || InpTPMode == TP_MONEY)
     {
      // Target Take Profit ($)
      if(InpTPMode == TP_MONEY && total_float >= InpTP_MoneyUSD)
        {
         Print("MONEY TP HIT: Total floating profit $", DoubleToString(total_float, 2),
               " >= Target TP $", DoubleToString(InpTP_MoneyUSD, 2), " → Tutup semua ", current_level, " posisi");
         basket_trailing_active = false;
         basket_max_profit      = 0.0;
         CloseAllPositions();
         return;
        }
      // Batas Stop Loss ($)
      if(InpSLMode == SL_MONEY && total_float <= -InpSL_MoneyUSD)
        {
         Print("MONEY SL HIT: Total floating loss $", DoubleToString(total_float, 2),
               " <= Batas SL -$", DoubleToString(InpSL_MoneyUSD, 2), " → Tutup semua ", current_level, " posisi");
         basket_trailing_active = false;
         basket_max_profit      = 0.0;
         CloseAllPositions();
         return;
        }
     }

   //=================================================================
   //=== BAGIAN 2: Single Trailing Stop (per posisi individual)     ===
   //=================================================================
   if(InpUseTrailing && current_level == 1)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(pos_info.SelectByIndex(i))
           {
            if(pos_info.Symbol() == trade_symbol && pos_info.Magic() == InpMagicNumber)
              {
               ENUM_POSITION_TYPE p_type = pos_info.PositionType();
               double open_p  = pos_info.PriceOpen();
               double cur_sl  = pos_info.StopLoss();
               double cur_tp  = pos_info.TakeProfit();
               ulong  ticket  = pos_info.Ticket();
               double cur_p   = (p_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(trade_symbol, SYMBOL_BID)
                                                              : SymbolInfoDouble(trade_symbol, SYMBOL_ASK);

               double profit_pts = (p_type == POSITION_TYPE_BUY) ? (cur_p - open_p) / trade_point
                                                                 : (open_p - cur_p) / trade_point;

               // Mode 0: Step-Lock (Kunci profit bertahap per milestone)
               if(InpTrailingMode == TRAIL_STEP_LOCK)
                 {
                  if(profit_pts >= InpTrailingStartPts)
                    {
                     double excess_pts = profit_pts - InpTrailingStartPts;
                     int steps = (InpTrailingStepPoints > 0) ? (int)MathFloor(excess_pts / InpTrailingStepPoints) : 0;
                     double lock_pts = InpTrailingLockPts + (steps * InpTrailingMovePoints);
                     double new_sl   = (p_type == POSITION_TYPE_BUY) ? (open_p + lock_pts * trade_point)
                                                                     : (open_p - lock_pts * trade_point);
                     new_sl = NormalizeDouble(new_sl, trade_digits);

                     bool need_modify = false;
                     if(p_type == POSITION_TYPE_BUY  && (cur_sl == 0.0 || new_sl > cur_sl + trade_point)) need_modify = true;
                     if(p_type == POSITION_TYPE_SELL && (cur_sl == 0.0 || new_sl < cur_sl - trade_point)) need_modify = true;

                     if(need_modify)
                       {
                        if(trade.PositionModify(ticket, new_sl, cur_tp))
                          {
                           if(InpDebugLog)
                              Print("STEP-LOCK TRAILING: Posisi ticket=", ticket, " SL dikunci ke ", DoubleToString(new_sl, trade_digits),
                                    " (+", DoubleToString(lock_pts, 0), " pts profit terkunci, Step ke-", steps, ")");
                          }
                       }
                    }
                 }
               // Mode 1: Classic Trailing
               else if(InpTrailingMode == TRAIL_CLASSIC)
                 {
                  if(profit_pts >= InpTrailingStartPts)
                    {
                     double new_sl = (p_type == POSITION_TYPE_BUY) ? (cur_p - InpTrailingDistPts * trade_point)
                                                                   : (cur_p + InpTrailingDistPts * trade_point);
                     new_sl = NormalizeDouble(new_sl, trade_digits);

                     bool need_modify = false;
                     if(p_type == POSITION_TYPE_BUY  && (cur_sl == 0.0 || new_sl >= cur_sl + InpTrailingStepPts * trade_point)) need_modify = true;
                     if(p_type == POSITION_TYPE_SELL && (cur_sl == 0.0 || new_sl <= cur_sl - InpTrailingStepPts * trade_point)) need_modify = true;

                     if(need_modify)
                       {
                        if(trade.PositionModify(ticket, new_sl, cur_tp))
                          {
                           if(InpDebugLog)
                              Print("CLASSIC TRAILING: Posisi ticket=", ticket, " SL digeser ke ", DoubleToString(new_sl, trade_digits));
                          }
                       }
                    }
                 }
              }
           }
        }
     }

   //=================================================================
   //=== BAGIAN 3: Dynamic Martingale Averaging Recovery Engine     ===
   //=================================================================
   if(!InpUseMartingale) return;

   //--- 3a. Basket Trailing Profit (ketika ada 1 posisi atau lebih)
   if(InpUseBasketTrailing)
     {
      if(!basket_trailing_active && total_float >= InpBasketTrailStartUSD)
        {
         basket_trailing_active = true;
         basket_max_profit      = total_float;
         Print("BASKET TRAILING AKTIF: Floating profit $", DoubleToString(total_float, 2),
               " >= Start $", DoubleToString(InpBasketTrailStartUSD, 2),
               " | Profit awal yang dikunci: $", DoubleToString(InpBasketTrailLockUSD, 2));
        }

      if(basket_trailing_active)
        {
         if(total_float > basket_max_profit)
            basket_max_profit = total_float;

         double excess_profit = basket_max_profit - InpBasketTrailStartUSD;
         int steps = (InpBasketTrailStepUSD > 0) ? (int)MathFloor(excess_profit / InpBasketTrailStepUSD) : 0;
         double current_lock_usd = InpBasketTrailLockUSD + (steps * InpBasketTrailMoveUSD);

         if(total_float < current_lock_usd)
           {
            Print("BASKET TRAILING HIT: Floating turun ke $", DoubleToString(total_float, 2),
                  " < Lock Level $", DoubleToString(current_lock_usd, 2),
                  " (Peak: $", DoubleToString(basket_max_profit, 2), ", Step ke-", steps, ")",
                  " → Tutup SEMUA ", current_level, " posisi!");
            basket_trailing_active = false;
            basket_max_profit      = 0.0;
            CloseAllPositions();
            return;
           }
        }
     }

   //--- 3b. Cek Target Profit Fixed Poin untuk semua posisi Martingale (jika trailing off)
   if(!InpUseBasketTrailing && current_level > 1)
     {
      double first_entry = 0.0, last_entry_unused = 0.0;
      ENUM_POSITION_TYPE p_type;
      if(GetFirstPosition(p_type, first_entry, last_entry_unused))
        {
         double cur_price = (p_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(trade_symbol, SYMBOL_BID)
                                                          : SymbolInfoDouble(trade_symbol, SYMBOL_ASK);
         double profit_dist_pts = (p_type == POSITION_TYPE_BUY) ? (cur_price - first_entry) / trade_point
                                                                : (first_entry - cur_price) / trade_point;
         if(profit_dist_pts >= InpMartingaleProfitPts)
           {
            Print("MARTINGALE: Target profit total tercapai (+", DoubleToString(profit_dist_pts, 0), " poin) → Tutup semua posisi!");
            CloseAllPositions();
            return;
           }
        }
     }

   //--- 3c. Cek apakah level averaging sudah mencapai batas maksimal
   if(current_level >= (1 + InpMaxMartingaleStep)) return;

   //--- 3d. Cek Risk Margin Guard
   double margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
   if(equity > 0 && (margin_used / equity * 100.0) >= InpMaxRiskMargin)
     {
      if(InpDebugLog) Print("MARTINGALE GUARD: Margin sudah mencapai batas aman (", DoubleToString(margin_used/equity*100.0, 1), "% >= ", InpMaxRiskMargin, "%)");
      return;
     }

   //--- 3e. Dapatkan harga entry terakhir dan arah posisi
   double first_entry_price = 0.0, last_entry = 0.0;
   ENUM_POSITION_TYPE pos_type;
   if(!GetFirstPosition(pos_type, first_entry_price, last_entry)) return;

   double cur_price = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(trade_symbol, SYMBOL_ASK)
                                                      : SymbolInfoDouble(trade_symbol, SYMBOL_BID);

   // Hitung jarak grid yang dibutuhkan
   double dist_pts = 0.0;
   if(InpMartiDistMode == MARTI_DIST_ATR)
     {
      double atr = (atr_value[1] > 0) ? atr_value[1] : (InpMartingaleDistPts * trade_point / InpMartiATR_Mult);
      dist_pts = atr * InpMartiATR_Mult;
     }
   else
     {
      dist_pts = InpMartingaleDistPts * trade_point;
     }

   //--- 3f. Cek apakah harga sudah bergerak cukup BERLAWANAN arah dari entry terakhir
   bool should_average = false;
   if(pos_type == POSITION_TYPE_BUY && cur_price <= last_entry - dist_pts)
      should_average = true;
   else if(pos_type == POSITION_TYPE_SELL && cur_price >= last_entry + dist_pts)
      should_average = true;

   if(!should_average) return;

   //--- 3g. Hitung lot untuk posisi averaging
   double base_lot = InpFixedLot;
   if(InpLotMode == LOT_RISK_PERCENT)
     {
      double risk_money  = equity * InpRiskPercent / 100.0;
      double tick_value  = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size   = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
      double point_value = (tick_size > 0) ? (tick_value * trade_point / tick_size) : 0.01;
      double sl_dist_pts = InpSL_FixedPts;
      if(sl_dist_pts > 0 && point_value > 0)
         base_lot = risk_money / (sl_dist_pts * point_value);
      else
         base_lot = InpFixedLot;
     }

   double avg_lot = base_lot * MathPow(InpMartingaleMult, current_level);

   // Normalisasi lot
   double min_lot  = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(trade_symbol, SYMBOL_VOLUME_STEP);
   if(step_lot > 0) avg_lot = MathFloor(avg_lot / step_lot) * step_lot;
   avg_lot = MathMax(min_lot, MathMin(max_lot, avg_lot));
   avg_lot = NormalizeDouble(avg_lot, 2);

   //--- Buka posisi averaging tanpa SL/TP individual
   bool res = false;
   string comment = "XAU PB Averaging L" + IntegerToString(current_level);

   if(pos_type == POSITION_TYPE_BUY)
      res = trade.Buy(avg_lot, trade_symbol, 0, 0, 0, comment);
   else
      res = trade.Sell(avg_lot, trade_symbol, 0, 0, 0, comment);

   if(res)
      Print("MARTINGALE AVERAGING (PULLBACK): Level ", current_level, " | Lot=", DoubleToString(avg_lot, 2),
            " | Harga=", DoubleToString(cur_price, trade_digits),
            " | Jarak dari entry terakhir=", DoubleToString(MathAbs(cur_price - last_entry) / trade_point, 0), " poin");
   else
      Print("MARTINGALE AVERAGING: Gagal buka posisi level ", current_level, " | Error: ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Fungsi bantuan: dapatkan nilai bar pertama                       |
//+------------------------------------------------------------------+
double GetCurrentHigh()  { return iHigh(trade_symbol, _Period, 0); }
double GetCurrentLow()   { return iLow(trade_symbol, _Period, 0); }
double GetCurrentClose() { return iClose(trade_symbol, _Period, 0); }
double GetCurrentOpen()  { return iOpen(trade_symbol, _Period, 0); }

//+------------------------------------------------------------------+
//| Fungsi untuk debugging: cetak nilai indikator saat klik chart    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CLICK && InpDebugLog)
     {
      Print("=== DEBUG PULLBACK BAR (", trade_symbol, ") ===");
      Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      Print("Close(1): ", DoubleToString(iClose(trade_symbol, _Period, 1), trade_digits));
      Print("EMA(1):   ", DoubleToString(ema_value[1], trade_digits));
      Print("ADX(1):   ", DoubleToString(adx_value[1], trade_digits), " (+DI: ", DoubleToString(adx_plus_di[1], 2), " -DI: ", DoubleToString(adx_minus_di[1], 2), ")");
      Print("RSI(1):   ", DoubleToString(rsi_value[1], trade_digits));
      Print("ATR(1):   ", DoubleToString(atr_value[1], trade_digits));
      Print("State:    ", EnumToString(pb_state), " | Ref=", pb_ref_price, " Target=", pb_target_price, " Cancel=", pb_cancel_price);
     }
  }
//+------------------------------------------------------------------+
