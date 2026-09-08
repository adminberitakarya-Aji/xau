//+------------------------------------------------------------------+
//|                                                  XAU_Phase1.mq5 |
//|                 Expert Advisor XAUUSD | Fase 1 & 2 - ML ONNX     |
//|   EMA + ADX + RSI + Confirmed Candle + ONNX Filter + Dashboard   |
//|   + Dynamic Martingale Recovery Engine                           |
//+------------------------------------------------------------------+
#property copyright   "XAU Phase1 & Phase2"
#property link        ""
#property version     "2.14"
#property strict
#property description "EA XAUUSD: EMA + ADX + RSI + Confirmed Candle + ONNX ML + Dashboard + Martingale + Step-Lock Trailing (Single & Basket USD)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//--- Resource model ONNX (tertanam langsung ke dalam file .ex5)
#resource "model_xau.onnx" as uchar ExtModelONNX[]

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

//===================================================================
//=== INPUT GROUP: SYMBOL & BROKER SETTINGS                        ===
//===================================================================
sinput group "===== SYMBOL & BROKER SETTINGS ====="
input string             InpCustomSymbol = "";             // Custom Symbol (kosongkan = otomatis chart, misal XAUUSD.vx)

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
input bool               InpADX_UseDI    = false;          // Gunakan filter +DI / -DI utk konfirmasi arah

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
input int                InpMagicNumber   = 20260824;      // Magic number

//===================================================================
//=== INPUT GROUP: MACHINE LEARNING / ONNX (FASE 2)                ===
//===================================================================
sinput group "===== MACHINE LEARNING / ONNX (FASE 2) ====="
input bool               InpUseMLFilter   = true;          // Aktifkan Filter Machine Learning (Node 3)
input double             InpMLMinWinProb  = 0.35;          // Min Win Probability agar order dieksekusi (0.35 - 0.65)

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
int      onnx_feature_count = 13; // Otomatis mendeteksi model 13 fitur lama atau 19 fitur baru
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
   text += "[XAU AI ENGINE v2.14 ONNX ML]\n";
   text += "====================================================\n";
   text += "- Status EA           : RUNNING [AKTIF]\n";
   text += "- Pair / Timeframe    : " + trade_symbol + " | " + EnumToString(_Period) + "\n";
   text += "- Spread Saat Ini     : " + IntegerToString(spread) + " Poin\n";
   text += "- Target SL / TP      : SL [" + sl_desc + "] | TP [" + tp_desc + "]\n";
   text += "- Jam Server          : " + TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS) + "\n";
   text += "----------------------------------------------------\n";
   text += "[STATUS INDIKATOR & PASAR]\n";
   text += "- EMA (" + IntegerToString(InpEMA_Period) + ") Trend    : " + ema_trend + "\n";
   text += "- ADX (" + IntegerToString(InpADX_Period) + ") Strength : " + adx_val_str + " [" + adx_trend + "]\n";
   text += "- Directional (+/-DI) : " + di_dir + "\n";
   text += "- RSI (" + IntegerToString(InpRSI_Period) + ") Value    : " + rsi_val_str + "\n";
   text += "- Monthly H/L (Prev)  : High=" + DoubleToString(monthly_high, trade_digits) + " | Low=" + DoubleToString(monthly_low, trade_digits) + "\n";
   text += "----------------------------------------------------\n";
   text += "[MACHINE LEARNING - ONNX NODE 3]\n";
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
      Alert("[XAU EA] Gagal memilih simbol: ", trade_symbol, ". Pastikan pair ada di Market Watch!");
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
      Alert("[XAU EA] Gagal buat handle indikator untuk pair: ", trade_symbol);
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
   
   //--- Inisialisasi model ONNX (Fase 2)
   //    Jika gagal, EA tetap BERJALAN dalam mode rule-based (ONNX bypass)
   if(InpUseMLFilter)
     {
      //--- 1. Coba load langsung dari buffer tersemat di dalam file .ex5 (#resource)
      if(ArraySize(ExtModelONNX) > 0)
        {
         handle_onnx = OnnxCreateFromBuffer(ExtModelONNX, ONNX_DEFAULT);
         if(handle_onnx != INVALID_HANDLE)
            Print("OnInit: Model ONNX berhasil dimuat langsung dari resource biner tersemat (Embedded .ex5).");
        }
      
      //--- 2. Fallback: coba load dari file fisik disk MQL5/Files/
      if(handle_onnx == INVALID_HANDLE)
         handle_onnx = OnnxCreate("model_xau.onnx", ONNX_DEFAULT);
      
      //--- 3. Fallback: coba dari subfolder Experts
      if(handle_onnx == INVALID_HANDLE)
         handle_onnx = OnnxCreate("Experts\\model_xau.onnx", ONNX_DEFAULT);
      
      if(handle_onnx == INVALID_HANDLE)
        {
         //--- EA tetap berjalan tapi ML dinonaktifkan otomatis
         last_signal_desc = "⚠️ ONNX gagal load! EA jalan tanpa filter ML";
         Print("[XAU EA] Peringatan: ONNX model tidak ditemukan (error ", GetLastError(), ").",
               " EA tetap berjalan dalam mode Rule-Based (tanpa filter ML).");
        }
      else
        {
         // Coba konfigurasi model 19 fitur baru terlebih dahulu
         const long input_shape_19[] = {1, 19};
         const long input_shape_13[] = {1, 13};
         bool shape_set = false;
         
         if(OnnxSetInputShape(handle_onnx, 0, input_shape_19))
           {
            onnx_feature_count = 19;
            shape_set = true;
            Print("OnInit: Terdeteksi model ONNX 19 fitur (dengan Market Context).");
           }
         else if(OnnxSetInputShape(handle_onnx, 0, input_shape_13))
           {
            onnx_feature_count = 13;
            shape_set = true;
            Print("OnInit: Terdeteksi model ONNX 13 fitur (Legacy).");
           }
         
         if(!shape_set)
           {
            Print("Gagal set input shape ONNX (13 maupun 19). Error: ", GetLastError());
            OnnxRelease(handle_onnx);
            handle_onnx = INVALID_HANDLE;
           }
         else
           {
            const long output_shape_label[] = {1};
            OnnxSetOutputShape(handle_onnx, 0, output_shape_label);
            const long output_shape_probs[] = {1, 2};
            OnnxSetOutputShape(handle_onnx, 1, output_shape_probs);
            last_signal_desc = "✅ ONNX Model (" + IntegerToString(onnx_feature_count) + " fitur) dimuat";
            Print("OnInit: Model ONNX berhasil dikonfigurasi dengan ", onnx_feature_count, " fitur input.");
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
   
   //--- Ambil level bulanan awal & update dashboard
   UpdateMonthlyLevels();
   UpdateDashboard();
   
   Print("OnInit: EA XAUUSD v2.14 AKTIF | Symbol=", trade_symbol,
         " | Digits=", trade_digits, " | Point=", DoubleToString(trade_point, 8),
         " | Martingale=", (InpUseMartingale ? "ON" : "OFF"),
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
   
   Print("OnDeinit: EA dihentikan, reason=", reason);
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
   
   //--- Deteksi sinyal entry (loop/graph engine pada bar baru)
   CheckForSignal();
   
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
      Print("NODE 3 (ML ONNX): Sinyal Type=", signal_type, " -> Predicted Win Prob=", DoubleToString(win_prob * 100.0, 1), "%");
   
   return(win_prob);
  }

//+------------------------------------------------------------------+
//| Deteksi sinyal entry berdasarkan pipeline (loop/graph engine)    |
//+------------------------------------------------------------------+
void CheckForSignal()
  {
   //--- Hindari sinyal berulang pada bar yang sama (eksekusi pada pembukaan bar baru)
   datetime bar_time = iTime(trade_symbol, _Period, 0);
   if(bar_time == last_bar_time) return;
   last_bar_time = bar_time;
   
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
         last_signal_desc = "FOLLOW BUY (Trend Bullish)";
         if(InpDebugLog) Print("NODE 1: FOLLOW BUY triggered");
        }
      
      // FOLLOW SELL: harga di bawah EMA, ADX kuat + -DI > +DI, RSI tidak oversold
      if(close1 < ema1 && adx1 >= InpADX_Strength && adx_sell_dir && rsi1 > InpRSI_Oversold)
        {
         follow_sell = true;
         last_signal_desc = "FOLLOW SELL (Trend Bearish)";
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
   //=== NODE 4: Keputusan akhir masuk posisi                      ===
   //=================================================================
   if(!do_buy && !do_sell) return; // tidak ada sinyal
   
   //--- Pastikan posisi belum melebihi batas (khusus simbol dan magic number EA ini)
   int total_positions = CountOpenPositions();
   if(total_positions >= InpMaxOpenPositions)
     {
      if(InpDebugLog) Print("Maks posisi tercapai (", total_positions, ")");
      return;
     }
   
   //--- Eksekusi order
   if(do_buy && InpIsBuyAllowed)   OpenPosition(ORDER_TYPE_BUY);
   if(do_sell && InpIsSellAllowed) OpenPosition(ORDER_TYPE_SELL);
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
      res = trade.Buy(lot, trade_symbol, price, sl, tp, "XAU Phase1+2 BUY");
   else if(type == ORDER_TYPE_SELL)
      res = trade.Sell(lot, trade_symbol, price, sl, tp, "XAU Phase1+2 SELL");
   
   if(!res)
     {
      Print("Gagal membuka posisi: ", trade.ResultRetcodeDescription());
      return;
     }
   
   if(InpDebugLog)
     {
      string type_str = (type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
      Print("Posisi ", type_str, " terbuka: lot=", DoubleToString(lot, 2),
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
      long stop_level    = SymbolInfoInteger(trade_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double min_sl_dist = (double)stop_level * trade_point;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!pos_info.SelectByIndex(i)) continue;
         if(pos_info.Symbol() != trade_symbol || pos_info.Magic() != InpMagicNumber) continue;

         double pos_open = pos_info.PriceOpen();
         double pos_sl   = pos_info.StopLoss();
         ulong  ticket   = pos_info.Ticket();

         if(pos_info.PositionType() == POSITION_TYPE_BUY)
           {
            double bid = SymbolInfoDouble(trade_symbol, SYMBOL_BID);
            double profit_pts = (bid - pos_open) / trade_point;

            // Aktifkan trailing hanya saat profit sudah mencapai start points
            if(profit_pts >= InpTrailingStartPts)
              {
               if(InpTrailingMode == TRAIL_STEP_LOCK)
                 {
                  double excess_pts = profit_pts - InpTrailingStartPts;
                  int steps = (InpTrailingStepPoints > 0) ? (int)MathFloor(excess_pts / InpTrailingStepPoints) : 0;
                  double target_lock_pts = InpTrailingLockPts + (steps * InpTrailingMovePoints);
                  double new_sl = NormalizeDouble(pos_open + (target_lock_pts * trade_point), trade_digits);

                  // Pastikan SL baru lebih tinggi dari SL lama & memenuhi STOPS_LEVEL
                  if(new_sl > pos_sl && (bid - new_sl) >= min_sl_dist)
                    {
                     if(trade.PositionModify(ticket, new_sl, pos_info.TakeProfit()))
                       {
                        if(InpDebugLog) Print("STEP-LOCK TRAILING BUY: SL naik ke ", DoubleToString(new_sl, trade_digits),
                                             " (Locked: +", DoubleToString(target_lock_pts, 0), " pts | Step: ", steps,
                                             ") | Bid=", DoubleToString(bid, trade_digits));
                       }
                    }
                 }
               else // TRAIL_CLASSIC
                 {
                  double trail_dist = InpTrailingDistPts * trade_point;
                  double trail_step = InpTrailingStepPts * trade_point;
                  double new_sl = NormalizeDouble(bid - trail_dist, trade_digits);
                  if(new_sl > pos_sl + trail_step && (bid - new_sl) >= min_sl_dist)
                    {
                     if(trade.PositionModify(ticket, new_sl, pos_info.TakeProfit()))
                       {
                        if(InpDebugLog) Print("CLASSIC TRAILING BUY: SL naik ke ", DoubleToString(new_sl, trade_digits),
                                             " | Bid=", DoubleToString(bid, trade_digits));
                       }
                    }
                 }
              }
           }
         else if(pos_info.PositionType() == POSITION_TYPE_SELL)
           {
            double ask = SymbolInfoDouble(trade_symbol, SYMBOL_ASK);
            double profit_pts = (pos_open - ask) / trade_point;

            if(profit_pts >= InpTrailingStartPts)
              {
               if(InpTrailingMode == TRAIL_STEP_LOCK)
                 {
                  double excess_pts = profit_pts - InpTrailingStartPts;
                  int steps = (InpTrailingStepPoints > 0) ? (int)MathFloor(excess_pts / InpTrailingStepPoints) : 0;
                  double target_lock_pts = InpTrailingLockPts + (steps * InpTrailingMovePoints);
                  double new_sl = NormalizeDouble(pos_open - (target_lock_pts * trade_point), trade_digits);

                  // Pastikan SL baru lebih rendah dari SL lama (atau belum ada SL) & memenuhi STOPS_LEVEL
                  if((pos_sl == 0 || new_sl < pos_sl) && (new_sl - ask) >= min_sl_dist)
                    {
                     if(trade.PositionModify(ticket, new_sl, pos_info.TakeProfit()))
                       {
                        if(InpDebugLog) Print("STEP-LOCK TRAILING SELL: SL turun ke ", DoubleToString(new_sl, trade_digits),
                                             " (Locked: +", DoubleToString(target_lock_pts, 0), " pts | Step: ", steps,
                                             ") | Ask=", DoubleToString(ask, trade_digits));
                       }
                    }
                 }
               else // TRAIL_CLASSIC
                 {
                  double trail_dist = InpTrailingDistPts * trade_point;
                  double trail_step = InpTrailingStepPts * trade_point;
                  double new_sl = NormalizeDouble(ask + trail_dist, trade_digits);
                  if((pos_sl == 0 || new_sl < pos_sl - trail_step) && (new_sl - ask) >= min_sl_dist)
                    {
                     if(trade.PositionModify(ticket, new_sl, pos_info.TakeProfit()))
                       {
                        if(InpDebugLog) Print("CLASSIC TRAILING SELL: SL turun ke ", DoubleToString(new_sl, trade_digits),
                                             " | Ask=", DoubleToString(ask, trade_digits));
                       }
                    }
                 }
              }
           }
        }
     }

   //=================================================================
   //=== BAGIAN 3: Martingale Averaging Recovery Engine            ===
   //=================================================================
   if(!InpUseMartingale) return;

   //--- 3a. Basket Trailing Profit Step-Lock berbasis USD (martingale group)
   if(InpUseBasketTrailing)
     {
      //--- Fase 1: Cek apakah floating profit mencapai Start → aktifkan trailing
      if(total_float >= InpBasketTrailStartUSD)
        {
         if(!basket_trailing_active)
           {
            basket_trailing_active = true;
            basket_max_profit      = total_float;
            // Hitung lock level awal (step 0)
            double init_lock = InpBasketTrailLockUSD;
            Print("BASKET STEP-LOCK: Aktif! Floating +$", DoubleToString(total_float, 2),
                  " >= Start $", DoubleToString(InpBasketTrailStartUSD, 2),
                  " → Lock awal dikunci di +$", DoubleToString(init_lock, 2));
           }
         else if(total_float > basket_max_profit)
           {
            basket_max_profit = total_float;
            // Hitung berapa milestone/step yang sudah dicapai
            double b_excess = basket_max_profit - InpBasketTrailStartUSD;
            int    b_steps  = (InpBasketTrailStepUSD > 0) ? (int)MathFloor(b_excess / InpBasketTrailStepUSD) : 0;
            double b_lock   = InpBasketTrailLockUSD + (b_steps * InpBasketTrailMoveUSD);
            if(InpDebugLog) Print("BASKET STEP-LOCK: Peak naik → +$", DoubleToString(basket_max_profit, 2),
                                  " | Step ke-", b_steps,
                                  " | Lock dinaikkan ke +$", DoubleToString(b_lock, 2));
           }
        }

      //--- Fase 2: Eksekusi exit jika floating profit turun menyentuh atau di bawah nilai lock saat ini
      if(basket_trailing_active)
        {
         double b_excess    = basket_max_profit - InpBasketTrailStartUSD;
         int    b_steps     = (InpBasketTrailStepUSD > 0) ? (int)MathFloor(b_excess / InpBasketTrailStepUSD) : 0;
         double b_lock_now  = InpBasketTrailLockUSD + (b_steps * InpBasketTrailMoveUSD);

         if(total_float <= b_lock_now)
           {
            Print("BASKET STEP-LOCK EXIT: Floating +$", DoubleToString(total_float, 2),
                  " <= Lock +$", DoubleToString(b_lock_now, 2),
                  " (Peak: +$", DoubleToString(basket_max_profit, 2),
                  " | Step ke-", b_steps, ") → Tutup semua ", current_level, " posisi");
            basket_trailing_active = false;
            basket_max_profit      = 0.0;
            CloseAllPositions();
            return;
           }
        }
     }

   //--- 3b. Fallback: Instant close saat profit target poin tercapai (jika basket trailing off)
   if(!InpUseBasketTrailing)
     {
      double tick_value   = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size    = SymbolInfoDouble(trade_symbol, SYMBOL_TRADE_TICK_SIZE);
      double target_money = InpMartingaleProfitPts * tick_value *
                            (tick_size > 0 ? (trade_point / tick_size) : 1.0);
      if(total_float >= target_money && current_level > 1)
        {
         Print("MARTINGALE RECOVERY: Total floating profit $", DoubleToString(total_float, 2),
               " >= target $", DoubleToString(target_money, 2), " → Tutup semua ", current_level, " posisi");
         CloseAllPositions();
         return;
        }
     }

   //--- 3c. Cek apakah sudah mencapai max level averaging
   if(current_level > InpMaxMartingaleStep)
     {
      if(InpDebugLog) Print("MARTINGALE: Level max (", InpMaxMartingaleStep, ") sudah tercapai, tidak tambah posisi lagi");
      return;
     }

   //--- 3d. Ambil info posisi pertama dan terakhir yang terbuka
   ENUM_POSITION_TYPE pos_type;
   double first_entry = 0.0;
   double last_entry  = 0.0;
   if(!GetFirstPosition(pos_type, first_entry, last_entry)) return;

   double cur_price = (pos_type == POSITION_TYPE_BUY) ?
                      SymbolInfoDouble(trade_symbol, SYMBOL_BID) :
                      SymbolInfoDouble(trade_symbol, SYMBOL_ASK);

   //--- 3e. Hitung jarak averaging (ATR atau Fixed)
   double dist_pts = 0.0;
   if(InpMartiDistMode == MARTI_DIST_ATR)
     {
      double cur_atr = (ArraySize(atr_value) > 1 && atr_value[1] > 0) ?
                       atr_value[1] : (InpMartingaleDistPts * trade_point);
      dist_pts = cur_atr * InpMartiATR_Mult;
      if(InpDebugLog) Print("MARTINGALE ATR DIST: ATR=", DoubleToString(cur_atr / trade_point, 0),
                            " pts | Mult=", InpMartiATR_Mult, " | Jarak=", DoubleToString(dist_pts / trade_point, 0), " pts");
     }
   else
      dist_pts = InpMartingaleDistPts * trade_point;

   //--- 3f. Cek apakah harga sudah bergerak cukup BERLAWANAN arah dari entry terakhir
   bool should_average = false;
   if(pos_type == POSITION_TYPE_BUY && cur_price <= last_entry - dist_pts)
      should_average = true;  // Harga turun X poin dari entry terakhir → averaging BUY lagi
   else if(pos_type == POSITION_TYPE_SELL && cur_price >= last_entry + dist_pts)
      should_average = true;  // Harga naik X poin dari entry terakhir → averaging SELL lagi

   if(!should_average) return;

   //--- 3g. Hitung lot untuk posisi averaging (lot dasar × multiplier^level)
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

   //--- Buka posisi averaging tanpa SL/TP (ditutup oleh basket trailing / profit target)
   bool res = false;
   string comment = "XAU Averaging L" + IntegerToString(current_level);

   if(pos_type == POSITION_TYPE_BUY)
      res = trade.Buy(avg_lot, trade_symbol, 0, 0, 0, comment);
   else
      res = trade.Sell(avg_lot, trade_symbol, 0, 0, 0, comment);

   if(res)
      Print("MARTINGALE AVERAGING: Level ", current_level, " | Lot=", DoubleToString(avg_lot, 2),
            " | Harga=", DoubleToString(cur_price, trade_digits),
            " | Jarak dari entry terakhir=", DoubleToString(MathAbs(cur_price - last_entry) / trade_point, 0), " poin",
            " | Mode Grid: ", (InpMartiDistMode == MARTI_DIST_ATR ? "ATR" : "Fixed"),
            " | Grid dist=", DoubleToString(dist_pts / trade_point, 0), " pts");
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
      Print("=== DEBUG BAR (", trade_symbol, ") ===");
      Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      Print("Close(1): ", DoubleToString(iClose(trade_symbol, _Period, 1), trade_digits));
      Print("EMA(1):   ", DoubleToString(ema_value[1], trade_digits));
      Print("ADX(1):   ", DoubleToString(adx_value[1], trade_digits), " (+DI: ", DoubleToString(adx_plus_di[1], 2), " -DI: ", DoubleToString(adx_minus_di[1], 2), ")");
      Print("RSI(1):   ", DoubleToString(rsi_value[1], trade_digits));
      Print("ATR(1):   ", DoubleToString(atr_value[1], trade_digits));
      Print("Prev Month H/L: ", DoubleToString(monthly_high, trade_digits), " / ", DoubleToString(monthly_low, trade_digits));
     }
  }
//+------------------------------------------------------------------+
