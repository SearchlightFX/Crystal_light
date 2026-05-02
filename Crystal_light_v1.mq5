//+------------------------------------------------------------------+
//|                                                   Crystal light  |
//|                                          Copyright 2026, KOKONOE |
//|                                        https://linktr.ee/kokonoe |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, KOKONOE"
#property link      "https://linktr.ee/kokonoe"
#property version   "1.0"
#property description "XAUJPY M3 confluence EA with account protection"

// Crystal_light_v1: XAUJPY M3 confluence defaults based on
// temp\XAUJPY_M3_202506261527_202605012354.csv

#include <Controls/Label.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_RESUME_MODE {
    RESUME_WEEKLY  = 0,  // weekly
    RESUME_DAILY   = 1,  // daily
    RESUME_MONTHLY = 2,  // monthly
    RESUME_NONE    = 3,  // none (permanent stop)
};

enum ENUM_START_OFF_TYPE {
    START_OFF_DAY_AFTER = 0,  // day after N days
    START_OFF_WEEKDAY   = 1,  // specific weekday
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input(name = "EA name")             string EAName            = "Crystal light";
input(name = "Magic number")        ulong  MagicNum          = 99099;
input(name = "Lots")                double DefaultLots       = 0.01;
input(name = "BUY TP value")        int    BuyTPPoints       = 1800;
input(name = "SELL TP value")       int    SellTPPoints      = 900;
input(name = "SL value (0 = no SL)") int   SLPoints         = 0;
input(name = "Time frame")          ENUM_TIMEFRAMES TimeFrame = PERIOD_M3;
input(name = "Crystal Core BUY differential")  int BuyDiff         = 300;
input(name = "Crystal Core SELL differential") int SellDiff        = 270;
input(name = "Trailing stop")       bool   UseTrailStop      = true;
input(name = "Trail Start (points profit)") int TrailStartPoints  = 1200;
input(name = "Trail Buffer (points)")       int TrailBufferPoints = 650;
input(name = "Trail Step (points profit)")  int TrailStepPoints   = 200;
input(name = "Buy orders density per candle")  int OrderDensityBuy  = 1;
input(name = "Sell orders density per candle") int OrderDensitySell = 1;
input(name = "Max multiple orders") int    MaxOrders         = 8;

input(name = "=== Auto Lot ===")    string _sep_al           = "####################";
input(name = "Auto lot ON/OFF")     bool   AutoLot           = true;
input(name = "Risk level")          double RiskLevel         = 1.2;

input(name = "=== DD-step ===")     string _sep_dd           = "####################";
input(name = "Enable DD-step multiple orders") bool dd_step_flag = true;
input(name = "DD step (%) for order change")   double  dd_step      = 6.0;
input(name = "DD step additional order limit") int  dd_cap       = 3;

input(name = "=== Target Profit ===") string _sep_tp         = "####################";
input(name = "Shutdown target profit ratio (<=1.0 = off / 1.1 = 110%)") double TargetProfitRate = 1.12;
input(name = "Resume mode (TP)")    ENUM_RESUME_MODE NupTime       = RESUME_WEEKLY;
input(name = "Resume day of week (TP)")  ENUM_DAY_OF_WEEK NupResumeDay  = WEDNESDAY;
input(name = "Resume days (TP, DAILY mode)") int NupDays = 3;

input(name = "=== Loss Cut ===")    string _sep_lc           = "####################";
input(name = "Loss of Shutdown Target (%/MAX=80)") int TargetLossPct = 28;
input(name = "Resume mode (LC)")    ENUM_RESUME_MODE LcNupTime      = RESUME_WEEKLY;
input(name = "Resume day of week (LC)") ENUM_DAY_OF_WEEK LcNupResumeDay = WEDNESDAY;
input(name = "Resume days (LC, DAILY mode)") int LcNupDays = 5;

input(name = "=== Start Off ===")   string _sep_so           = "####################";
input(name = "Start Off (delay entry start)") bool StartOff  = false;
input(name = "Start Off type")      ENUM_START_OFF_TYPE StartOff_Type = START_OFF_WEEKDAY;
input(name = "Start After Days (day after mode)") int StartAfterDays  = 3;
input(name = "Start Weekday (weekday mode)")  ENUM_DAY_OF_WEEK StartWeekday = WEDNESDAY;

input(name = "===== Margin Guard Settings =====") string mg_separator                = "####################";
input(name = "Min margin level to allow entry (%, 0=OFF)") double MinMarginLevel     = 200.0;

input(name = "=== Crystal Entry Confluence ===") string _sep_crystal = "####################";
input(name = "Crystal Momentum min BUY score (0-4)") int MomentumMinBuyScore = 2;
input(name = "Crystal Momentum BUY ATR(5) threshold (points)") double MomentumBuyAtr5Threshold = 640.0;
input(name = "Crystal Momentum BUY distance from 20-bar low (%)") double MomentumBuyDistLowPct = 0.24;
input(name = "Crystal Momentum BUY 5-bar close slope") double MomentumBuySlope5Threshold = 0.0;
input(name = "Crystal Momentum BUY volume ratio vs 20-bar avg") double MomentumBuyVolRatioThresh = 1.05;
input(name = "Crystal Reversal SELL upper wick min (points)") double ReversalSellUpperWickMinPoints = 150.0;
input(name = "Crystal Reversal SELL upper/lower wick ratio") double ReversalSellUpperWickLowerRatio = 1.0;
input(name = "Crystal Reversal block SELL fake pattern") bool ReversalBlockSellFake = true;
input(name = "Crystal Compression BUY lookback bars") int CompressionBuyLookBack = 5;
input(name = "Crystal Compression BUY range (points)") int CompressionBuyRangePoints = 2400;
input(name = "Crystal Compression BUY wick/body ratio") double CompressionBuyWickBodyRatio = 1.1;
input(name = "Crystal Swing L1 BUY differential") int SwingBuyDiffL1 = 250;
input(name = "Crystal Swing L1 SELL differential") int SwingSellDiffL1 = 230;
input(name = "Crystal Swing L2 BUY differential") int SwingBuyDiffL2 = 100;
input(name = "Crystal Swing L2 SELL differential") int SwingSellDiffL2 = 100;

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int      SymMag;
int      SymDigits         = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
double   FixedLots         = DefaultLots;
double   BuyTPValue        = (double)BuyTPPoints;
double   SellTPValue       = (double)SellTPPoints;
double   SLValue           = (double)SLPoints;
double   BuyDiffValue      = (double)BuyDiff;
double   SellDiffValue     = (double)SellDiff;
double   TargetLossValue   = (double)TargetLossPct;
int      MaxOrdersVal      = MaxOrders;
int      OrderDensityBuyVal  = OrderDensityBuy;
int      OrderDensitySellVal = OrderDensitySell;
int      TrailStartPointsVal = TrailStartPoints;
int      TrailBufferPointsVal = TrailBufferPoints;
int      TrailStepPointsVal = TrailStepPoints;
datetime NextBarTimeBuy    = TimeCurrent();
datetime NextBarTimeSell   = TimeCurrent();
bool     IsOrderStopped    = false;   // Permanent stop flag (RESUME_NONE for TP or LC)
double   InitialBalance    = 0.0;     // Balance captured at EA init (reset on resume)
ulong    CloseDeviation    = 99;
int      SlippageVal       = 30;
double   StopsLevelVal;
double   SupportLine;
double   ResistanceLine;

// Stop loss parameters (NOTE: this value is re-fetched dynamically in
// TrailingStopUpdate() and NewOrder() to stay current with broker changes)
int      StopsLevel        = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

//--- Target Profit pause state
bool     TargetProfitPaused = false;
datetime TargetProfitResume = 0;
double   TargetProfitTarget = 0.0;

//--- Loss Cut pause state
bool     LossCutPaused     = false;
datetime LossCutResume     = 0;

//--- DD-step state
int      dd_step_level     = 0;   // Current DD step level

//--- Start Off state
datetime StartOffDeadline  = 0;   // Entries blocked until this datetime

//--- UI Labels
CLabel  *InfoLabel1 = NULL;
CLabel  *InfoLabel2 = NULL;
CLabel  *InfoLabel3 = NULL;
CLabel  *InfoLabel4 = NULL;

//--- Trade objects
CTrade        Trade;
CAccountInfo  AcctInfo;
CPositionInfo PosInfo;

bool CrystalReversalSellFakePattern();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Enable only for hedge account
    if(AcctInfo.MarginMode() != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
        return (-1);

    // Capture account balance at initialization
    InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE) + AccountInfoDouble(ACCOUNT_CREDIT);

    // Validate / clamp inputs
    if(DefaultLots    <= 0)       FixedLots       = 0.01;
    if(BuyTPPoints    <= 0)       BuyTPValue      = 1800.0;
    if(SellTPPoints   <= 0)       SellTPValue     = 900.0;
    if(SLPoints       < 0)        SLValue         = 0.0;
    if(BuyDiff        <= 0)       BuyDiffValue    = 300.0;
    if(SellDiff       <= 0)       SellDiffValue   = 270.0;
    if(MaxOrders      <= 0)       MaxOrdersVal    = 8;
    if(TrailStartPoints < 0)      TrailStartPointsVal = 0;
    if(TrailBufferPoints < 0)     TrailBufferPointsVal = 0;
    if(TrailStepPoints  < 0)      TrailStepPointsVal = 0;
    if(TargetLossPct  >= 80)      TargetLossValue = 80.0;
    if(BuyTPValue     > 9999999)  BuyTPValue      = 9999999;
    if(SellTPValue    > 9999999)  SellTPValue     = 9999999;
    if(SLValue        > 9999999)  SLValue         = 9999999;
    if(BuyDiff        > 9999999)  BuyDiffValue    = 9999999;
    if(SellDiff       > 9999999)  SellDiffValue   = 9999999;
    if(MaxOrders      > 99)       MaxOrdersVal    = 99;
    if(TrailStartPointsVal > 9999999) TrailStartPointsVal = 9999999;
    if(TrailBufferPointsVal > 9999999) TrailBufferPointsVal = 9999999;
    if(TrailStepPointsVal  > 9999999) TrailStepPointsVal = 9999999;

    // Convert to price units
    BuyDiffValue  = BuyDiffValue  * _Point;
    SellDiffValue = SellDiffValue * _Point;
    BuyTPValue    = BuyTPValue    * _Point;
    SellTPValue   = SellTPValue   * _Point;
    SLValue       = SLValue       * _Point;
    StopsLevelVal = StopsLevel    * _Point;

    // Set Target Profit target
    TargetProfitTarget = (TargetProfitRate > 1.0) ? InitialBalance * TargetProfitRate : 0.0;

    // Validate lot volume
    string desc;
    if(!CheckVolumeValue(FixedLots, desc)) {
        Print("Warn:: Lot issue: ", desc, " -- reset to min lot.");
        FixedLots = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    }

    // Magnification
    ResetLastError();
    SymMag = (int)MathPow(10, SymDigits);
    int error = GetLastError();
    if(error != 0) {
        Print("Error:: MathPow error ", error);
        return (-1);
    }

    // Initialise StartOff deadline
    if(StartOff) {
        StartOffDeadline = CalcStartOffDeadline();
        Print("Info:: StartOff enabled. Entry blocked until: ",
              TimeToString(StartOffDeadline, TIME_DATE | TIME_MINUTES));
    }

    // Create UI labels
    InfoLabel1 = new CLabel();
    InfoLabel2 = new CLabel();
    InfoLabel3 = new CLabel();
    InfoLabel4 = new CLabel();

    DrawInfo();

    Trade.SetExpertMagicNumber(MagicNum);
    Trade.SetDeviationInPoints(SlippageVal);

    Print("Info:: ", EAName, " Started. MagicNum=", MagicNum,
          " InitialBalance=", DoubleToString(InitialBalance, 2),
          " AutoLot=", (AutoLot ? "ON" : "OFF"),
          " RiskLevel=", DoubleToString(RiskLevel, 2),
          " TrailStart=", TrailStartPointsVal,
          " TrailBuffer=", TrailBufferPointsVal,
          " TrailStep=", TrailStepPointsVal,
          " TP_target=", (TargetProfitRate > 1.0 ? DoubleToString(TargetProfitTarget, 2) : "OFF"),
          " NupTime=", EnumToString(NupTime),
          " LcNupTime=", EnumToString(LcNupTime),
          " dd_step_flag=", dd_step_flag,
          " StartOff=", StartOff);
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if(InfoLabel1 != NULL) { delete InfoLabel1; InfoLabel1 = NULL; }
    if(InfoLabel2 != NULL) { delete InfoLabel2; InfoLabel2 = NULL; }
    if(InfoLabel3 != NULL) { delete InfoLabel3; InfoLabel3 = NULL; }
    if(InfoLabel4 != NULL) { delete InfoLabel4; InfoLabel4 = NULL; }

    // Delete background rectangle objects
    ObjectDelete(0, "SCL_BG_Line1");
    ObjectDelete(0, "SCL_BG_Line2");
    ObjectDelete(0, "SCL_BG_Line3");
    ObjectDelete(0, "SCL_BG_Line4");

    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Draw information panel with background panels                    |
//+------------------------------------------------------------------+
void DrawInfo() {
    string c_symbol       = Symbol();
    double c_balance      = AccountInfoDouble(ACCOUNT_BALANCE);
    double c_credit       = AccountInfoDouble(ACCOUNT_CREDIT);
    double c_totalBalance = c_balance + c_credit;
    double c_equity       = AccountInfoDouble(ACCOUNT_EQUITY);
    double c_floatingLoss = c_totalBalance - c_equity;
    double pf_ls          = (c_totalBalance != 0.0)
                            ? NormalizeDouble((-c_floatingLoss / c_totalBalance) * 100.0, 1)
                            : 0.0;

    int    on_chart_spread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    string candle_time     = CandleTimer();

    //--- Line 1: Symbol / float / Spread
    string infoLine1 = "Symbol: " + c_symbol
                     + " / float: " + DoubleToString(pf_ls, 1) + "%"
                     + " / Spread: " + IntegerToString(on_chart_spread);

    //--- Line 2: Target Equity / Next candle / AutoLot
    string tp_val_str = (TargetProfitRate > 1.0)
                        ? DoubleToString(TargetProfitTarget, 2)
                        : "OFF";
    string autoLotStr = AutoLot
                        ? ("AutoLot:ON(R=" + DoubleToString(RiskLevel, 2) + ")")
                        : "AutoLot:OFF";
    string infoLine2 = "Target Equity: " + tp_val_str
                     + " / Next: " + candle_time
                     + " / " + autoLotStr;

    //--- Line 3: DD-step info
    string infoLine3 = "DD-step: " + (dd_step_flag ? "ON" : "OFF");
    if(dd_step_flag) {
        MqlDateTime serverDt;
        TimeToStruct(TimeCurrent(), serverDt);
        string serverTimeStr = StringFormat("%04d-%02d-%02dT%02d:%02d:%02d",
                                            serverDt.year, serverDt.mon, serverDt.day,
                                            serverDt.hour, serverDt.min, serverDt.sec);
        infoLine3 += " / Server time: " + serverTimeStr;
    }

    //--- Line 4: Pause / StartOff state
    string infoLine4 = "";
    if(TargetProfitPaused && TargetProfitResume > 0) {
        MqlDateTime rdt;
        TimeToStruct(TargetProfitResume, rdt);
        string resumeDate = StringFormat("%04d-%02d-%02d", rdt.year, rdt.mon, rdt.day);
        string nextTargetStr = (TargetProfitRate > 1.0)
                               ? DoubleToString(TargetProfitRate * c_equity, 2)
                               : "OFF";
        infoLine4 = "TP resume: " + resumeDate + " / Next Target: " + nextTargetStr;
    } else if(LossCutPaused && LossCutResume > 0) {
        MqlDateTime rdt;
        TimeToStruct(LossCutResume, rdt);
        string resumeDate = StringFormat("%04d-%02d-%02d", rdt.year, rdt.mon, rdt.day);
        infoLine4 = "LC resume: " + resumeDate + " (Loss Cut triggered)";
    } else if(StartOff && StartOffDeadline > TimeCurrent()) {
        MqlDateTime rdt;
        TimeToStruct(StartOffDeadline, rdt);
        string soDate = StringFormat("%04d-%02d-%02d", rdt.year, rdt.mon, rdt.day);
        infoLine4 = "StartOff: entry blocked until " + soDate;
    }

    //--- Create background rectangles for each line (semi-transparent dark grey)
    //--- Line 1 background
    if(!ObjectCreate(0, "SCL_BG_Line1", OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectDelete(0, "SCL_BG_Line1");
        ObjectCreate(0, "SCL_BG_Line1", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    }
    ObjectSetInteger(0, "SCL_BG_Line1", OBJPROP_XDISTANCE, 120);
    ObjectSetInteger(0, "SCL_BG_Line1", OBJPROP_YDISTANCE, 120);
    ObjectSetInteger(0, "SCL_BG_Line1", OBJPROP_XSIZE, 560);
    ObjectSetInteger(0, "SCL_BG_Line1", OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, "SCL_BG_Line1", OBJPROP_BGCOLOR, 0x80646464);  // clear GRAY
    ObjectSetInteger(0, "SCL_BG_Line1", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "SCL_BG_Line1", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, "SCL_BG_Line1", OBJPROP_FILL, true);
    ObjectSetInteger(0, "SCL_BG_Line1", OBJPROP_BACK, false);

    //--- Line 2 background
    if(!ObjectCreate(0, "SCL_BG_Line2", OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectDelete(0, "SCL_BG_Line2");
        ObjectCreate(0, "SCL_BG_Line2", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    }
    ObjectSetInteger(0, "SCL_BG_Line2", OBJPROP_XDISTANCE, 120);
    ObjectSetInteger(0, "SCL_BG_Line2", OBJPROP_YDISTANCE, 140);
    ObjectSetInteger(0, "SCL_BG_Line2", OBJPROP_XSIZE, 560);
    ObjectSetInteger(0, "SCL_BG_Line2", OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, "SCL_BG_Line2", OBJPROP_BGCOLOR, 0x80646464);  // clear GRAY
    ObjectSetInteger(0, "SCL_BG_Line2", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "SCL_BG_Line2", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, "SCL_BG_Line2", OBJPROP_FILL, true);
    ObjectSetInteger(0, "SCL_BG_Line2", OBJPROP_BACK, false);

    //--- Line 3 background
    if(!ObjectCreate(0, "SCL_BG_Line3", OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectDelete(0, "SCL_BG_Line3");
        ObjectCreate(0, "SCL_BG_Line3", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    }
    ObjectSetInteger(0, "SCL_BG_Line3", OBJPROP_XDISTANCE, 120);
    ObjectSetInteger(0, "SCL_BG_Line3", OBJPROP_YDISTANCE, 160);
    ObjectSetInteger(0, "SCL_BG_Line3", OBJPROP_XSIZE, 560);
    ObjectSetInteger(0, "SCL_BG_Line3", OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, "SCL_BG_Line3", OBJPROP_BGCOLOR, 0x80646464);  // clear GRAY
    ObjectSetInteger(0, "SCL_BG_Line3", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "SCL_BG_Line3", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, "SCL_BG_Line3", OBJPROP_FILL, true);
    ObjectSetInteger(0, "SCL_BG_Line3", OBJPROP_BACK, false);

    //--- Line 4 background
    if(!ObjectCreate(0, "SCL_BG_Line4", OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectDelete(0, "SCL_BG_Line4");
        ObjectCreate(0, "SCL_BG_Line4", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    }
    ObjectSetInteger(0, "SCL_BG_Line4", OBJPROP_XDISTANCE, 120);
    ObjectSetInteger(0, "SCL_BG_Line4", OBJPROP_YDISTANCE, 180);
    ObjectSetInteger(0, "SCL_BG_Line4", OBJPROP_XSIZE, 560);
    ObjectSetInteger(0, "SCL_BG_Line4", OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, "SCL_BG_Line4", OBJPROP_BGCOLOR, 0x80646464);  // clear GRAY
    ObjectSetInteger(0, "SCL_BG_Line4", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "SCL_BG_Line4", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, "SCL_BG_Line4", OBJPROP_FILL, true);
    ObjectSetInteger(0, "SCL_BG_Line4", OBJPROP_BACK, false);

    //--- Create text labels on top of background panels
    if(InfoLabel1 != NULL) {
        InfoLabel1.Create(0, "SCL_Line1", 0, 122, 120, 1200, 140);
        InfoLabel1.Color(clrYellow);
        InfoLabel1.Text(infoLine1);
    }
    if(InfoLabel2 != NULL) {
        InfoLabel2.Create(0, "SCL_Line2", 0, 122, 140, 1200, 160);
        InfoLabel2.Color(clrYellow);
        InfoLabel2.Text(infoLine2);
    }
    if(InfoLabel3 != NULL) {
        InfoLabel3.Create(0, "SCL_Line3", 0, 122, 160, 1200, 180);
        InfoLabel3.Color(clrYellow);
        InfoLabel3.Text(infoLine3);
    }
    if(InfoLabel4 != NULL) {
        InfoLabel4.Create(0, "SCL_Line4", 0, 122, 180, 1200, 200);
        InfoLabel4.Color(clrAqua);
        InfoLabel4.Text(infoLine4);
    }
}

//+------------------------------------------------------------------+
//| Crystal Core entry signal                                        |
//+------------------------------------------------------------------+
bool CrystalCoreEntrySignal(ENUM_ORDER_TYPE orderType) {
    ENUM_TIMEFRAMES tf = TimeFrame;

    double low[6];
    double high[6];
    for(int i = 0; i < 6; i++) {
        low[i]  = NormalizeDouble(iLow(_Symbol, tf, i + 1), SymDigits);
        high[i] = NormalizeDouble(iHigh(_Symbol, tf, i + 1), SymDigits);
    }

    double curRateAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double curRateBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    ENUM_TIMEFRAMES curTimeFrame = (ENUM_TIMEFRAMES)ChartPeriod();

    if(orderType == ORDER_TYPE_BUY) {
        if(curTimeFrame == PERIOD_D1 || curTimeFrame == PERIOD_W1 || curTimeFrame == PERIOD_MN1) {
            if(low[1] < low[2]) {
                if((curRateAsk - low[1]) < BuyDiffValue) return false;
                return (iLow(_Symbol, tf, 0) > iLow(_Symbol, tf, 1));
            }
        } else {
            if(low[1] < low[2] && low[2] < low[3] && low[3] < low[4]) {
                if((curRateAsk - low[1]) < BuyDiffValue) return false;
                return (iLow(_Symbol, tf, 0) > iLow(_Symbol, tf, 1));
            }
        }
    } else if(orderType == ORDER_TYPE_SELL) {
        if(curTimeFrame == PERIOD_D1 || curTimeFrame == PERIOD_W1 || curTimeFrame == PERIOD_MN1) {
            if(high[1] > high[2]) {
                if((high[1] - curRateBid) < SellDiffValue) return false;
                return (iHigh(_Symbol, tf, 0) < iHigh(_Symbol, tf, 1));
            }
        } else {
            if(high[1] > high[2] && high[2] > high[3] && high[3] > high[4]) {
                if((high[1] - curRateBid) < SellDiffValue) return false;
                return (iHigh(_Symbol, tf, 0) < iHigh(_Symbol, tf, 1));
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Crystal Momentum BUY score                                       |
//+------------------------------------------------------------------+
int CrystalMomentumBuyScore() {
    ENUM_TIMEFRAMES tf = TimeFrame;
    if(iBars(_Symbol, tf) < 25) return 0;

    double closeArr[5], highArr[5], lowArr[5];
    long   volArr[5], vol20Arr[20];
    double low20Arr[20];

    for(int j = 0; j < 5; j++) {
        int idx = j + 1;
        closeArr[j] = iClose(_Symbol, tf, idx);
        highArr[j]  = iHigh(_Symbol, tf, idx);
        lowArr[j]   = iLow(_Symbol, tf, idx);
        volArr[j]   = iVolume(_Symbol, tf, idx);
    }
    for(int j = 0; j < 20; j++) {
        int idx = j + 1;
        low20Arr[j] = iLow(_Symbol, tf, idx);
        vol20Arr[j] = iVolume(_Symbol, tf, idx);
    }

    double atr5 = 0.0;
    for(int j = 1; j < 5; j++) {
        double prevClose = iClose(_Symbol, tf, j + 1);
        double tr = MathMax(highArr[j] - lowArr[j],
                    MathMax(MathAbs(highArr[j] - prevClose),
                            MathAbs(lowArr[j] - prevClose)));
        atr5 += tr;
    }
    double atr5Pts = (atr5 / 4.0) / _Point;

    double recent20Low = low20Arr[0];
    for(int j = 1; j < 20; j++)
        if(low20Arr[j] < recent20Low) recent20Low = low20Arr[j];

    double currOpen = iOpen(_Symbol, tf, 0);
    double distFromLow = (currOpen > 0.0) ? (currOpen - recent20Low) / currOpen * 100.0 : 0.0;

    double sumX = 10.0, sumY = 0.0, sumXY = 0.0, sumX2 = 30.0;
    for(int j = 0; j < 5; j++) {
        sumY += closeArr[j];
        sumXY += j * closeArr[j];
    }
    double slope5 = (5.0 * sumXY - sumX * sumY) / (5.0 * sumX2 - sumX * sumX);

    double avgVol20 = 0.0;
    for(int j = 0; j < 20; j++) avgVol20 += (double)vol20Arr[j];
    avgVol20 /= 20.0;
    double volRatio = (avgVol20 > 0.0) ? (double)volArr[0] / avgVol20 : 1.0;

    int score = 0;
    if(atr5Pts > MomentumBuyAtr5Threshold) score++;
    if(distFromLow > MomentumBuyDistLowPct) score++;
    if(slope5 < MomentumBuySlope5Threshold) score++;
    if(volRatio > MomentumBuyVolRatioThresh) score++;
    return score;
}

//+------------------------------------------------------------------+
//| Crystal Reversal SELL pattern                                    |
//+------------------------------------------------------------------+
bool CrystalReversalSellEntryPattern() {
    ENUM_TIMEFRAMES tf = TimeFrame;
    if(iBars(_Symbol, tf) < 3) return false;

    double open2 = iOpen(_Symbol, tf, 2);
    double close2 = iClose(_Symbol, tf, 2);
    if(close2 <= open2) return false;

    double open1 = iOpen(_Symbol, tf, 1);
    double close1 = iClose(_Symbol, tf, 1);
    double high1 = iHigh(_Symbol, tf, 1);
    double low1 = iLow(_Symbol, tf, 1);
    if(close1 >= open1) return false;

    double body1 = MathAbs(open1 - close1);
    double upperWick1 = high1 - MathMax(open1, close1);
    double lowerWick1 = MathMin(open1, close1) - low1;
    if(body1 <= 0.0 || upperWick1 <= 0.0) return false;
    if((upperWick1 / _Point) < ReversalSellUpperWickMinPoints) return false;
    if(upperWick1 < lowerWick1 * ReversalSellUpperWickLowerRatio) return false;

    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(currentPrice <= 0.0) currentPrice = iOpen(_Symbol, tf, 0);
    if(currentPrice > open1) return false;
    if(currentPrice < close1) return false;

    if(ReversalBlockSellFake && CrystalReversalSellFakePattern()) return false;
    return true;
}

bool CrystalReversalSellFakePattern() {
    ENUM_TIMEFRAMES tf = TimeFrame;
    if(iBars(_Symbol, tf) < 3) return false;

    double open2 = iOpen(_Symbol, tf, 2);
    double close2 = iClose(_Symbol, tf, 2);
    double low2 = iLow(_Symbol, tf, 2);
    double open1 = iOpen(_Symbol, tf, 1);
    double close1 = iClose(_Symbol, tf, 1);
    double low1 = iLow(_Symbol, tf, 1);

    double lowerWick2 = MathMin(open2, close2) - low2;
    double lowerWick1 = MathMin(open1, close1) - low1;
    return (lowerWick2 > lowerWick1);
}

//+------------------------------------------------------------------+
//| Crystal Compression BUY pattern                                  |
//+------------------------------------------------------------------+
bool CrystalCompressionBuyEntryPattern() {
    ENUM_TIMEFRAMES tf = TimeFrame;
    int lookback = CompressionBuyLookBack;
    if(lookback < 2) lookback = 2;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, tf, 1, lookback, rates) < lookback) return false;

    double bodySize = MathAbs(rates[0].close - rates[0].open);
    double lowerWick = MathMin(rates[0].open, rates[0].close) - rates[0].low;
    double upperWick = rates[0].high - MathMax(rates[0].open, rates[0].close);

    double highestN = rates[0].high;
    double lowestN = rates[0].low;
    for(int i = 1; i < lookback; i++) {
        if(rates[i].high > highestN) highestN = rates[i].high;
        if(rates[i].low < lowestN) lowestN = rates[i].low;
    }

    double rangeN = highestN - lowestN;
    double midPoint = (highestN + lowestN) / 2.0;
    bool isHammer = lowerWick > (bodySize * CompressionBuyWickBodyRatio) && lowerWick > upperWick;
    bool isStrongClose = rates[0].close > midPoint;
    bool isConsolidation = rangeN < (CompressionBuyRangePoints * _Point);
    return (isHammer && isStrongClose && isConsolidation);
}

//+------------------------------------------------------------------+
//| Crystal Swing level signals                                      |
//+------------------------------------------------------------------+
bool CrystalSwingLevel1Signal(ENUM_ORDER_TYPE orderType) {
    ENUM_TIMEFRAMES tf = TimeFrame;
    double currentRateBuy = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double currentRateSell = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    double low[9], high[9];
    for(int i = 0; i < 9; i++) {
        low[i] = NormalizeDouble(iLow(_Symbol, tf, i + 1), SymDigits);
        high[i] = NormalizeDouble(iHigh(_Symbol, tf, i + 1), SymDigits);
    }
    double nowLow = iLow(_Symbol, tf, 0);
    double nowHigh = iHigh(_Symbol, tf, 0);

    double buyDiff = (double)SwingBuyDiffL1 * _Point;
    double sellDiff = (double)SwingSellDiffL1 * _Point;

    if(orderType == ORDER_TYPE_BUY) {
        if(tf == PERIOD_D1 || tf == PERIOD_W1 || tf == PERIOD_MN1) {
            return (low[1] < low[2] && (currentRateBuy - low[1]) > buyDiff);
        }
        return (nowLow < low[1] && low[1] < low[2] && (currentRateBuy - nowLow) > buyDiff);
    }

    if(orderType == ORDER_TYPE_SELL) {
        if(tf == PERIOD_D1 || tf == PERIOD_W1 || tf == PERIOD_MN1) {
            return (high[1] > high[2] && (high[1] - currentRateSell) > sellDiff);
        }
        return (nowHigh > high[1] && high[1] > high[2] && (nowHigh - currentRateSell) > sellDiff);
    }

    return false;
}

bool CrystalSwingLevel2Signal(ENUM_ORDER_TYPE orderType) {
    ENUM_TIMEFRAMES tf = TimeFrame;
    double low[9], high[9];
    for(int i = 0; i < 9; i++) {
        low[i] = NormalizeDouble(iLow(_Symbol, tf, i + 1), SymDigits);
        high[i] = NormalizeDouble(iHigh(_Symbol, tf, i + 1), SymDigits);
    }
    double nowLow = iLow(_Symbol, tf, 0);
    double nowHigh = iHigh(_Symbol, tf, 0);

    double buyDiff = (double)SwingBuyDiffL2 * _Point;
    double sellDiff = (double)SwingSellDiffL2 * _Point;

    if(orderType == ORDER_TYPE_BUY)
        return (low[4] < low[5] && low[5] < low[6] && low[2] < nowLow && (nowLow - low[1]) > buyDiff);

    if(orderType == ORDER_TYPE_SELL)
        return (high[4] > high[5] && high[5] > high[6] && high[2] > nowHigh && (high[1] - nowHigh) > sellDiff);

    return false;
}

//+------------------------------------------------------------------+
//| Crystal confluence gate                                          |
//+------------------------------------------------------------------+
bool CrystalEntryConfluence(ENUM_ORDER_TYPE orderType) {
    if(!CrystalCoreEntrySignal(orderType)) return false;

    if(orderType == ORDER_TYPE_BUY) {
        if(CrystalMomentumBuyScore() < MomentumMinBuyScore) return false;
    } else if(orderType == ORDER_TYPE_SELL) {
        if(!CrystalReversalSellEntryPattern()) return false;
    }

    if(orderType == ORDER_TYPE_BUY) {
        if(!CrystalCompressionBuyEntryPattern()) return false;
    }

    if(!CrystalSwingLevel1Signal(orderType) && !CrystalSwingLevel2Signal(orderType)) return false;

    return true;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    //--- Chart update
    DrawInfo();

    //--- Permanent stop
    if(IsOrderStopped) return;

    //--- Loss cut (resume check first, then trigger check)
    LossCut();

    //--- Target profit check (resume check first, then trigger check)
    CheckTargetProfit();

    //--- While paused, skip all trading
    if(TargetProfitPaused) return;
    if(LossCutPaused)      return;

    //--- Trailing stop (runs regardless of StartOff to protect open positions)
    if(PositionsTotal() > 0 && UseTrailStop)
        TrailingStopUpdate();

    //--- DD-step dynamic max orders
    if(dd_step_flag)
        DynamicMultipleOrders();

    //--- StartOff gate: block new entries until deadline passes
    if(StartOff && TimeCurrent() < StartOffDeadline)
        return;

    //--- Crystal entry confluence
    if(CrystalEntryConfluence(ORDER_TYPE_BUY))
        NewOrder(ORDER_TYPE_BUY);

    if(CrystalEntryConfluence(ORDER_TYPE_SELL))
        NewOrder(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Margin level guard: returns true if margin level is sufficient   |
//| Skips check when MinMarginLevel==0 or no positions are open.     |
//+------------------------------------------------------------------+
bool IsMarginSufficient() {
    if(MinMarginLevel <= 0.0)
        return true;
    double usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);
    // When no positions are open OR account data is not yet available,
    // margin level is undefined (treat as infinite) - allow entry.
    // This prevents false blocking on brand-new accounts where some brokers
    // may report a non-zero usedMargin before equity data is fully loaded.
    if(usedMargin <= 0.0)
        return true;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
        return true;   // equity not yet available - skip guard
    double marginLevel = (equity / usedMargin) * 100.0;
    if(marginLevel < MinMarginLevel) {
        Print("Warn:: Entry blocked - margin level too low: ",
              DoubleToString(marginLevel, 1), "% < ", DoubleToString(MinMarginLevel, 1), "%");
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Trailing Stop                                                    |
//|                                                                  |
//| Min guard distance: max(current StopsLevel, FreezeLevel, Spread) |
//| Trail distance = minGuardDist + TrailBufferPoints * _Point        |
//| Trail starts after TrailStartPoints profit                        |
//| Re-trail only after SL improves by TrailStepPoints                |
//| BUY  SL ratchets upward only  (never moves down)                 |
//| SELL SL ratchets downward only (never moves up)                  |
//| Retry: max 3 attempts with 100ms wait between retries             |
//+------------------------------------------------------------------+
void TrailingStopUpdate() {
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    if(bid <= 0.0 || ask <= 0.0) return;

    // Re-fetch broker distance constraints on every call.
    int currentStopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int currentFreezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

    // Get current spread in points (accounts for wide spreads like XAUUSD)
    int currentSpread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);

    // Use the strictest broker constraint plus a safety margin to avoid
    // "close to market" / invalid-stops failures during Market validation.
    double minGuardDist = MathMax(
        MathMax(
            (double)currentStopsLevel,
            (double)currentFreezeLevel
        ) + 5.0,
        (double)currentSpread * 2.0 + 2.0
    ) * _Point;

    // Effective trail distance: minGuardDist + user-configured buffer
    double trailDist = MathMax(
        minGuardDist * 2.0,
        minGuardDist + (double)TrailBufferPointsVal * _Point
    );
    double trailStepDist = MathMax((double)TrailStepPointsVal * _Point, _Point);

    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetSymbol(i) != Symbol()) continue;
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNum) continue;

        ENUM_POSITION_TYPE posType  = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);

        if(posType == POSITION_TYPE_BUY) {
            // Price-based profit in points (symbol-agnostic)
            double profitPts = (bid - openPrice) / _Point;
            if(profitPts < (double)TrailStartPointsVal) continue;

            // PositionModify validates TP as well. If the existing TP is already
            // too close to market, an SL-only trail update will still be rejected.
            if(currentTP > 0.0) {
                if(currentTP <= bid) continue;
                if(currentTP - bid < minGuardDist) continue;
            }

            // Candidate SL: trail below current bid by trailDist
            double newSL = NormalizeDouble(bid - trailDist, SymDigits);

            // Guard: distance from bid must satisfy minimum guard distance
            if(bid - newSL < minGuardDist) continue;

            // [Fix 2] Ratchet only upward AND enforce minimum step size.
            // Old (v7.3): newSL <= currentSL + _Point   (1-point threshold — too small)
            // New (v7.4): newSL <  currentSL + trailStep (meaningful improvement required)
            if(currentSL > 0.0 && newSL < currentSL + trailStepDist) continue;

            // [Fix 3] Redundancy guard: skip if change is smaller than 1 point
            if(MathAbs(newSL - currentSL) < _Point) continue;

            // Profit-guard: Only modify SL if new SL is above the open price (ensures profit-side SL)
            if(newSL <= openPrice) continue;

            // Retry logic (max 3 attempts with 100ms wait and price refresh between retries)
            for(int retry = 0; retry < 3; retry++) {
                // Refresh price and broker distance limits immediately before modify.
                bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
                ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
                currentStopsLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
                currentFreezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
                currentSpread      = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
                minGuardDist = MathMax(
                    MathMax(
                        (double)currentStopsLevel,
                        (double)currentFreezeLevel
                    ) + 5.0,
                    (double)currentSpread * 2.0 + 2.0
                ) * _Point;
                trailDist = MathMax(
                    minGuardDist * 2.0,
                    minGuardDist + (double)TrailBufferPointsVal * _Point
                );
                newSL = NormalizeDouble(bid - trailDist, SymDigits);

                if(bid <= 0.0 || ask <= 0.0) break;
                if(currentTP > 0.0) {
                    if(currentTP <= bid) break;
                    if(currentTP - bid < minGuardDist) break;
                }
                if(bid - newSL < minGuardDist) break;
                if(currentSL > 0.0 && newSL < currentSL + trailStepDist) break;
                if(MathAbs(newSL - currentSL) < _Point) break;
                if(newSL <= openPrice) break;

                if(Trade.PositionModify(ticket, newSL, currentTP)) {
                    Print("Info:: BUY Trail updated. ticket=", ticket,
                          " bid=", bid, " newSL=", newSL, " oldSL=", currentSL,
                          " profitPts=", profitPts, " (attempt ", retry + 1, ")");
                    break;
                } else {
                    int  err = GetLastError();
                    uint ret = Trade.ResultRetcode();

                    // Close-to-market / frozen / invalid-stops errors will not improve
                    // by immediate retries using nearly the same price, so stop here.
                    if(ret == TRADE_RETCODE_INVALID_STOPS ||
                       ret == TRADE_RETCODE_FROZEN) {
                        Print("Warn:: BUY Trail skipped due to broker distance constraint. ticket=", ticket,
                              " newSL=", newSL, " bid=", bid, " guard=", minGuardDist,
                              " err=", err, " retcode=", ret);
                        break;
                    }

                    if(retry < 2) {
                        // Wait and refresh prices before next retry
                        Sleep(100);
                        bid   = SymbolInfoDouble(Symbol(), SYMBOL_BID);
                        ask   = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
                        newSL = NormalizeDouble(bid - trailDist, SymDigits);

                        // [Fix 4] Re-apply ratchet guard after price refresh.
                        // If price moved against us, newSL may now be worse than currentSL.
                        if(currentSL > 0.0 && newSL < currentSL + trailStepDist) break;
                        if(MathAbs(newSL - currentSL) < _Point) break;
                    } else {
                        // Final attempt failed
                        Print("Error:: BUY TrailingStop modify failed after 3 attempts. ticket=", ticket,
                              " newSL=", newSL, " bid=", bid, " guard=", minGuardDist,
                              " err=", err, " retcode=", ret);
                        // [Fix 5] Check trade server retcode (ret), not MQL5 error code (err).
                        // TRADE_RETCODE_MARKET_CLOSED=10018 is a server retcode, not GetLastError() value.
                        if(ret == TRADE_RETCODE_MARKET_CLOSED) Sleep(3600000);
                    }
                }
            }

        } else if(posType == POSITION_TYPE_SELL) {
            // Price-based profit in points (symbol-agnostic)
            double profitPts = (openPrice - ask) / _Point;
            if(profitPts < (double)TrailStartPointsVal) continue;

            // PositionModify validates TP as well. If the existing TP is already
            // too close to market, an SL-only trail update will still be rejected.
            if(currentTP > 0.0) {
                if(currentTP >= ask) continue;
                if(ask - currentTP < minGuardDist) continue;
            }

            // Candidate SL: trail above current ask by trailDist
            double newSL = NormalizeDouble(ask + trailDist, SymDigits);

            // Guard: distance from ask must satisfy minimum guard distance
            if(newSL - ask < minGuardDist) continue;

            // [Fix 2] Ratchet only downward AND enforce minimum step size.
            // Old (v7.3): newSL >= currentSL - _Point   (1-point threshold — too small)
            // New (v7.4): newSL >  currentSL - trailStep (meaningful improvement required)
            if(currentSL > 0.0 && newSL > currentSL - trailStepDist) continue;

            // [Fix 3] Redundancy guard: skip if change is smaller than 1 point
            if(MathAbs(newSL - currentSL) < _Point) continue;

            // Profit-guard: Only modify SL if new SL is below the open price (ensures profit-side SL)
            if(newSL >= openPrice) continue;

            // Retry logic (max 3 attempts with 100ms wait and price refresh between retries)
            for(int retry = 0; retry < 3; retry++) {
                // Refresh price and broker distance limits immediately before modify.
                bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
                ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
                currentStopsLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
                currentFreezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
                currentSpread      = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
                minGuardDist = MathMax(
                    MathMax(
                        (double)currentStopsLevel,
                        (double)currentFreezeLevel
                    ) + 5.0,
                    (double)currentSpread * 2.0 + 2.0
                ) * _Point;
                trailDist = MathMax(
                    minGuardDist * 2.0,
                    minGuardDist + (double)TrailBufferPointsVal * _Point
                );
                newSL = NormalizeDouble(ask + trailDist, SymDigits);

                if(bid <= 0.0 || ask <= 0.0) break;
                if(currentTP > 0.0) {
                    if(currentTP >= ask) break;
                    if(ask - currentTP < minGuardDist) break;
                }
                if(newSL - ask < minGuardDist) break;
                if(currentSL > 0.0 && newSL > currentSL - trailStepDist) break;
                if(MathAbs(newSL - currentSL) < _Point) break;
                if(newSL >= openPrice) break;

                if(Trade.PositionModify(ticket, newSL, currentTP)) {
                    Print("Info:: SELL Trail updated. ticket=", ticket,
                          " ask=", ask, " newSL=", newSL, " oldSL=", currentSL,
                          " profitPts=", profitPts, " (attempt ", retry + 1, ")");
                    break;
                } else {
                    int  err = GetLastError();
                    uint ret = Trade.ResultRetcode();

                    // Close-to-market / frozen / invalid-stops errors will not improve
                    // by immediate retries using nearly the same price, so stop here.
                    if(ret == TRADE_RETCODE_INVALID_STOPS ||
                       ret == TRADE_RETCODE_FROZEN) {
                        Print("Warn:: SELL Trail skipped due to broker distance constraint. ticket=", ticket,
                              " newSL=", newSL, " ask=", ask, " guard=", minGuardDist,
                              " err=", err, " retcode=", ret);
                        break;
                    }

                    if(retry < 2) {
                        // Wait and refresh prices before next retry
                        Sleep(100);
                        bid   = SymbolInfoDouble(Symbol(), SYMBOL_BID);
                        ask   = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
                        newSL = NormalizeDouble(ask + trailDist, SymDigits);

                        // [Fix 4] Re-apply ratchet guard after price refresh.
                        // If price moved against us, newSL may now be worse than currentSL.
                        if(currentSL > 0.0 && newSL > currentSL - trailStepDist) break;
                        if(MathAbs(newSL - currentSL) < _Point) break;
                    } else {
                        // Final attempt failed
                        Print("Error:: SELL TrailingStop modify failed after 3 attempts. ticket=", ticket,
                              " newSL=", newSL, " ask=", ask, " guard=", minGuardDist,
                              " err=", err, " retcode=", ret);
                        // [Fix 5] Check trade server retcode (ret), not MQL5 error code (err).
                        if(ret == TRADE_RETCODE_MARKET_CLOSED) Sleep(3600000);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Target Profit Check                                              |
//|                                                                  |
//| When equity reaches InitialBalance * TargetProfitRate:           |
//|   RESUME_WEEKLY  : pause until nearest upcoming NupResumeDay     |
//|   RESUME_DAILY   : pause for NupDays calendar days               |
//|   RESUME_MONTHLY : pause until 1st of next month                 |
//|   RESUME_NONE    : close all and stop permanently                |
//| TargetProfitRate <= 1.0 disables this feature entirely.          |
//+------------------------------------------------------------------+
void CheckTargetProfit() {
    if(TargetProfitRate <= 1.0) return;

    if(TargetProfitPaused) {
        if(TimeCurrent() >= TargetProfitResume) {
            // Resume: reset InitialBalance and recalculate target
            InitialBalance     = AccountInfoDouble(ACCOUNT_BALANCE)
                               + AccountInfoDouble(ACCOUNT_CREDIT);
            TargetProfitTarget = InitialBalance * TargetProfitRate;
            TargetProfitPaused = false;
            TargetProfitResume = 0;
            Print("Info:: TP resumed. NewBalance=", DoubleToString(InitialBalance, 2),
                  " NewTarget=", DoubleToString(TargetProfitTarget, 2));
        }
        return;
    }

    if(AccountInfoDouble(ACCOUNT_EQUITY) >= TargetProfitTarget) {
        CloseProfitable();
        ClosePosition(ORDER_TYPE_BUY);
        ClosePosition(ORDER_TYPE_SELL);
        if(NupTime != RESUME_NONE) {
            TargetProfitPaused = true;
            TargetProfitResume = GetNextResumeTime(NupTime, NupResumeDay, NupDays);
            Print("Info:: Target profit reached (", DoubleToString(TargetProfitRate, 2),
                  "x = ", DoubleToString(TargetProfitTarget, 2),
                  "). Suspending until: ",
                  TimeToString(TargetProfitResume, TIME_DATE | TIME_MINUTES));
        } else {
            IsOrderStopped = true;
            Print("Info:: Target profit reached (", DoubleToString(TargetProfitRate, 2),
                  "x = ", DoubleToString(TargetProfitTarget, 2), "). EA stopped permanently.");
        }
    }
}

//+------------------------------------------------------------------+
//| Loss Cut                                                         |
//|                                                                  |
//| When floating loss >= TargetLossPct% of balance:                 |
//|   RESUME_WEEKLY  : pause until nearest upcoming LcNupResumeDay   |
//|   RESUME_DAILY   : pause for LcNupDays calendar days             |
//|   RESUME_MONTHLY : pause until 1st of next month                 |
//|   RESUME_NONE    : close all and stop permanently                |
//+------------------------------------------------------------------+
void LossCut() {
    //--- Resume check
    if(LossCutPaused) {
        if(TimeCurrent() >= LossCutResume) {
            LossCutPaused  = false;
            LossCutResume  = 0;
            // Reset InitialBalance and TP target on resume
            InitialBalance     = AccountInfoDouble(ACCOUNT_BALANCE)
                               + AccountInfoDouble(ACCOUNT_CREDIT);
            TargetProfitTarget = (TargetProfitRate > 1.0) ? InitialBalance * TargetProfitRate : 0.0;
            Print("Info:: LC resumed. NewBalance=", DoubleToString(InitialBalance, 2),
                  " NewTarget=", DoubleToString(TargetProfitTarget, 2));
        }
        return;
    }

    //--- Trigger check
    double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
    double credit       = AccountInfoDouble(ACCOUNT_CREDIT);
    double totalBalance = balance + credit;
    double equity       = AccountInfoDouble(ACCOUNT_EQUITY);
    double floatingLoss = totalBalance - equity;
    double lossLimit    = TargetLossValue / 100.0;

    if(totalBalance != 0.0 && floatingLoss / totalBalance >= lossLimit) {
        CloseProfitable();
        ClosePosition(ORDER_TYPE_BUY);
        ClosePosition(ORDER_TYPE_SELL);
        if(LcNupTime != RESUME_NONE) {
            LossCutPaused = true;
            LossCutResume = GetNextResumeTime(LcNupTime, LcNupResumeDay, LcNupDays);
            Print("Warn:: Loss cut triggered. Suspending until: ",
                  TimeToString(LossCutResume, TIME_DATE | TIME_MINUTES));
        } else {
            IsOrderStopped = true;
            Print("Warn:: Loss cut triggered. EA stopped permanently.");
        }
    }
}

//+------------------------------------------------------------------+
//| Get next resume datetime                                         |
//|                                                                  |
//| RESUME_WEEKLY  : nearest upcoming targetDow at 00:00.            |
//|                  If today IS targetDow, advance one full week.    |
//| RESUME_DAILY   : midnight after 'days' calendar days (min 1).    |
//| RESUME_MONTHLY : midnight of the 1st day of next month.          |
//+------------------------------------------------------------------+
datetime GetNextResumeTime(ENUM_RESUME_MODE mode, ENUM_DAY_OF_WEEK targetDow, int days = 1) {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime todayMidnight = TimeCurrent() - (dt.hour * 3600 + dt.min * 60 + dt.sec);

    if(mode == RESUME_DAILY) {
        int safeDays = (days >= 1) ? days : 1;
        return todayMidnight + (datetime)(safeDays * 86400);
    } else if(mode == RESUME_WEEKLY) {
        int dow          = dt.day_of_week;
        int targetDowInt = (int)targetDow;
        int daysUntil    = (targetDowInt - dow + 7) % 7;
        if(daysUntil == 0) daysUntil = 7;   // same day -> next week
        return todayMidnight + (datetime)(daysUntil * 86400);
    } else if(mode == RESUME_MONTHLY) {
        int nextMon  = dt.mon + 1;
        int nextYear = dt.year;
        if(nextMon > 12) { nextMon = 1; nextYear++; }
        MqlDateTime nd = {};
        nd.year = nextYear; nd.mon = nextMon; nd.day = 1;
        nd.hour = 0;        nd.min = 0;       nd.sec = 0;
        return StructToTime(nd);
    }
    // Fallback: next day
    return todayMidnight + 86400;
}

//+------------------------------------------------------------------+
//| Dynamic MaxOrders control by DD step                             |
//|                                                                  |
//| Increases MaxOrdersVal by 1 for each dd_step% drawdown drop.    |
//| Decreases MaxOrdersVal on recovery.                              |
//| Upper cap = MaxOrders (initial input value) + dd_cap.            |
//+------------------------------------------------------------------+
void DynamicMultipleOrders() {
    if(dd_step <= 0) return;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0.0) return;

    double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
    double dd_ratio   = (balance - equity) / balance * 100.0;   // DD% (positive = in loss)
    double dd_step_db = (double)dd_step;
    int    new_level  = (dd_ratio > 0.0) ? (int)MathFloor(dd_ratio / dd_step_db) : 0;

    if(new_level == dd_step_level) return;   // No change needed

    int dd_step_cap = MaxOrders + dd_cap;

    if(new_level > dd_step_level) {
        // Drawdown deepened: increase MaxOrdersVal
        int diff = new_level - dd_step_level;
        MaxOrdersVal += diff;
        if(MaxOrdersVal > dd_step_cap) MaxOrdersVal = dd_step_cap;
        dd_step_level = new_level;
        Print("Info:: DD step increased to level ", dd_step_level,
              " (DD=", DoubleToString(dd_ratio, 2), "%) -> MaxOrdersVal=", MaxOrdersVal,
              " (cap=", dd_step_cap, ")");
    } else {
        // Drawdown recovered: decrease MaxOrdersVal
        int diff = dd_step_level - new_level;
        MaxOrdersVal -= diff;
        if(MaxOrdersVal < 1) MaxOrdersVal = 1;
        dd_step_level = new_level;
        Print("Info:: DD step recovered to level ", dd_step_level,
              " (DD=", DoubleToString(dd_ratio, 2), "%) -> MaxOrdersVal=", MaxOrdersVal);
    }
}

//+------------------------------------------------------------------+
//| Calculate Start Off deadline                                     |
//|                                                                  |
//| START_OFF_DAY_AFTER : midnight after StartAfterDays days.        |
//| START_OFF_WEEKDAY   : midnight of nearest upcoming StartWeekday.  |
//|                       If today IS StartWeekday, advance one week. |
//+------------------------------------------------------------------+
datetime CalcStartOffDeadline() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime todayMidnight = TimeCurrent() - (dt.hour * 3600 + dt.min * 60 + dt.sec);

    if(StartOff_Type == START_OFF_DAY_AFTER) {
        int safeDays = (StartAfterDays >= 1) ? StartAfterDays : 1;
        return todayMidnight + (datetime)(safeDays * 86400);
    } else {   // START_OFF_WEEKDAY
        int dow          = dt.day_of_week;
        int targetDowInt = (int)StartWeekday;
        int daysUntil    = (targetDowInt - dow + 7) % 7;
        if(daysUntil == 0) daysUntil = 7;   // same day -> next week
        return todayMidnight + (datetime)(daysUntil * 86400);
    }
}

//+------------------------------------------------------------------+
//| Check open position density - BUY                                |
//+------------------------------------------------------------------+
void OpenCheckBuy() {
    bool     exact           = false;
    int      barIndex        = iBarShift(_Symbol, TimeFrame, TimeCurrent(), exact);
    datetime candleStartTime = iTime(NULL, TimeFrame, barIndex);

    datetime bar1 = iTime(NULL, TimeFrame, 1);
    datetime bar2 = iTime(NULL, TimeFrame, 2);
    int      orderCount = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetInteger(POSITION_MAGIC) == MagicNum) {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                if(openTime >= candleStartTime) orderCount++;
                if(orderCount >= OrderDensityBuyVal) {
                    NextBarTimeBuy = bar1 - bar2 + candleStartTime;
                    return;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check open position density - SELL                               |
//+------------------------------------------------------------------+
void OpenCheckSell() {
    bool     exact           = false;
    int      barIndex        = iBarShift(_Symbol, TimeFrame, TimeCurrent(), exact);
    datetime candleStartTime = iTime(NULL, TimeFrame, barIndex);

    datetime bar1 = iTime(NULL, TimeFrame, 1);
    datetime bar2 = iTime(NULL, TimeFrame, 2);
    int      orderCount = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetInteger(POSITION_MAGIC) == MagicNum) {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                if(openTime >= candleStartTime) orderCount++;
                if(orderCount >= OrderDensitySellVal) {
                    NextBarTimeSell = bar1 - bar2 + candleStartTime;
                    return;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Order density flag                                               |
//+------------------------------------------------------------------+
bool OpenCheckFlag(ENUM_ORDER_TYPE orderType) {
    if(orderType == ORDER_TYPE_BUY) {
        if(OrderDensityBuy <= 0) return (false);
        Sleep(1000);
        OpenCheckBuy();
        if(NextBarTimeBuy > TimeCurrent()) return (true);
    } else {
        if(OrderDensitySell <= 0) return (false);
        Sleep(1000);
        OpenCheckSell();
        if(NextBarTimeSell > TimeCurrent()) return (true);
    }
    return (false);
}

//+------------------------------------------------------------------+
//| Check account balance for new trade                              |
//+------------------------------------------------------------------+
bool CheckMoneyForTrade(string symb, double lots, ENUM_ORDER_TYPE type) {
    MqlTick mqltick;
    SymbolInfoTick(symb, mqltick);
    double price = (type == ORDER_TYPE_SELL) ? mqltick.bid : mqltick.ask;

    double margin, freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if(!OrderCalcMargin(type, symb, lots, price, margin)) {
        Print("Error:: Error in ", __FUNCTION__, " code=", GetLastError());
        return (false);
    }
    if(margin > freeMargin) {
        Print("Warn:: Not enough free margin for trade. Margin required: ", margin,
              " Free margin: ", freeMargin);
        return (false);
    }
    return (true);
}

//+------------------------------------------------------------------+
//| Lot volume consistency check                                     |
//+------------------------------------------------------------------+
bool CheckVolumeValue(double volume, string &description) {
    double minVol = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    if(volume < minVol) {
        description = StringFormat("Below SYMBOL_VOLUME_MIN=%.2f", minVol);
        return (false);
    }
    double maxVol = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    if(volume > maxVol) {
        description = StringFormat("Above SYMBOL_VOLUME_MAX=%.2f", maxVol);
        return (false);
    }
    double volStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    int    ratio   = (int)MathRound(volume / volStep);
    if(MathAbs(ratio * volStep - volume) > 0.0000001) {
        description = StringFormat("Not a multiple of SYMBOL_VOLUME_STEP=%.2f", volStep);
        return (false);
    }
    description = "OK";
    return (true);
}

//+------------------------------------------------------------------+
//| Get total open volume for current symbol                         |
//+------------------------------------------------------------------+
double PositionVolume(string symbol) {
    double totalVol = 0.0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetSymbol(i) != symbol) continue;
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelect(symbol))
            totalVol += PositionGetDouble(POSITION_VOLUME);
    }
    return totalVol;
}

//+------------------------------------------------------------------+
//| Get maximum allowable volume for a new order                     |
//+------------------------------------------------------------------+
double NewOrderAllowedVolume(string symbol) {
    double symMaxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double maxVol    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_LIMIT);
    if(maxVol == 0.0) maxVol = symMaxVol * 20.0;

    double openedVol = PositionVolume(symbol);
    if(openedVol < 0.0)           return 0.0;
    if(maxVol - openedVol <= 0.0) return 0.0;

    double pendingVol  = 0.0;
    int    totalOrders = OrdersTotal();
    for(int i = 0; i < totalOrders; i++) {
        ulong ticket = OrderGetTicket(i);
        if(ticket > 0 && symbol == OrderGetString(ORDER_SYMBOL))
            pendingVol += OrderGetDouble(ORDER_VOLUME_INITIAL);
    }
    return MathMin(maxVol - openedVol - pendingVol, symMaxVol);
}

//+------------------------------------------------------------------+
//| Truncate lot to minimum volume step                              |
//+------------------------------------------------------------------+
double DigiTrunc(double val) {
    double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int    digits    = (int)MathLog10(1.0 / lotStep);
    double factor    = MathPow(10, digits);
    int    truncated = (int)MathFloor(val * factor);
    return truncated * lotStep;
}

//+------------------------------------------------------------------+
//| Clamp lot to broker limits after truncation                      |
//+------------------------------------------------------------------+
double ClampLot(double lot) {
    lot = DigiTrunc(lot);
    double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    return MathMax(minVol, MathMin(lot, maxVol));
}

//+------------------------------------------------------------------+
//| Auto Lot calculation                                             |
//|                                                                  |
//| Returns FixedLots when AutoLot=false.                            |
//| When AutoLot=true, calculates base lot from free margin using    |
//| currency-specific step thresholds and RiskLevel multiplier.      |
//|                                                                  |
//| Supported margin currencies: USD, JPY, RUB, EUR.                 |
//| Falls back to FixedLots for unsupported currencies.              |
//+------------------------------------------------------------------+
double AutoLots() {
    if(!AutoLot)
        return FixedLots;

    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) {
        Print("Error:: AutoLots: Failed to get tick.");
        return FixedLots;
    }

    string marginCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    double equity         = AccountInfoDouble(ACCOUNT_EQUITY);
    double freeMargin     = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double contractSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double lot_step       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double max_volume     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    if(contractSize <= 0.0 || lot_step <= 0.0) {
        Print("Error:: AutoLots: Invalid contract size or lot step.");
        return FixedLots;
    }

    double stepStart = 0.0;
    double stepUp    = 0.0;
    if(marginCurrency == "USD") {
        stepStart = 2000.00;
        stepUp    = 3000.00;
    } else if(marginCurrency == "JPY") {
        stepStart = 300000.00;
        stepUp    = 450000.00;
    } else if(marginCurrency == "RUB") {
        stepStart = 220000.00;
        stepUp    = 440000.00;
    } else if(marginCurrency == "EUR") {
        stepStart = 1700.00;
        stepUp    = 2550.00;
    } else {
        // Unsupported currency: fall back to fixed lots
        Print("Warn:: AutoLots: Unsupported margin currency '", marginCurrency, "'. Using FixedLots.");
        return FixedLots;
    }

    double candidateLots = FixedLots;
    if(freeMargin > 0.0 && equity > stepStart && stepUp > 0.0) {
        int steps = (int)((freeMargin - stepStart) / stepUp);
        if(steps >= 0 && freeMargin > stepStart) {
            double incrementsLot   = MathMin(lot_step * (steps + 1), max_volume);
            double incrementsValue = incrementsLot * RiskLevel;
            candidateLots          = FixedLots + incrementsValue;
            if(candidateLots <= 0.0)        candidateLots = FixedLots;
            if(candidateLots >= max_volume) candidateLots = max_volume;
        }
    }

    return DigiTrunc(candidateLots);
}

//+------------------------------------------------------------------+
//| Resolve lot size for the next order                              |
//|                                                                  |
//| Returns AutoLots() when AutoLot=true, otherwise FixedLots.       |
//| Result is clamped to broker limits via ClampLot().               |
//+------------------------------------------------------------------+
double ResolveLot() {
    return ClampLot(AutoLot ? AutoLots() : FixedLots);
}

//+------------------------------------------------------------------+
//| New Order function                                               |
//+------------------------------------------------------------------+
void NewOrder(ENUM_ORDER_TYPE orderType) {
    string symbol = Symbol();
    double volume = ResolveLot();   // AutoLot-aware lot sizing
    double slPrice = 0.0;
    double tpPrice = 0.0;

    // [Fix 6] Re-fetch StopsLevel from broker before each order.
    // The global StopsLevel cached at EA init may be stale if the broker
    // updates SYMBOL_TRADE_STOPS_LEVEL during the session.
    StopsLevel    = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    StopsLevelVal = (double)StopsLevel * _Point;

    double orderableVol = NewOrderAllowedVolume(symbol);

    double curRateAsk = 0.0;
    double curRateBid = 0.0;
    int    safeCount  = 0;

    double locSLVal = SLValue;
    double tpPoint  = (orderType == ORDER_TYPE_BUY) ? BuyTPValue : SellTPValue;

    bool ocFlag = OpenCheckFlag(orderType);
    if(ocFlag) return;

    // Margin Guard Check
    if(!IsMarginSufficient())
        return;

    if(PositionsTotal() == 0) {
        if(orderType == ORDER_TYPE_BUY) {
            curRateAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            curRateBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

            if(locSLVal != 0 && locSLVal < StopsLevelVal)
                locSLVal += StopsLevelVal * 1.1;
            slPrice = curRateAsk - locSLVal;
            safeCount = 1;
            while(slPrice <= 0 && safeCount < 10) {
                locSLVal *= 0.8;
                slPrice   = curRateAsk - locSLVal;
                safeCount++;
            }
            slPrice = NormalizeDouble(slPrice, SymDigits);
            if(slPrice >= curRateAsk) slPrice *= 0.9;
            slPrice = NormalizeDouble(slPrice, SymDigits);
            if(locSLVal == 0) slPrice = 0.0;

            tpPoint = tpPoint + (StopsLevelVal * 1.1);
            tpPrice = NormalizeDouble(curRateAsk + tpPoint, SymDigits);

            if(CheckMoneyForTrade(symbol, volume, orderType)) {
                if(!Trade.Buy(volume, symbol, curRateAsk, slPrice, tpPrice, EAName)) {
                    int  err = GetLastError();
                    uint ret = Trade.ResultRetcode();
                    Print("Error:: Buy failed. err=", err, " retcode=", ret);
                    if(ret == TRADE_RETCODE_MARKET_CLOSED) Sleep(3600000);
                }
            }
        } else {
            curRateAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            curRateBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

            if(locSLVal != 0 && locSLVal < StopsLevelVal)
                locSLVal += StopsLevelVal * 1.1;
            slPrice = NormalizeDouble(curRateBid + locSLVal, SymDigits);
            if(slPrice <= curRateBid) slPrice *= 1.1;
            slPrice = NormalizeDouble(slPrice, SymDigits);
            if(locSLVal == 0) slPrice = 0.0;

            tpPoint = tpPoint + (StopsLevelVal * 1.1);
            tpPrice = curRateBid - tpPoint;
            safeCount = 1;
            while(tpPrice <= 0 && safeCount < 10) {
                tpPoint *= 0.8;
                tpPrice  = curRateBid - tpPoint;
                safeCount++;
            }
            tpPrice = NormalizeDouble(tpPrice, SymDigits);

            if(CheckMoneyForTrade(symbol, volume, orderType)) {
                if(!Trade.Sell(volume, symbol, curRateBid, slPrice, tpPrice, EAName)) {
                    int  err = GetLastError();
                    uint ret = Trade.ResultRetcode();
                    Print("Error:: Sell failed. err=", err, " retcode=", ret);
                    if(ret == TRADE_RETCODE_MARKET_CLOSED) Sleep(3600000);
                }
            }
        }
    } else {
        if(orderType == ORDER_TYPE_BUY) {
            if(orderableVol > volume) {
                if(PositionsTotal() < MaxOrdersVal) {
                    curRateAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
                    curRateBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

                    if(locSLVal != 0 && locSLVal < StopsLevelVal)
                        locSLVal += StopsLevelVal * 1.1;
                    slPrice = curRateAsk - locSLVal;
                    safeCount = 1;
                    while(slPrice <= 0 && safeCount < 10) {
                        locSLVal *= 0.8;
                        slPrice   = curRateAsk - locSLVal;
                        safeCount++;
                    }
                    slPrice = NormalizeDouble(slPrice, SymDigits);
                    if(slPrice >= curRateAsk) slPrice *= 0.9;
                    slPrice = NormalizeDouble(slPrice, SymDigits);
                    if(locSLVal == 0) slPrice = 0.0;

                    tpPoint = tpPoint + (StopsLevelVal * 1.1);
                    tpPrice = NormalizeDouble(curRateAsk + tpPoint, SymDigits);

                    if(CheckMoneyForTrade(symbol, volume, orderType)) {
                        if(!Trade.Buy(volume, symbol, curRateAsk, slPrice, tpPrice, EAName)) {
                            int  err = GetLastError();
                            uint ret = Trade.ResultRetcode();
                            Print("Error:: Buy failed. err=", err, " retcode=", ret);
                            if(ret == TRADE_RETCODE_MARKET_CLOSED) Sleep(3600000);
                        }
                    }
                }
            } else {
                Print("Warn:: BUY volume overflow. OrderableVol: ", orderableVol);
            }
        } else {
            if(orderableVol > volume) {
                if(PositionsTotal() < MaxOrdersVal) {
                    curRateAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
                    curRateBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

                    if(locSLVal != 0 && locSLVal < StopsLevelVal)
                        locSLVal += StopsLevelVal * 1.1;
                    slPrice = NormalizeDouble(curRateBid + locSLVal, SymDigits);
                    if(slPrice <= curRateBid) slPrice *= 1.1;
                    slPrice = NormalizeDouble(slPrice, SymDigits);
                    if(locSLVal == 0) slPrice = 0.0;

                    tpPoint = tpPoint + (StopsLevelVal * 1.1);
                    tpPrice = curRateBid - tpPoint;
                    safeCount = 1;
                    while(tpPrice <= 0 && safeCount < 10) {
                        tpPoint *= 0.8;
                        tpPrice  = curRateBid - tpPoint;
                        safeCount++;
                    }
                    tpPrice = NormalizeDouble(tpPrice, SymDigits);

                    if(CheckMoneyForTrade(symbol, volume, orderType)) {
                        if(!Trade.Sell(volume, symbol, curRateBid, slPrice, tpPrice, EAName)) {
                            int  err = GetLastError();
                            uint ret = Trade.ResultRetcode();
                            Print("Error:: Sell failed. err=", err, " retcode=", ret);
                            if(ret == TRADE_RETCODE_MARKET_CLOSED) Sleep(3600000);
                        }
                    }
                }
            } else {
                Print("Warn:: SELL volume overflow. OrderableVol: ", orderableVol);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close positions by order type                                    |
//+------------------------------------------------------------------+
void ClosePosition(ENUM_ORDER_TYPE orderType) {
    int   totalPos = PositionsTotal();
    ulong closingTks[];

    for(int i = 0; i < totalPos; i++) {
        string symbol = PositionGetSymbol(i);
        if(symbol != Symbol()) continue;

        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNum) continue;

        bool isBuy  = (orderType == ORDER_TYPE_BUY  && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
        bool isSell = (orderType == ORDER_TYPE_SELL && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL);
        if(!isBuy && !isSell) continue;

        ArrayResize(closingTks, ArraySize(closingTks) + 1);
        closingTks[ArraySize(closingTks) - 1] = ticket;
    }

    for(int i = 0; i < ArraySize(closingTks); i++) {
        if(closingTks[i] == 0) break;
        if(!Trade.PositionClose(closingTks[i], CloseDeviation)) {
            int  err = GetLastError();
            uint ret = Trade.ResultRetcode();
            Print("Error:: Close failed. err=", err, " retcode=", ret);
            if(err == TRADE_RETCODE_MARKET_CLOSED) Sleep(3600000);
        }
    }
}

//+------------------------------------------------------------------+
//| Close profitable positions                                       |
//+------------------------------------------------------------------+
void CloseProfitable() {
    int   totalPos = PositionsTotal();
    ulong closingTks[];

    for(int i = 0; i < totalPos; i++) {
        string symbol = PositionGetSymbol(i);
        if(symbol != Symbol()) continue;

        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNum) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetDouble(POSITION_PROFIT) <= 0.0) continue;

        ArrayResize(closingTks, ArraySize(closingTks) + 1);
        closingTks[ArraySize(closingTks) - 1] = ticket;
    }

    for(int i = 0; i < ArraySize(closingTks); i++) {
        if(closingTks[i] == 0) break;
        if(!Trade.PositionClose(closingTks[i], CloseDeviation)) {
            int  err = GetLastError();
            uint ret = Trade.ResultRetcode();
            Print("Error:: CloseProfitable failed. err=", err, " retcode=", ret);
            if(err == TRADE_RETCODE_MARKET_CLOSED) Sleep(10);
        }
    }
}

//+------------------------------------------------------------------+
//| Return remaining time of current candle as "hh:mm:ss"            |
//+------------------------------------------------------------------+
string CandleTimer() {
    ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
    bool exact        = false;
    int  bar_index    = iBarShift(_Symbol, tf, TimeCurrent(), exact);

    datetime candle_start    = iTime(_Symbol, tf, bar_index);
    int      candle_duration = PeriodSeconds();
    int      time_remaining  = (int)((candle_start + candle_duration) - TimeCurrent());
    if(time_remaining < 0) time_remaining = 0;

    return StringFormat("%02d:%02d:%02d",
                        time_remaining / 3600,
                        (time_remaining % 3600) / 60,
                        time_remaining % 60);
}

//--- End of code
