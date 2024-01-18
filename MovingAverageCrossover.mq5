//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include<Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input enums                                                      |
//+------------------------------------------------------------------+
enum EntryExitType {Fixed, Percent};

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "General"
static input double InpLotSize = 0.01; // lot size
input double InpLeverageUtil = 0.05; // leverage utilization

input group "Entry/Exit";
input bool InpCloseSignal = true; // close trades by opposite signal
input EntryExitType InpStopLossType = Fixed; // stop loss type
input EntryExitType InpTakeProfitType = Fixed; // take profit type
input double InpStopLossPercent = 1.0; // stop loss in %
input double InpTakeProfitPercent = 2.0; // take profit in %
input int InpStopLossPips = 0; // stop loss in pips (0 = off)
input int InpTakeProfitPips = 100; // take profit in pips (0 = off)

input group "MovingAverages";
input int InpFastEmaPeriod = 24; // fast ema period
input int InpSlowEmaPeriod = 48; // slow ema period
input int InpSmaPeriod = 240; // sma period

input group "RsiFilter";
input bool InpUseRsiFilter = false; // use rsi filter
input ENUM_TIMEFRAMES InpRsiTimeframe = PERIOD_H1; // rsi timeframe
input int InpRsiPeriod = 14; // rsi period
input int InpRsiUpperLevel = 75; // rsi upper level
input int InpRsiLowerLevel = 25; // rsi lower level

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
long leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
int handleFastEma, handleSlowEma, handleSma, handleRsi;
double fastEmaBuffer[], slowEmaBuffer[], smaBuffer[], rsiBuffer[];
datetime openTimeBuy, openTimeSell;
MqlTick currentTick;
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
    // check user inputs
    if(InpLotSize <= 0 || InpLotSize > 10){
        Alert("InpLotSize <= 0 || InpLotSize > 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(InpFastEmaPeriod <= 1 || InpSlowEmaPeriod <= 1 || InpSmaPeriod <= 1){
        Alert("InpFastEmaPeriod <= 1 || InpSlowEmaPeriod <= 1 || InpSmaPeriod <= 1");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(InpFastEmaPeriod >= InpSlowEmaPeriod){
        Alert("InpFastEmaPeriod >= InpSlowEmaPeriod");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(InpSlowEmaPeriod >= InpSmaPeriod){
        Alert("InpSlowEmaPeriod >= InpSmaPeriod");
        return INIT_PARAMETERS_INCORRECT;
    }

    if(InpUseRsiFilter == true){
        if(InpRsiPeriod <= 1){
            Alert("InpRsiPeriod<=1");
            return INIT_PARAMETERS_INCORRECT;
        }
        if(InpRsiUpperLevel <= InpRsiLowerLevel){
            Alert("InpRsiUpperLevel <= InpRsiLowerLevel");
            return INIT_PARAMETERS_INCORRECT;
        }
        if(InpRsiUpperLevel > 100){
            Alert("InpRsiUpperLevel > 100");
            return INIT_PARAMETERS_INCORRECT;
        }
        if(InpRsiLowerLevel <= 0){
            Alert("InpRsiLowerLevel <= 0");
            return INIT_PARAMETERS_INCORRECT;
        }
    }

    // create indicator handles
    handleFastEma = iMA(_Symbol, _Period, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if(handleFastEma == INVALID_HANDLE){
        Alert("Failed to create indicator handleFastEma");
        return INIT_FAILED;  
    }
    handleSlowEma = iMA(_Symbol, _Period, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if(handleSlowEma == INVALID_HANDLE){
        Alert("Failed to create indicator handleSlowEma");
        return INIT_FAILED;  
    }
    handleSma = iMA(_Symbol, _Period, InpSmaPeriod, 0, MODE_SMA, PRICE_CLOSE);
    if(handleSma == INVALID_HANDLE){
        Alert("Failed to create indicator handleSma");
        return INIT_FAILED;  
    }
    if(InpUseRsiFilter == true){
        handleRsi = iRSI(_Symbol, InpRsiTimeframe, InpRsiPeriod, PRICE_CLOSE);
        if(handleRsi == INVALID_HANDLE){
            Alert("Failed to create indicator handleRSI");
            return INIT_FAILED;  
        }
    }

    // set buffer as series
    ArraySetAsSeries(fastEmaBuffer, true);
    ArraySetAsSeries(slowEmaBuffer, true);
    ArraySetAsSeries(smaBuffer, true);
    
    if(InpUseRsiFilter == true){
        ArraySetAsSeries(rsiBuffer, true);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
    // release indicator handles
    if(handleFastEma != INVALID_HANDLE){IndicatorRelease(handleFastEma);}
    if(handleSlowEma != INVALID_HANDLE){IndicatorRelease(handleSlowEma);}
    if(handleSma != INVALID_HANDLE){IndicatorRelease(handleSma);}
    if(InpUseRsiFilter == true && handleRsi != INVALID_HANDLE){IndicatorRelease(handleRsi);}
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
    // get current tick
    if(!SymbolInfoTick(_Symbol,currentTick)){Print("Failed to get current tick"); return;}

    //+------------------------------------------------------------------+

    // get fastEma values
    int values = CopyBuffer(handleFastEma, 0, 0, 2, fastEmaBuffer);
    if(values != 2){Print("Failed to get fastEma values"); return;}

    // get slowEma values
    values = CopyBuffer(handleSlowEma, 0, 0, 2, slowEmaBuffer);
    if(values != 2){Print("Failed to get slowEma values"); return;}

    // get sma values
    values = CopyBuffer(handleSma, 0, 0, 2, smaBuffer);
    if(values != 2){Print("Failed to get sma values"); return;}

    if(InpUseRsiFilter == true){
        // get rsi values
        values = CopyBuffer(handleRsi, 0, 0, 1, rsiBuffer);
        if(values != 1){Print("Failed to get rsi values"); return;}
    }

    //+------------------------------------------------------------------+

    // get current balance
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    // count open positions
    int countBuy, countSell;
    if(!CountOpenPositions(countBuy, countSell)){return;}

    // percent exits
    if(InpStopLossType == Percent){PercentStopLoss(balance, InpStopLossPercent);}
    if(InpTakeProfitType == Percent){PercentTakeProfit(balance, InpTakeProfitPercent);}

    //+------------------------------------------------------------------+

    // trade conditions
    bool buyCondition, sellCondition;

    if(InpUseRsiFilter == true){
        buyCondition = fastEmaBuffer[1] < slowEmaBuffer[1] && fastEmaBuffer[0] > slowEmaBuffer[0] && fastEmaBuffer[0] < smaBuffer[0] && slowEmaBuffer[0] < smaBuffer[0] && rsiBuffer[0] < InpRsiLowerLevel;
        sellCondition = fastEmaBuffer[1] > slowEmaBuffer[1] && fastEmaBuffer[0] < slowEmaBuffer[0] && fastEmaBuffer[0] > smaBuffer[0] && slowEmaBuffer[0] > smaBuffer[0] && rsiBuffer[0] > InpRsiUpperLevel;
    } else {
        buyCondition = fastEmaBuffer[1] < slowEmaBuffer[1] && fastEmaBuffer[0] > slowEmaBuffer[0] && fastEmaBuffer[0] < smaBuffer[0] && slowEmaBuffer[0] < smaBuffer[0];
        sellCondition = fastEmaBuffer[1] > slowEmaBuffer[1] && fastEmaBuffer[0] < slowEmaBuffer[0] && fastEmaBuffer[0] > smaBuffer[0] && slowEmaBuffer[0] > smaBuffer[0];
    }

    // check for buy position
    if(buyCondition == true && countBuy == 0 && openTimeBuy != iTime(_Symbol, _Period, 0)){

        // close sell trades
        if(InpCloseSignal){if(!ClosePositions(2)){return;}}

        // set new candle time
        openTimeBuy = iTime(_Symbol, _Period, 0);

        // set lot size, stop loss and take profit
        double lotSize = InpLeverageUtil == 0 ? InpLotSize : NormalizeDouble(((balance * leverage) / 100000) * InpLeverageUtil, 2);
        double sl = InpStopLossPips == 0 ? 0 : currentTick.bid - InpStopLossPips * 10 * _Point;
        double tp = InpTakeProfitPips == 0 ? 0 : currentTick.bid + InpTakeProfitPips * 10 * _Point;

        // normalizing sl and tp
        if(!NormalizePrice(sl)){return;}
        if(!NormalizePrice(tp)){return;}

        // open buy
        trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, lotSize, currentTick.ask, sl, tp, "AdvancedMA");
    }

    //+------------------------------------------------------------------+

    // check for sell position
    if(sellCondition == true && countSell == 0 && openTimeSell != iTime(_Symbol, _Period, 0)){

        // close buy trades
        if(InpCloseSignal){if(!ClosePositions(1)){return;}}

        // set new candle time
        openTimeSell = iTime(_Symbol, _Period, 0);

        // set lot size, stop loss and take profit
        double lotSize = InpLeverageUtil == 0 ? InpLotSize : NormalizeDouble(((balance * leverage) / 100000) * InpLeverageUtil, 2);
        double sl = InpStopLossPips == 0 ? 0 : currentTick.ask + InpStopLossPips * 10 * _Point;
        double tp = InpTakeProfitPips == 0 ? 0 : currentTick.ask - InpTakeProfitPips * 10 * _Point;

        // normalizing sl and tp
        if(!NormalizePrice(sl)){return;}
        if(!NormalizePrice(tp)){return;}

        // open sell
        trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, lotSize, currentTick.bid, sl, tp, "AdvancedMA");
    }
}

// normalize price
bool NormalizePrice(double &price){
    double tickSize=0;
    if(!SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE,tickSize)){Print("Failed to get tick size"); return false;}
    price=NormalizeDouble(MathRound(price/tickSize)*tickSize,_Digits);
    return true;
}

// close positions
bool ClosePositions(int all_buy_sell){
    int total=PositionsTotal();
    for(int i=total-1; i>=0; i--){
        ulong ticket=PositionGetTicket(i);
        if(ticket<=0){Print("Failed to get position ticket"); return false;}
        long type;
        if(!PositionGetInteger(POSITION_TYPE,type)){Print("Failed to get position type"); return false;}
        if(all_buy_sell==1 && type==POSITION_TYPE_SELL){continue;}
        if(all_buy_sell==2 && type==POSITION_TYPE_BUY){continue;}
        trade.PositionClose(ticket);
        if(trade.ResultRetcode()!=TRADE_RETCODE_DONE){
            Print(
                "Failed to close position:\n",
                "ticket:",(string)ticket,
                "result:",(string)trade.ResultRetcode(),":",trade.CheckResultRetcodeDescription()
            );
        }
    }
    return true;
}

// count open positions
bool CountOpenPositions(int &countBuy, int &countSell){
    countBuy=0;
    countSell=0;
    int total=PositionsTotal();
    for(int i=total-1; i>=0; i--){
        ulong ticket=PositionGetTicket(i);
        if(ticket<=0){Print("Failed to get position ticket"); return false;}
        if(!PositionSelectByTicket(ticket)){Print("Failed to select position"); return false;}
        long type;
        if(!PositionGetInteger(POSITION_TYPE,type)){Print("Failed to get position type"); return false;}
        if(type==POSITION_TYPE_BUY){countBuy++;}
        if(type==POSITION_TYPE_SELL){countSell++;}
    }
    return true;
}

// close positions
bool ClosePositions(int all_buy_sell){
    int total=PositionsTotal();
    for(int i=total-1; i>=0; i--){
        ulong ticket=PositionGetTicket(i);
        if(ticket<=0){Print("Failed to get position ticket"); return false;}
        long type;
        if(!PositionGetInteger(POSITION_TYPE,type)){Print("Failed to get position type"); return false;}
        if(all_buy_sell==1 && type==POSITION_TYPE_SELL){continue;}
        if(all_buy_sell==2 && type==POSITION_TYPE_BUY){continue;}
        trade.PositionClose(ticket);
        if(trade.ResultRetcode()!=TRADE_RETCODE_DONE){
            Print(
                "Failed to close position:\n",
                "ticket:",(string)ticket,
                "result:",(string)trade.ResultRetcode(),":",trade.CheckResultRetcodeDescription()
            );
        }
    }
    return true;
}