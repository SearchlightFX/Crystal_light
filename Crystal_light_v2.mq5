//+------------------------------------------------------------------+
//|                                             Crystal_light_v2.mq5 |
//|                                          Copyright 2026, KOKONOE |
//|                                        https://linktr.ee/kokonoe |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, KOKONOE"
#property link      "https://linktr.ee/kokonoe"
#property version   "2.0"
#property description "Range auto-detection limit-order EA for MT5 hedge accounts"

#include <Controls/Label.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input(name = "EA name")                   string EAName             = "Crystal light";
input(name = "Magic number")              ulong  MagicNum           = 990992;
input(name = "Lots")                      double DefaultLots        = 0.01;
input(name = "Lookback bars for range")   int    RangeLookbackBars  = 48;
input(name = "Time frame")                ENUM_TIMEFRAMES TimeFrame = PERIOD_CURRENT;
input(name = "SL value points (0 = no SL)") int  SLPoints           = 0;
input(name = "Min range points")          int    MinRangePoints     = 120;
input(name = "Max range points (0 = OFF)") int   MaxRangePoints     = 0;
input(name = "Entry offset from edge points") int EntryOffsetPoints = 5;
input(name = "Order refresh seconds")     int    OrderRefreshSeconds = 30;
input(name = "Refresh pending orders with range") bool RefreshPendingOrders = true;
input(name = "Slippage points")           int    SlippagePoints     = 30;

input(name = "=== Side Switch ===")       string _sep_side          = "####################";
input(name = "Use Buy side")              bool   UseBuy             = true;
input(name = "Use Sell side")             bool   UseSell            = true;

input(name = "=== Auto Lot ===")          string _sep_al            = "####################";
input(name = "Auto lot ON/OFF")           bool   AutoLot            = false;
input(name = "Balance per minimum lot")   double BalancePerMiniLot   = 250000.0;
input(name = "AutoLot multiplier")        double AutoLotMultiplier  = 1.0;

input(name = "=== Doten ===")             string _sep_doten         = "####################";
input(name = "Doten after TP ON/OFF")     bool   UseDoten           = false;

input(name = "=== Multiple Orders ===")   string _sep_multi         = "####################";
input(name = "Multiple positions/orders ON/OFF") bool UseMultipleOrders = false;
input(name = "Orders per side")           int    OrdersPerSide      = 1;
input(name = "Layer step points")         int    LayerStepPoints    = 20;
input(name = "Max holding positions")     int    MaxPositions       = 4;
input(name = "Max pending orders")        int    MaxPendingOrders   = 4;

input(name = "===== Margin Guard Settings =====") string mg_separator = "####################";
input(name = "Min margin level to allow entry (%, 0=OFF)") double MinMarginLevel = 200.0;

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int      SymDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
double   RangeHigh = 0.0;
double   RangeLow  = 0.0;
double   RangeSize = 0.0;
datetime LastOrderRefresh = 0;

CLabel *InfoLabel1 = NULL;
CLabel *InfoLabel2 = NULL;
CLabel *InfoLabel3 = NULL;
CLabel *InfoLabel4 = NULL;

CTrade        Trade;
CAccountInfo  AcctInfo;
CPositionInfo PosInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    if(AcctInfo.MarginMode() != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
        Print("Error:: ", EAName, " is for hedge accounts only.");
        return INIT_FAILED;
    }

    if(RangeLookbackBars < 2) {
        Print("Error:: Lookback bars must be 2 or more.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(DefaultLots <= 0.0) {
        Print("Error:: Lots must be greater than zero.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(MaxPositions < 1 || MaxPendingOrders < 0) {
        Print("Error:: Max positions/orders inputs are invalid.");
        return INIT_PARAMETERS_INCORRECT;
    }

    Trade.SetExpertMagicNumber(MagicNum);
    Trade.SetDeviationInPoints(SlippagePoints);

    InfoLabel1 = new CLabel();
    InfoLabel2 = new CLabel();
    InfoLabel3 = new CLabel();
    InfoLabel4 = new CLabel();

    UpdateRange();
    DrawInfo();

    Print("Info:: ", EAName, " Started. MagicNum=", MagicNum,
          " Lots=", DoubleToString(DefaultLots, 2),
          " LookbackBars=", RangeLookbackBars,
          " AutoLot=", (AutoLot ? "ON" : "OFF"),
          " Doten=", (UseDoten ? "ON" : "OFF"),
          " Multiple=", (UseMultipleOrders ? "ON" : "OFF"));

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if(InfoLabel1 != NULL) { delete InfoLabel1; InfoLabel1 = NULL; }
    if(InfoLabel2 != NULL) { delete InfoLabel2; InfoLabel2 = NULL; }
    if(InfoLabel3 != NULL) { delete InfoLabel3; InfoLabel3 = NULL; }
    if(InfoLabel4 != NULL) { delete InfoLabel4; InfoLabel4 = NULL; }

    ObjectDelete(0, "SCL_BG_Line1");
    ObjectDelete(0, "SCL_BG_Line2");
    ObjectDelete(0, "SCL_BG_Line3");
    ObjectDelete(0, "SCL_BG_Line4");
    ObjectDelete(0, "CLV2_RangeHigh");
    ObjectDelete(0, "CLV2_RangeLow");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    UpdateRange();
    DrawRangeLines();
    DrawInfo();

    if(!IsRangeTradable())
        return;

    if(TimeCurrent() - LastOrderRefresh < OrderRefreshSeconds)
        return;

    LastOrderRefresh = TimeCurrent();
    if(RefreshPendingOrders)
        DeleteMyPendingOrders();
    PlaceRangeOrders();
}

//+------------------------------------------------------------------+
//| Trade transaction: Doten after TP close                          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
    if(!UseDoten) return;
    if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
    if(trans.deal == 0) return;
    if(!HistoryDealSelect(trans.deal)) return;

    if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNum) return;
    if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
    if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
    if((ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON) != DEAL_REASON_TP) return;

    ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
    if(dealType == DEAL_TYPE_SELL) {
        PlaceOneOrder(ORDER_TYPE_SELL_LIMIT, true, 0);
    } else if(dealType == DEAL_TYPE_BUY) {
        PlaceOneOrder(ORDER_TYPE_BUY_LIMIT, true, 0);
    }
}

//+------------------------------------------------------------------+
//| Draw information panel                                           |
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
    int    rangePoints     = (int)MathRound(RangeSize / _Point);

    string infoLine1 = "Symbol: " + c_symbol
                     + " / float: " + DoubleToString(pf_ls, 1) + "%"
                     + " / Spread: " + IntegerToString(on_chart_spread);

    string infoLine2 = "Range: " + DoubleToString(RangeLow, SymDigits)
                     + " - " + DoubleToString(RangeHigh, SymDigits)
                     + " (" + IntegerToString(rangePoints) + "pt)"
                     + " / Next: " + candle_time;

    string autoLotStr = AutoLot
                        ? ("AutoLot:ON x" + DoubleToString(AutoLotMultiplier, 2))
                        : "AutoLot:OFF";
    string infoLine3 = autoLotStr
                     + " / Doten:" + (UseDoten ? "ON" : "OFF")
                     + " / Multi:" + (UseMultipleOrders ? "ON" : "OFF");

    string infoLine4 = "Positions: " + IntegerToString(CountMyPositions(-1))
                     + "/" + IntegerToString(MaxPositions)
                     + " / Pending: " + IntegerToString(CountMyPending(-1))
                     + "/" + IntegerToString(MaxPendingOrders)
                     + " / Lot: " + DoubleToString(CalcLots(), 2);

    DrawBg("SCL_BG_Line1", 120, 120);
    DrawBg("SCL_BG_Line2", 120, 140);
    DrawBg("SCL_BG_Line3", 120, 160);
    DrawBg("SCL_BG_Line4", 120, 180);

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

void DrawBg(string name, int x, int y) {
    if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectDelete(0, name);
        ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, 620);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, 20);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, 0x80646464);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Range calculation and display                                    |
//+------------------------------------------------------------------+
bool UpdateRange() {
    ENUM_TIMEFRAMES tf = EffectiveTimeFrame();
    int bars = iBars(_Symbol, tf);
    if(bars <= RangeLookbackBars + 1) return false;

    int highIndex = iHighest(_Symbol, tf, MODE_HIGH, RangeLookbackBars, 1);
    int lowIndex  = iLowest(_Symbol, tf, MODE_LOW, RangeLookbackBars, 1);
    if(highIndex < 0 || lowIndex < 0) return false;

    RangeHigh = NormalizeDouble(iHigh(_Symbol, tf, highIndex), SymDigits);
    RangeLow  = NormalizeDouble(iLow(_Symbol, tf, lowIndex), SymDigits);
    RangeSize = RangeHigh - RangeLow;
    return (RangeSize > 0.0);
}

bool IsRangeTradable() {
    if(!UpdateRange()) return false;
    int rangePoints = (int)MathRound(RangeSize / _Point);
    if(rangePoints < MinRangePoints) return false;
    if(MaxRangePoints > 0 && rangePoints > MaxRangePoints) return false;
    if(!IsMarginSufficient()) return false;
    return true;
}

void DrawRangeLines() {
    DrawHLine("CLV2_RangeHigh", RangeHigh, clrTomato);
    DrawHLine("CLV2_RangeLow", RangeLow, clrDeepSkyBlue);
}

void DrawHLine(string name, double price, color lineColor) {
    if(price <= 0.0) return;
    if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) {
        ObjectSetDouble(0, name, OBJPROP_PRICE, price);
    }
    ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

ENUM_TIMEFRAMES EffectiveTimeFrame() {
    return (TimeFrame == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : TimeFrame;
}

//+------------------------------------------------------------------+
//| Order placement                                                  |
//+------------------------------------------------------------------+
void PlaceRangeOrders() {
    int maxLayers = UseMultipleOrders ? OrdersPerSide : 1;
    if(maxLayers < 1) maxLayers = 1;

    if(UseBuy) {
        int existingBuy = CountMyPositions(POSITION_TYPE_BUY) + CountMyPending(ORDER_TYPE_BUY_LIMIT);
        for(int layer = existingBuy; layer < maxLayers; layer++) {
            if(!CanAddExposure()) break;
            if(!PlaceOneOrder(ORDER_TYPE_BUY_LIMIT, false, layer)) break;
        }
    }

    if(UseSell) {
        int existingSell = CountMyPositions(POSITION_TYPE_SELL) + CountMyPending(ORDER_TYPE_SELL_LIMIT);
        for(int layer = existingSell; layer < maxLayers; layer++) {
            if(!CanAddExposure()) break;
            if(!PlaceOneOrder(ORDER_TYPE_SELL_LIMIT, false, layer)) break;
        }
    }
}

bool PlaceOneOrder(ENUM_ORDER_TYPE orderType, bool fromDoten, int layer) {
    if(!IsRangeTradable()) return false;
    if(!CanAddExposure()) return false;

    double lot = CalcLots();
    string desc;
    if(!CheckVolumeValue(lot, desc)) {
        Print("Warn:: Lot issue: ", desc);
        return false;
    }
    if(!CheckMoneyForTrade(_Symbol, lot, orderType)) return false;

    int stopsLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    int spread      = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    double minDist  = (MathMax(MathMax(stopsLevel, freezeLevel) + 2, spread + 2)) * _Point;
    double layerDist = (EntryOffsetPoints + (layer * LayerStepPoints)) * _Point;
    if(layerDist < minDist) layerDist = minDist;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double price = 0.0;
    double sl = 0.0;
    double tp = 0.0;

    if(orderType == ORDER_TYPE_BUY_LIMIT) {
        price = NormalizeDouble(RangeLow + layerDist, SymDigits);
        if(price >= ask - minDist) price = NormalizeDouble(ask - minDist, SymDigits);
        tp = NormalizeDouble(RangeHigh - minDist, SymDigits);
        if(tp <= price + minDist) tp = NormalizeDouble(price + minDist, SymDigits);
        if(SLPoints > 0) sl = NormalizeDouble(price - SLPoints * _Point, SymDigits);
        if(!UseBuy && !fromDoten) return false;
        return Trade.BuyLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, EAName);
    }

    if(orderType == ORDER_TYPE_SELL_LIMIT) {
        price = NormalizeDouble(RangeHigh - layerDist, SymDigits);
        if(price <= bid + minDist) price = NormalizeDouble(bid + minDist, SymDigits);
        tp = NormalizeDouble(RangeLow + minDist, SymDigits);
        if(tp >= price - minDist) tp = NormalizeDouble(price - minDist, SymDigits);
        if(SLPoints > 0) sl = NormalizeDouble(price + SLPoints * _Point, SymDigits);
        if(!UseSell && !fromDoten) return false;
        return Trade.SellLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, EAName);
    }

    return false;
}

bool CanAddExposure() {
    if(CountMyPositions(-1) >= MaxPositions) return false;
    if(CountMyPending(-1) >= MaxPendingOrders) return false;
    return true;
}

void DeleteMyPendingOrders() {
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if((ulong)OrderGetInteger(ORDER_MAGIC) != MagicNum) continue;

        ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT) continue;

        if(!Trade.OrderDelete(ticket)) {
            Print("Warn:: Pending order delete failed. ticket=", ticket,
                  " retcode=", Trade.ResultRetcode(),
                  " err=", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
//| Account and symbol guards                                        |
//+------------------------------------------------------------------+
double CalcLots() {
    double lot = DefaultLots;

    if(AutoLot && BalancePerMiniLot > 0.0) {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE) + AccountInfoDouble(ACCOUNT_CREDIT);
        lot = (balance / BalancePerMiniLot) * 0.01 * AutoLotMultiplier;
    }

    double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if(lot < minVol) lot = minVol;
    if(lot > maxVol) lot = maxVol;
    if(volStep > 0.0) lot = MathFloor(lot / volStep) * volStep;
    return NormalizeDouble(lot, 2);
}

bool IsMarginSufficient() {
    if(MinMarginLevel <= 0.0)
        return true;
    double usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);
    if(usedMargin <= 0.0)
        return true;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
        return true;
    double marginLevel = (equity / usedMargin) * 100.0;
    if(marginLevel < MinMarginLevel) {
        Print("Warn:: Entry blocked - margin level too low: ",
              DoubleToString(marginLevel, 1), "% < ", DoubleToString(MinMarginLevel, 1), "%");
        return false;
    }
    return true;
}

bool CheckMoneyForTrade(string symb, double lots, ENUM_ORDER_TYPE type) {
    MqlTick mqltick;
    SymbolInfoTick(symb, mqltick);
    ENUM_ORDER_TYPE calcType = (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT)
                               ? ORDER_TYPE_SELL
                               : ORDER_TYPE_BUY;
    double price = (calcType == ORDER_TYPE_SELL) ? mqltick.bid : mqltick.ask;

    double margin, freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if(!OrderCalcMargin(calcType, symb, lots, price, margin)) {
        Print("Error:: Error in ", __FUNCTION__, " code=", GetLastError());
        return false;
    }
    if(margin > freeMargin) {
        Print("Warn:: Not enough free margin for trade. Margin required: ", margin,
              " Free margin: ", freeMargin);
        return false;
    }
    return true;
}

bool CheckVolumeValue(double volume, string &description) {
    double minVol = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    if(volume < minVol) {
        description = StringFormat("Below SYMBOL_VOLUME_MIN=%.2f", minVol);
        return false;
    }
    double maxVol = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    if(volume > maxVol) {
        description = StringFormat("Above SYMBOL_VOLUME_MAX=%.2f", maxVol);
        return false;
    }
    double volStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    int    ratio   = (int)MathRound(volume / volStep);
    if(MathAbs(ratio * volStep - volume) > 0.0000001) {
        description = StringFormat("Not a multiple of SYMBOL_VOLUME_STEP=%.2f", volStep);
        return false;
    }
    description = "OK";
    return true;
}

//+------------------------------------------------------------------+
//| Counters                                                         |
//+------------------------------------------------------------------+
int CountMyPositions(int positionType) {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNum) continue;
        if(positionType >= 0 && (int)PositionGetInteger(POSITION_TYPE) != positionType) continue;
        count++;
    }
    return count;
}

int CountMyPending(int orderType) {
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if((ulong)OrderGetInteger(ORDER_MAGIC) != MagicNum) continue;
        ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT) continue;
        if(orderType >= 0 && (int)type != orderType) continue;
        count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Candle timer                                                     |
//+------------------------------------------------------------------+
string CandleTimer() {
    ENUM_TIMEFRAMES tf = EffectiveTimeFrame();
    datetime currentBarTime = iTime(_Symbol, tf, 0);
    int periodSeconds = PeriodSeconds(tf);
    if(currentBarTime <= 0 || periodSeconds <= 0) return "--:--";

    int remain = (int)(currentBarTime + periodSeconds - TimeCurrent());
    if(remain < 0) remain = 0;

    int hours = remain / 3600;
    int mins  = (remain % 3600) / 60;
    int secs  = remain % 60;

    if(hours > 0)
        return StringFormat("%02d:%02d:%02d", hours, mins, secs);
    return StringFormat("%02d:%02d", mins, secs);
}
//+------------------------------------------------------------------+
