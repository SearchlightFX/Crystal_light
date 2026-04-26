//+------------------------------------------------------------------+
//|                                                    Crystal light |
//|                                          Copyright 2026, KOKONOE |
//|                                        https://linktr.ee/kokonoe |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, KOKONOE"
#property link      "https://linktr.ee/kokonoe"
#property version   "2.0"
#property description "ETHUSD dedicated MT5 EA with trend-pullback entries and account protection."
#property strict

#include <Controls/Label.mqh>
#include <Trade/Trade.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

enum ENUM_RESUME_MODE {
    RESUME_WEEKLY  = 0,
    RESUME_DAILY   = 1,
    RESUME_MONTHLY = 2,
    RESUME_NONE    = 3
};

enum ENUM_START_OFF_TYPE {
    START_OFF_DAY_AFTER = 0,
    START_OFF_WEEKDAY   = 1
};

input(name = "EA name")                     string EAName             = "Crystal light";
input(name = "Magic number")               ulong  MagicNum           = 26042601;
input(name = "Signal time frame")          ENUM_TIMEFRAMES SignalTF  = PERIOD_M15;
input(name = "Enable BUY")                 bool   EnableBuy          = true;
input(name = "Enable SELL")                bool   EnableSell         = true;
input(name = "Default lots")               double DefaultLots        = 0.01;
input(name = "Max total positions")        int    MaxTotalPositions  = 1;
input(name = "One position only per symbol side") bool OnePerSide    = true;

input(name = "=== Strategy ===")           string _sep_strategy      = "####################";
input(name = "Fast EMA period")            int    FastEMAPeriod      = 8;
input(name = "Trend EMA period")           int    TrendEMAPeriod     = 21;
input(name = "Slow EMA period")            int    SlowEMAPeriod      = 55;
input(name = "ATR period")                 int    ATRPeriod          = 14;
input(name = "RSI period")                 int    RSIPeriod          = 14;
input(name = "Spread filter max points")   int    MaxSpreadPoints    = 750;
input(name = "Min ATR points")             int    MinATRPoints       = 1000;
input(name = "Trend slope bars")           int    TrendSlopeBars     = 2;
input(name = "Pending expiration bars")    int    PendingExpiryBars  = 2;
input(name = "Use limit entries")          bool   UseLimitEntries    = true;
input(name = "Fallback to market if limit invalid") bool FallbackMarket = false;

input(name = "BUY breakout ATR multiple")  double BuyBreakoutATR     = 1.20;
input(name = "BUY minimum RSI")            double BuyMinRSI          = 75.0;
input(name = "BUY pullback ATR for limit") double BuyPullbackATR     = 0.20;
input(name = "BUY initial SL ATR")         double BuyInitialSLATR    = 2.40;
input(name = "BUY time exit bars")         int    BuyTimeExitBars    = 24;

input(name = "SELL breakdown ATR multiple") double SellBreakoutATR   = 1.40;
input(name = "SELL maximum RSI")            double SellMaxRSI        = 20.0;
input(name = "SELL rebound ATR for limit")  double SellPullbackATR   = 0.10;
input(name = "SELL initial SL ATR")         double SellInitialSLATR  = 2.00;
input(name = "SELL time exit bars")         int    SellTimeExitBars  = 12;

input(name = "=== Trailing ===")           string _sep_trail         = "####################";
input(name = "Use ATR trailing")           bool   UseATRTrailing     = true;
input(name = "Trail start ATR")            double TrailStartATR      = 1.20;
input(name = "Trail distance ATR")         double TrailDistanceATR   = 1.40;
input(name = "Min SL advance points")      int    TrailStepPoints    = 500;

input(name = "=== Auto Lot ===")           string _sep_al            = "####################";
input(name = "Auto lot ON/OFF")            bool   AutoLot            = false;
input(name = "Auto lot risk % per trade")  double AutoLotRiskPct     = 0.40;
input(name = "Risk level multiplier")      double RiskLevel          = 1.00;

input(name = "=== Target Profit ===")      string _sep_tp            = "####################";
input(name = "Shutdown target profit ratio (<=1.0 = off)") double TargetProfitRate = 1.12;
input(name = "Resume mode (TP)")           ENUM_RESUME_MODE NupTime  = RESUME_WEEKLY;
input(name = "Resume day of week (TP)")    ENUM_DAY_OF_WEEK NupResumeDay = MONDAY;
input(name = "Resume days (TP, DAILY mode)") int NupDays             = 3;

input(name = "=== Loss Cut ===")           string _sep_lc            = "####################";
input(name = "Loss of Shutdown Target (%/MAX=80)") int TargetLossPct = 18;
input(name = "Resume mode (LC)")           ENUM_RESUME_MODE LcNupTime = RESUME_WEEKLY;
input(name = "Resume day of week (LC)")    ENUM_DAY_OF_WEEK LcNupResumeDay = MONDAY;
input(name = "Resume days (LC, DAILY mode)") int LcNupDays           = 5;

input(name = "=== Start Off ===")          string _sep_so            = "####################";
input(name = "Start Off (delay entry start)") bool StartOff          = false;
input(name = "Start Off type")             ENUM_START_OFF_TYPE StartOffType = START_OFF_WEEKDAY;
input(name = "Start After Days")           int    StartAfterDays     = 3;
input(name = "Start Weekday")              ENUM_DAY_OF_WEEK StartWeekday = MONDAY;

input(name = "=== Margin Guard ===")       string _sep_mg            = "####################";
input(name = "Min margin level to allow entry (%, 0=OFF)") double MinMarginLevel = 250.0;

int      SymDigits           = 0;
double   PointValue          = 0.0;
int      FastEMAPeriodVal    = 8;
int      TrendEMAPeriodVal   = 21;
int      SlowEMAPeriodVal    = 55;
int      ATRPeriodVal        = 14;
int      RSIPeriodVal        = 14;
int      PendingExpiryBarsVal= 2;
int      BuyTimeExitBarsVal  = 24;
int      SellTimeExitBarsVal = 12;
int      TargetLossPctVal    = 18;
double   InitialBalance      = 0.0;
double   TargetProfitTarget  = 0.0;
bool     TargetProfitPaused  = false;
datetime TargetProfitResume  = 0;
bool     LossCutPaused       = false;
datetime LossCutResume       = 0;
bool     IsOrderStopped      = false;
datetime StartOffDeadline    = 0;
datetime LastSignalBarTime   = 0;

int HandleFastEMA  = INVALID_HANDLE;
int HandleTrendEMA = INVALID_HANDLE;
int HandleSlowEMA  = INVALID_HANDLE;
int HandleATR      = INVALID_HANDLE;
int HandleRSI      = INVALID_HANDLE;

CTrade        Trade;
CAccountInfo  Account;
CPositionInfo PositionInfo;
COrderInfo    OrderInfo;

CLabel *InfoLabel1 = NULL;
CLabel *InfoLabel2 = NULL;
CLabel *InfoLabel3 = NULL;
CLabel *InfoLabel4 = NULL;

struct SignalSnapshot {
    datetime closedBarTime;
    double   close1;
    double   high1;
    double   low1;
    double   high2;
    double   low2;
    double   emaFast1;
    double   emaTrend1;
    double   emaTrendSlopeRef;
    double   emaSlow1;
    double   atr1;
    double   rsi1;
};

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
string StatePrefix()
{
   // Since AccountInfoInteger can return a 64-bit integer, use %I64d.
   return StringFormat("CL.%I64d.%d.%s.", AccountInfoInteger(ACCOUNT_LOGIN), MagicNum, _Symbol);
}



double Clamp(double value, double minValue, double maxValue) {
    if(value < minValue) return minValue;
    if(value > maxValue) return maxValue;
    return value;
}

double NormalizeVolume(double volume) {
    double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int    stepDigits = 2;

    if(step <= 0.0) step = 0.01;
    if(step < 1.0)
        stepDigits = (int)MathRound(-MathLog10(step));
    volume = Clamp(volume, minVolume, maxVolume);
    volume = MathFloor(volume / step) * step;
    return NormalizeDouble(volume, stepDigits);
}

double GetMinStopDistance() {
    double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * PointValue;
    double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * PointValue;
    double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * PointValue;
    return MathMax(MathMax(stops, freeze), spread + (3.0 * PointValue));
}

bool CheckVolumeValue(double volume, string &description) {
    double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if(volume < minVolume) {
        description = StringFormat("Below SYMBOL_VOLUME_MIN %.2f", minVolume);
        return false;
    }

    double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if(volume > maxVolume) {
        description = StringFormat("Above SYMBOL_VOLUME_MAX %.2f", maxVolume);
        return false;
    }

    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if(step <= 0.0) step = 0.01;
    int ratio = (int)MathRound(volume / step);
    if(MathAbs(ratio * step - volume) > 0.0000001) {
        description = StringFormat("Not a SYMBOL_VOLUME_STEP multiple %.2f", step);
        return false;
    }

    description = "OK";
    return true;
}

bool CheckMoneyForTrade(string symbol, double lots, ENUM_ORDER_TYPE type, double price) {
    double margin      = 0.0;
    double freeMargin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if(!OrderCalcMargin(type, symbol, lots, price, margin)) {
        Print("Error:: OrderCalcMargin failed. code=", GetLastError());
        return false;
    }

    if(margin > freeMargin) {
        Print("Warn:: Not enough free margin. required=", DoubleToString(margin, 2),
              " free=", DoubleToString(freeMargin, 2));
        return false;
    }

    return true;
}

bool IsMarginSufficient() {
    if(MinMarginLevel <= 0.0) return true;

    double usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);
    if(usedMargin <= 0.0) return true;

    double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
    double marginLevel = (equity / usedMargin) * 100.0;
    if(marginLevel < MinMarginLevel) {
        Print("Warn:: Margin guard blocked entry. level=",
              DoubleToString(marginLevel, 1), " min=", DoubleToString(MinMarginLevel, 1));
        return false;
    }
    return true;
}

double GetIndicatorValue(int handle, int shift) {
    double value[1];
    if(handle == INVALID_HANDLE) return 0.0;
    if(CopyBuffer(handle, 0, shift, 1, value) != 1) return 0.0;
    return value[0];
}

bool BuildSignalSnapshot(SignalSnapshot &snap) {
    snap.closedBarTime   = iTime(_Symbol, SignalTF, 1);
    snap.close1          = iClose(_Symbol, SignalTF, 1);
    snap.high1           = iHigh(_Symbol, SignalTF, 1);
    snap.low1            = iLow(_Symbol, SignalTF, 1);
    snap.high2           = iHigh(_Symbol, SignalTF, 2);
    snap.low2            = iLow(_Symbol, SignalTF, 2);
    snap.emaFast1        = GetIndicatorValue(HandleFastEMA, 1);
    snap.emaTrend1       = GetIndicatorValue(HandleTrendEMA, 1);
    snap.emaTrendSlopeRef= GetIndicatorValue(HandleTrendEMA, 1 + TrendSlopeBars);
    snap.emaSlow1        = GetIndicatorValue(HandleSlowEMA, 1);
    snap.atr1            = GetIndicatorValue(HandleATR, 1);
    snap.rsi1            = GetIndicatorValue(HandleRSI, 1);

    if(snap.closedBarTime <= 0) return false;
    if(snap.close1 == 0.0 || snap.atr1 <= 0.0) return false;
    return true;
}

bool IsNewSignalBar() {
    datetime currentBarTime = iTime(_Symbol, SignalTF, 0);
    if(currentBarTime <= 0) return false;
    if(currentBarTime == LastSignalBarTime) return false;
    LastSignalBarTime = currentBarTime;
    return true;
}

//+------------------------------------------------------------------+
//| State persistence                                                |
//+------------------------------------------------------------------+
void SaveState() {
    string prefix = StatePrefix();
    GlobalVariableSet(prefix + "InitialBalance", InitialBalance);
    GlobalVariableSet(prefix + "TargetProfitTarget", TargetProfitTarget);
    GlobalVariableSet(prefix + "TargetProfitPaused", TargetProfitPaused ? 1.0 : 0.0);
    GlobalVariableSet(prefix + "TargetProfitResume", (double)TargetProfitResume);
    GlobalVariableSet(prefix + "LossCutPaused", LossCutPaused ? 1.0 : 0.0);
    GlobalVariableSet(prefix + "LossCutResume", (double)LossCutResume);
    GlobalVariableSet(prefix + "IsOrderStopped", IsOrderStopped ? 1.0 : 0.0);
    GlobalVariableSet(prefix + "StartOffDeadline", (double)StartOffDeadline);
}

double LoadStateValue(string key, double defaultValue) {
    if(GlobalVariableCheck(key))
        return GlobalVariableGet(key);
    return defaultValue;
}

void LoadState() {
    string prefix = StatePrefix();
    InitialBalance     = LoadStateValue(prefix + "InitialBalance", InitialBalance);
    TargetProfitTarget = LoadStateValue(prefix + "TargetProfitTarget", TargetProfitTarget);
    TargetProfitPaused = (LoadStateValue(prefix + "TargetProfitPaused", 0.0) > 0.5);
    TargetProfitResume = (datetime)LoadStateValue(prefix + "TargetProfitResume", 0.0);
    LossCutPaused      = (LoadStateValue(prefix + "LossCutPaused", 0.0) > 0.5);
    LossCutResume      = (datetime)LoadStateValue(prefix + "LossCutResume", 0.0);
    IsOrderStopped     = (LoadStateValue(prefix + "IsOrderStopped", 0.0) > 0.5);
    StartOffDeadline   = (datetime)LoadStateValue(prefix + "StartOffDeadline", 0.0);
}

//+------------------------------------------------------------------+
//| UI                                                               |
//+------------------------------------------------------------------+
void CreateLabel(CLabel *&label, string name, int y, color textColor) {
    if(label == NULL)
        label = new CLabel();

    if(label != NULL && ObjectFind(0, name) < 0) {
        if(!label.Create(0, name, 0, 10, y, 1400, y + 18))
            Print("Warn:: Failed to create label ", name);
    }

    if(label != NULL)
        label.Color(textColor);
}

void DrawInfo() {
    double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity       = AccountInfoDouble(ACCOUNT_EQUITY);
    double floatingPnL  = equity - balance;
    int spreadPoints    = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

    string line1 = "Symbol: " + _Symbol
                 + " / TF: " + EnumToString(SignalTF)
                 + " / Spread: " + IntegerToString(spreadPoints)
                 + " / Float: " + DoubleToString(floatingPnL, 2);

    string line2 = EAName
                 + " / Magic: " + IntegerToString((int)MagicNum)
                 + " / AutoLot: " + (AutoLot ? "ON" : "OFF")
                 + " / Equity: " + DoubleToString(equity, 2);

    string tpState = (TargetProfitRate > 1.0)
                   ? DoubleToString(TargetProfitTarget, 2)
                   : "OFF";
    string line3 = "InitBalance: " + DoubleToString(InitialBalance, 2)
                 + " / TargetProfit: " + tpState
                 + " / LossCut: " + IntegerToString(TargetLossPctVal) + "%";

    string line4 = "Trading active";
    if(IsOrderStopped) {
        line4 = "Stopped permanently";
    } else if(TargetProfitPaused) {
        line4 = "TP paused until " + TimeToString(TargetProfitResume, TIME_DATE | TIME_MINUTES);
    } else if(LossCutPaused) {
        line4 = "LossCut paused until " + TimeToString(LossCutResume, TIME_DATE | TIME_MINUTES);
    } else if(StartOff && TimeCurrent() < StartOffDeadline) {
        line4 = "StartOff until " + TimeToString(StartOffDeadline, TIME_DATE | TIME_MINUTES);
    }

    CreateLabel(InfoLabel1, "CL_Info1", 120, clrAqua);
    CreateLabel(InfoLabel2, "CL_Info2", 138, clrAqua);
    CreateLabel(InfoLabel3, "CL_Info3", 156, clrYellow);
    CreateLabel(InfoLabel4, "CL_Info4", 174, clrYellow);

    if(InfoLabel1 != NULL) InfoLabel1.Text(line1);
    if(InfoLabel2 != NULL) InfoLabel2.Text(line2);
    if(InfoLabel3 != NULL) InfoLabel3.Text(line3);
    if(InfoLabel4 != NULL) InfoLabel4.Text(line4);
}

//+------------------------------------------------------------------+
//| Account protection                                               |
//+------------------------------------------------------------------+
datetime GetNextResumeTime(ENUM_RESUME_MODE mode, ENUM_DAY_OF_WEEK targetDow, int days = 1) {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime todayMidnight = TimeCurrent() - (dt.hour * 3600 + dt.min * 60 + dt.sec);

    if(mode == RESUME_DAILY) {
        int safeDays = (days >= 1) ? days : 1;
        return todayMidnight + (datetime)(safeDays * 86400);
    }

    if(mode == RESUME_WEEKLY) {
        int dow          = dt.day_of_week;
        int targetDowInt = (int)targetDow;
        int daysUntil    = (targetDowInt - dow + 7) % 7;
        if(daysUntil == 0) daysUntil = 7;
        return todayMidnight + (datetime)(daysUntil * 86400);
    }

    if(mode == RESUME_MONTHLY) {
        int nextMon  = dt.mon + 1;
        int nextYear = dt.year;
        if(nextMon > 12) {
            nextMon = 1;
            nextYear++;
        }

        MqlDateTime nextMonth = {};
        nextMonth.year = nextYear;
        nextMonth.mon  = nextMon;
        nextMonth.day  = 1;
        nextMonth.hour = 0;
        nextMonth.min  = 0;
        nextMonth.sec  = 0;
        return StructToTime(nextMonth);
    }

    return todayMidnight + 86400;
}

datetime CalcStartOffDeadline() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime todayMidnight = TimeCurrent() - (dt.hour * 3600 + dt.min * 60 + dt.sec);

    if(StartOffType == START_OFF_DAY_AFTER) {
        int safeDays = (StartAfterDays >= 1) ? StartAfterDays : 1;
        return todayMidnight + (datetime)(safeDays * 86400);
    }

    int dow          = dt.day_of_week;
    int targetDowInt = (int)StartWeekday;
    int daysUntil    = (targetDowInt - dow + 7) % 7;
    if(daysUntil == 0) daysUntil = 7;
    return todayMidnight + (datetime)(daysUntil * 86400);
}

//+------------------------------------------------------------------+
//| Exposure control                                                 |
//+------------------------------------------------------------------+
int CountEAOpenPositions() {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNum) continue;
        count++;
    }
    return count;
}

bool HasPositionType(ENUM_POSITION_TYPE type) {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNum) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
            return true;
    }
    return false;
}

bool HasPendingType(ENUM_ORDER_TYPE type) {
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0 || !OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if((ulong)OrderGetInteger(ORDER_MAGIC) != MagicNum) continue;
        if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == type)
            return true;
    }
    return false;
}

void DeletePendingType(ENUM_ORDER_TYPE type) {
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0 || !OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if((ulong)OrderGetInteger(ORDER_MAGIC) != MagicNum) continue;
        if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type) continue;

        if(!Trade.OrderDelete(ticket))
            Print("Warn:: Pending delete failed. ticket=", ticket, " ret=", Trade.ResultRetcode());
    }
}

void DeleteAllPendings() {
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0 || !OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if((ulong)OrderGetInteger(ORDER_MAGIC) != MagicNum) continue;

        if(!Trade.OrderDelete(ticket))
            Print("Warn:: Pending delete failed. ticket=", ticket, " ret=", Trade.ResultRetcode());
    }
}

void CloseAllPositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNum) continue;

        if(!Trade.PositionClose(ticket))
            Print("Warn:: Position close failed. ticket=", ticket, " ret=", Trade.ResultRetcode());
    }
}

void CloseAllExposure() {
    DeleteAllPendings();
    CloseAllPositions();
}

//+------------------------------------------------------------------+
//| Protection checks                                                |
//+------------------------------------------------------------------+
void CheckTargetProfit() {
    if(TargetProfitRate <= 1.0) return;

    if(TargetProfitPaused) {
        if(TimeCurrent() >= TargetProfitResume) {
            InitialBalance     = AccountInfoDouble(ACCOUNT_BALANCE) + AccountInfoDouble(ACCOUNT_CREDIT);
            TargetProfitTarget = InitialBalance * TargetProfitRate;
            TargetProfitPaused = false;
            TargetProfitResume = 0;
            SaveState();
            Print("Info:: Target profit resumed. NewBalance=",
                  DoubleToString(InitialBalance, 2),
                  " NewTarget=", DoubleToString(TargetProfitTarget, 2));
        }
        return;
    }

    if(AccountInfoDouble(ACCOUNT_EQUITY) >= TargetProfitTarget) {
        CloseAllExposure();
        if(NupTime != RESUME_NONE) {
            TargetProfitPaused = true;
            TargetProfitResume = GetNextResumeTime(NupTime, NupResumeDay, NupDays);
            SaveState();
            Print("Info:: Target profit reached. Suspended until ",
                  TimeToString(TargetProfitResume, TIME_DATE | TIME_MINUTES));
        } else {
            IsOrderStopped = true;
            SaveState();
            Print("Info:: Target profit reached. EA stopped permanently.");
        }
    }
}

void LossCut() {
    if(LossCutPaused) {
        if(TimeCurrent() >= LossCutResume) {
            LossCutPaused      = false;
            LossCutResume      = 0;
            InitialBalance     = AccountInfoDouble(ACCOUNT_BALANCE) + AccountInfoDouble(ACCOUNT_CREDIT);
            TargetProfitTarget = (TargetProfitRate > 1.0) ? InitialBalance * TargetProfitRate : 0.0;
            SaveState();
            Print("Info:: LossCut resumed. NewBalance=",
                  DoubleToString(InitialBalance, 2),
                  " NewTarget=", DoubleToString(TargetProfitTarget, 2));
        }
        return;
    }

    double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
    double credit       = AccountInfoDouble(ACCOUNT_CREDIT);
    double totalBalance = balance + credit;
    if(totalBalance <= 0.0) return;

    double equity       = AccountInfoDouble(ACCOUNT_EQUITY);
    double floatingLoss = totalBalance - equity;
    double lossLimit    = Clamp((double)TargetLossPctVal, 0.0, 80.0) / 100.0;

    if(floatingLoss / totalBalance >= lossLimit) {
        CloseAllExposure();
        if(LcNupTime != RESUME_NONE) {
            LossCutPaused = true;
            LossCutResume = GetNextResumeTime(LcNupTime, LcNupResumeDay, LcNupDays);
            SaveState();
            Print("Warn:: LossCut triggered. Suspended until ",
                  TimeToString(LossCutResume, TIME_DATE | TIME_MINUTES));
        } else {
            IsOrderStopped = true;
            SaveState();
            Print("Warn:: LossCut triggered. EA stopped permanently.");
        }
    }
}

//+------------------------------------------------------------------+
//| Money management                                                 |
//+------------------------------------------------------------------+
double CalcAutoLot(double stopDistance) {
    if(!AutoLot) return NormalizeVolume(DefaultLots);

    double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskPct    = Clamp(AutoLotRiskPct, 0.01, 10.0);
    double riskMoney  = equity * (riskPct / 100.0) * MathMax(RiskLevel, 0.1);
    double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

    if(stopDistance <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
        return NormalizeVolume(DefaultLots);

    double moneyPerLot = (stopDistance / tickSize) * tickValue;
    if(moneyPerLot <= 0.0)
        return NormalizeVolume(DefaultLots);

    double volume = riskMoney / moneyPerLot;
    string desc;
    volume = NormalizeVolume(volume);
    if(!CheckVolumeValue(volume, desc)) {
        Print("Warn:: Auto lot volume adjusted to default. reason=", desc);
        return NormalizeVolume(DefaultLots);
    }

    return volume;
}

//+------------------------------------------------------------------+
//| Strategy                                                         |
//+------------------------------------------------------------------+
bool AllowNewOrders(ENUM_ORDER_TYPE orderType) {
    if(!IsMarginSufficient()) return false;
    if(IsOrderStopped || TargetProfitPaused || LossCutPaused) return false;
    if(StartOff && TimeCurrent() < StartOffDeadline) return false;
    if((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpreadPoints) return false;
    if(CountEAOpenPositions() >= MaxTotalPositions) return false;

    if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT) {
        if(OnePerSide && (HasPositionType(POSITION_TYPE_BUY) || HasPendingType(ORDER_TYPE_BUY_LIMIT)))
            return false;
    }

    if(orderType == ORDER_TYPE_SELL || orderType == ORDER_TYPE_SELL_LIMIT) {
        if(OnePerSide && (HasPositionType(POSITION_TYPE_SELL) || HasPendingType(ORDER_TYPE_SELL_LIMIT)))
            return false;
    }

    if(HasPositionType(POSITION_TYPE_BUY) || HasPositionType(POSITION_TYPE_SELL))
        return false;

    return true;
}

bool BuySignal(const SignalSnapshot &snap) {
    if(!EnableBuy) return false;
    if(snap.atr1 < (double)MinATRPoints * PointValue) return false;
    if(snap.emaTrend1 <= snap.emaSlow1) return false;
    if(snap.emaTrend1 <= snap.emaTrendSlopeRef) return false;
    if(snap.rsi1 < BuyMinRSI) return false;
    if(snap.close1 <= snap.high2) return false;

    double stretch = (snap.close1 - snap.emaFast1) / snap.atr1;
    if(stretch < BuyBreakoutATR) return false;
    return true;
}

bool SellSignal(const SignalSnapshot &snap) {
    if(!EnableSell) return false;
    if(snap.atr1 < (double)MinATRPoints * PointValue) return false;
    if(snap.emaTrend1 >= snap.emaSlow1) return false;
    if(snap.emaTrend1 >= snap.emaTrendSlopeRef) return false;
    if(snap.rsi1 > SellMaxRSI) return false;
    if(snap.close1 >= snap.low2) return false;

    double stretch = (snap.emaFast1 - snap.close1) / snap.atr1;
    if(stretch < SellBreakoutATR) return false;
    return true;
}

bool PlaceBuyOrder(const SignalSnapshot &snap) {
    if(!AllowNewOrders(ORDER_TYPE_BUY_LIMIT)) return false;

    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return false;

    double minStop = GetMinStopDistance();
    double entry   = snap.close1 - (snap.atr1 * BuyPullbackATR);
    double sl      = entry - (snap.atr1 * BuyInitialSLATR);
    double volume  = CalcAutoLot(entry - sl);
    datetime expiry = TimeCurrent() + (datetime)(MathMax(PendingExpiryBarsVal, 1) * PeriodSeconds(SignalTF));

    entry = NormalizeDouble(entry, SymDigits);
    sl    = NormalizeDouble(sl, SymDigits);

    if(entry <= 0.0 || sl <= 0.0 || volume <= 0.0) return false;

    if((tick.ask - entry) < minStop) {
        if(!FallbackMarket || !UseLimitEntries) return false;
        entry = tick.ask;
        sl    = entry - MathMax(snap.atr1 * BuyInitialSLATR, minStop);
        entry = NormalizeDouble(entry, SymDigits);
        sl    = NormalizeDouble(sl, SymDigits);

        if(!CheckMoneyForTrade(_Symbol, volume, ORDER_TYPE_BUY, entry)) return false;
        if(!Trade.Buy(volume, _Symbol, entry, sl, 0.0, EAName + " BUY")) {
            Print("Error:: Buy failed. ret=", Trade.ResultRetcode());
            return false;
        }
        return true;
    }

    if(!UseLimitEntries) {
        entry = tick.ask;
        sl    = entry - MathMax(snap.atr1 * BuyInitialSLATR, minStop);
        entry = NormalizeDouble(entry, SymDigits);
        sl    = NormalizeDouble(sl, SymDigits);

        if(!CheckMoneyForTrade(_Symbol, volume, ORDER_TYPE_BUY, entry)) return false;
        if(!Trade.Buy(volume, _Symbol, entry, sl, 0.0, EAName + " BUY")) {
            Print("Error:: Buy failed. ret=", Trade.ResultRetcode());
            return false;
        }
        return true;
    }

    if((entry - sl) < minStop) {
        sl = entry - minStop;
        sl = NormalizeDouble(sl, SymDigits);
    }

    if(!CheckMoneyForTrade(_Symbol, volume, ORDER_TYPE_BUY_LIMIT, entry)) return false;
    if(!Trade.BuyLimit(volume, entry, _Symbol, sl, 0.0, ORDER_TIME_SPECIFIED, expiry, EAName + " BUY_LIMIT")) {
        Print("Error:: BuyLimit failed. ret=", Trade.ResultRetcode());
        return false;
    }

    return true;
}

bool PlaceSellOrder(const SignalSnapshot &snap) {
    if(!AllowNewOrders(ORDER_TYPE_SELL_LIMIT)) return false;

    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return false;

    double minStop = GetMinStopDistance();
    double entry   = snap.close1 + (snap.atr1 * SellPullbackATR);
    double sl      = entry + (snap.atr1 * SellInitialSLATR);
    double volume  = CalcAutoLot(sl - entry);
    datetime expiry = TimeCurrent() + (datetime)(MathMax(PendingExpiryBarsVal, 1) * PeriodSeconds(SignalTF));

    entry = NormalizeDouble(entry, SymDigits);
    sl    = NormalizeDouble(sl, SymDigits);

    if(entry <= 0.0 || sl <= 0.0 || volume <= 0.0) return false;

    if((entry - tick.bid) < minStop) {
        if(!FallbackMarket || !UseLimitEntries) return false;
        entry = tick.bid;
        sl    = entry + MathMax(snap.atr1 * SellInitialSLATR, minStop);
        entry = NormalizeDouble(entry, SymDigits);
        sl    = NormalizeDouble(sl, SymDigits);

        if(!CheckMoneyForTrade(_Symbol, volume, ORDER_TYPE_SELL, entry)) return false;
        if(!Trade.Sell(volume, _Symbol, entry, sl, 0.0, EAName + " SELL")) {
            Print("Error:: Sell failed. ret=", Trade.ResultRetcode());
            return false;
        }
        return true;
    }

    if(!UseLimitEntries) {
        entry = tick.bid;
        sl    = entry + MathMax(snap.atr1 * SellInitialSLATR, minStop);
        entry = NormalizeDouble(entry, SymDigits);
        sl    = NormalizeDouble(sl, SymDigits);

        if(!CheckMoneyForTrade(_Symbol, volume, ORDER_TYPE_SELL, entry)) return false;
        if(!Trade.Sell(volume, _Symbol, entry, sl, 0.0, EAName + " SELL")) {
            Print("Error:: Sell failed. ret=", Trade.ResultRetcode());
            return false;
        }
        return true;
    }

    if((sl - entry) < minStop) {
        sl = entry + minStop;
        sl = NormalizeDouble(sl, SymDigits);
    }

    if(!CheckMoneyForTrade(_Symbol, volume, ORDER_TYPE_SELL_LIMIT, entry)) return false;
    if(!Trade.SellLimit(volume, entry, _Symbol, sl, 0.0, ORDER_TIME_SPECIFIED, expiry, EAName + " SELL_LIMIT")) {
        Print("Error:: SellLimit failed. ret=", Trade.ResultRetcode());
        return false;
    }

    return true;
}

void EvaluateEntries() {
    if(!IsNewSignalBar()) return;

    SignalSnapshot snap;
    if(!BuildSignalSnapshot(snap)) return;

    if(BuySignal(snap)) {
        DeletePendingType(ORDER_TYPE_SELL_LIMIT);
        PlaceBuyOrder(snap);
        return;
    }

    if(SellSignal(snap)) {
        DeletePendingType(ORDER_TYPE_BUY_LIMIT);
        PlaceSellOrder(snap);
        return;
    }
}

//+------------------------------------------------------------------+
//| Position management                                              |
//+------------------------------------------------------------------+
bool MoveStopLoss(ulong ticket, double newSL, double currentTP) {
    newSL = NormalizeDouble(newSL, SymDigits);
    if(!Trade.PositionModify(ticket, newSL, currentTP)) {
        Print("Warn:: PositionModify failed. ticket=", ticket, " ret=", Trade.ResultRetcode());
        return false;
    }
    return true;
}

void ManagePositionExit() {
    double atrNow = GetIndicatorValue(HandleATR, 1);
    if(atrNow <= 0.0) atrNow = GetMinStopDistance();

    double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double minStop    = GetMinStopDistance();
    double trailStep  = MathMax((double)TrailStepPoints * PointValue, PointValue);

    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNum) continue;

        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double openPrice        = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL        = PositionGetDouble(POSITION_SL);
        double currentTP        = PositionGetDouble(POSITION_TP);
        datetime openTime       = (datetime)PositionGetInteger(POSITION_TIME);
        int heldBars            = (int)((TimeCurrent() - openTime) / PeriodSeconds(SignalTF));

        if(type == POSITION_TYPE_BUY && heldBars >= BuyTimeExitBarsVal) {
            Trade.PositionClose(ticket);
            continue;
        }

        if(type == POSITION_TYPE_SELL && heldBars >= SellTimeExitBarsVal) {
            Trade.PositionClose(ticket);
            continue;
        }

        if(!UseATRTrailing) continue;

        if(type == POSITION_TYPE_BUY) {
            double profitDistance = bid - openPrice;
            if(profitDistance < TrailStartATR * atrNow) continue;

            double newSL = bid - (TrailDistanceATR * atrNow);
            if(newSL <= openPrice) continue;
            if((bid - newSL) < minStop) newSL = bid - minStop;
            if(currentSL > 0.0 && newSL < currentSL + trailStep) continue;
            MoveStopLoss(ticket, newSL, currentTP);
        } else if(type == POSITION_TYPE_SELL) {
            double profitDistance = openPrice - ask;
            if(profitDistance < TrailStartATR * atrNow) continue;

            double newSL = ask + (TrailDistanceATR * atrNow);
            if(newSL >= openPrice) continue;
            if((newSL - ask) < minStop) newSL = ask + minStop;
            if(currentSL > 0.0 && newSL > currentSL - trailStep) continue;
            MoveStopLoss(ticket, newSL, currentTP);
        }
    }
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                 |
//+------------------------------------------------------------------+
int OnInit() {
    if(Account.MarginMode() != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
        return INIT_FAILED;

    SymDigits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    PointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(SymDigits <= 0 || PointValue <= 0.0)
        return INIT_FAILED;

    FastEMAPeriodVal    = (int)Clamp(FastEMAPeriod, 2, 200);
    TrendEMAPeriodVal   = (int)Clamp(TrendEMAPeriod, 2, 400);
    SlowEMAPeriodVal    = (int)Clamp(SlowEMAPeriod, 2, 600);
    ATRPeriodVal        = (int)Clamp(ATRPeriod, 2, 200);
    RSIPeriodVal        = (int)Clamp(RSIPeriod, 2, 100);
    PendingExpiryBarsVal= (int)Clamp(PendingExpiryBars, 1, 20);
    BuyTimeExitBarsVal  = (int)Clamp(BuyTimeExitBars, 1, 200);
    SellTimeExitBarsVal = (int)Clamp(SellTimeExitBars, 1, 200);
    TargetLossPctVal    = (int)Clamp(TargetLossPct, 1, 80);

    HandleFastEMA  = iMA(_Symbol, SignalTF, FastEMAPeriodVal, 0, MODE_EMA, PRICE_CLOSE);
    HandleTrendEMA = iMA(_Symbol, SignalTF, TrendEMAPeriodVal, 0, MODE_EMA, PRICE_CLOSE);
    HandleSlowEMA  = iMA(_Symbol, SignalTF, SlowEMAPeriodVal, 0, MODE_EMA, PRICE_CLOSE);
    HandleATR      = iATR(_Symbol, SignalTF, ATRPeriodVal);
    HandleRSI      = iRSI(_Symbol, SignalTF, RSIPeriodVal, PRICE_CLOSE);

    if(HandleFastEMA == INVALID_HANDLE ||
       HandleTrendEMA == INVALID_HANDLE ||
       HandleSlowEMA == INVALID_HANDLE ||
       HandleATR == INVALID_HANDLE ||
       HandleRSI == INVALID_HANDLE) {
        Print("Error:: Indicator handle creation failed.");
        return INIT_FAILED;
    }

    Trade.SetExpertMagicNumber(MagicNum);
    Trade.SetDeviationInPoints(30);

    InitialBalance     = AccountInfoDouble(ACCOUNT_BALANCE) + AccountInfoDouble(ACCOUNT_CREDIT);
    TargetProfitTarget = (TargetProfitRate > 1.0) ? InitialBalance * TargetProfitRate : 0.0;

    LoadState();

    if(StartOff && StartOffDeadline <= 0)
        StartOffDeadline = CalcStartOffDeadline();

    SaveState();
    DrawInfo();

    Print("Info:: ", EAName, " started. Symbol=", _Symbol,
          " TF=", EnumToString(SignalTF),
          " AutoLot=", (AutoLot ? "ON" : "OFF"),
          " UseLimitEntries=", (UseLimitEntries ? "ON" : "OFF"));
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    SaveState();

    if(HandleFastEMA  != INVALID_HANDLE) IndicatorRelease(HandleFastEMA);
    if(HandleTrendEMA != INVALID_HANDLE) IndicatorRelease(HandleTrendEMA);
    if(HandleSlowEMA  != INVALID_HANDLE) IndicatorRelease(HandleSlowEMA);
    if(HandleATR      != INVALID_HANDLE) IndicatorRelease(HandleATR);
    if(HandleRSI      != INVALID_HANDLE) IndicatorRelease(HandleRSI);

    if(InfoLabel1 != NULL) { delete InfoLabel1; InfoLabel1 = NULL; }
    if(InfoLabel2 != NULL) { delete InfoLabel2; InfoLabel2 = NULL; }
    if(InfoLabel3 != NULL) { delete InfoLabel3; InfoLabel3 = NULL; }
    if(InfoLabel4 != NULL) { delete InfoLabel4; InfoLabel4 = NULL; }
}

void OnTick() {
    DrawInfo();

    LossCut();
    CheckTargetProfit();
    ManagePositionExit();

    if(IsOrderStopped) return;
    if(TargetProfitPaused) return;
    if(LossCutPaused) return;
    if(StartOff && TimeCurrent() < StartOffDeadline) return;

    EvaluateEntries();
}
//--- End of code ---//
