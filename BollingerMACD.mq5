//+------------------------------------------------------------------+
//|                                                BollingerMACD.mq5 |
//|                         Copyright 2021,Amirfarrokh Ghanbar Pour. |
//|                                           https://www.amirfg.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021,Amirfarrokh Ghanbar Pour."
#property link      "https://www.amirfg.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

CTrade ctrade; 

input double Total_Risk_Percent = 30.0,
             Trade_Risk_Percent = 3.0,
             Auto_TP_Percent    = 0.01;
             
input int    BB_Period     = 21,
             BB_Shift      = 0,
             BB_Deviation  = 2.000,
             
             MACD_Fast_EMA = 12 ,  
             MACD_Slow_EMA = 26,  
             MACD_Signal   = 9,
             
             ATR_Period    = 21;
             
input ENUM_APPLIED_PRICE MACD_Applied_Price = PRICE_CLOSE,
                         BB_Applied_Price   = PRICE_CLOSE;
                         
double MarginLevelRatio = 1.50,
       dSpread,
       UpBuffer[],
       LowBuffer[],
       MidBuffer[],
       diMACDMainBuffer[],
       diMACDSignalBuffer[],
       diATRBuffer[];
       
int    RiskFreePosNo = 0,
       iLotSize      = 100000,
       iBufferSize   = 5,
       iBBHandle,
       iMACDHandle,
       iATRHandle;
       
long   lLeverage = 0;    
//+------------------------------------------------------------------+
int OnInit()
  {
      if (_Period < PERIOD_M1 || _Period > PERIOD_MN1) return(INIT_PARAMETERS_INCORRECT);

      iBBHandle = iBands(_Symbol, _Period, BB_Period, BB_Shift, BB_Deviation, BB_Applied_Price);
      if (iBBHandle < 0) return(INIT_FAILED);

      iMACDHandle = iMACD(_Symbol, _Period, MACD_Fast_EMA, MACD_Slow_EMA, MACD_Signal, MACD_Applied_Price);
      if (iMACDHandle < 0) return(INIT_FAILED);

      iATRHandle = iATR(_Symbol, _Period, ATR_Period);
      if (iATRHandle < 0) return(INIT_FAILED);

      lLeverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
      return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
      if (iBBHandle!=INVALID_HANDLE)   IndicatorRelease(iBBHandle);   
      if (iMACDHandle!=INVALID_HANDLE) IndicatorRelease(iMACDHandle);   
      if (iATRHandle!=INVALID_HANDLE)  IndicatorRelease(iATRHandle);   
  }
//+------------------------------------------------------------------+
void OnTick()
  {
      long   lOrderType;
      double dOrderSL        = 0.0,
             dOrderOpenPrice = 0.0,
             SumMaxLose      = 0.0,
             dAsk            = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
             dBid            = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      bool   bTradeAllowed   = true;       
      
      if (CopyBuffer(iBBHandle, UPPER_BAND, 0, iBufferSize, UpBuffer) <= 0) return;
      ArraySetAsSeries(UpBuffer, true);
   
      if (CopyBuffer(iBBHandle, LOWER_BAND, 0, iBufferSize, LowBuffer) <= 0) return;
      ArraySetAsSeries(LowBuffer, true);
   
      if (CopyBuffer(iBBHandle, BASE_LINE, 0, iBufferSize, MidBuffer) <= 0) return;
      ArraySetAsSeries(MidBuffer, true);
      
      if(CopyBuffer(iMACDHandle, 0, 0, iBufferSize, diMACDMainBuffer) <= 0) return;
      ArraySetAsSeries(diMACDMainBuffer, true); 

      if(CopyBuffer(iMACDHandle, 1, 0, iBufferSize, diMACDSignalBuffer) <= 0) return;
      ArraySetAsSeries(diMACDSignalBuffer, true); 

      if(CopyBuffer(iATRHandle, 0, 0, iBufferSize, diATRBuffer) <= 0) return;
      ArraySetAsSeries(diATRBuffer, true); 

      RiskFreePosNo = 0;
      for (int iIndex1 = PositionsTotal() - 1; iIndex1 >= 0; iIndex1--)
      {
         if (PositionGetTicket(iIndex1) == 0) continue;
   
         lOrderType      = PositionGetInteger(POSITION_TYPE);
         dOrderSL        = PositionGetDouble(POSITION_SL);
         dOrderOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   
         if (lOrderType == ORDER_TYPE_BUY)
            SumMaxLose += (dOrderOpenPrice - dOrderSL) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * PositionGetDouble(POSITION_VOLUME) * iLotSize;
         else if (lOrderType == ORDER_TYPE_SELL)   
            SumMaxLose += (dOrderSL - dOrderOpenPrice) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * PositionGetDouble(POSITION_VOLUME) * iLotSize;
   
         if ((lOrderType == ORDER_TYPE_BUY && dOrderSL > dOrderOpenPrice) || (lOrderType == ORDER_TYPE_SELL && dOrderSL < dOrderOpenPrice))
               RiskFreePosNo++;

         string sSplitedComment[2];
         StringSplit(PositionGetString(POSITION_COMMENT), ';', sSplitedComment);
         if (PositionGetSymbol(iIndex1) != _Symbol || sSplitedComment[0] != EnumToString((ENUM_TIMEFRAMES)_Period)) continue;

         if ((lOrderType == ORDER_TYPE_BUY && dOrderSL <= dOrderOpenPrice) || (lOrderType == ORDER_TYPE_SELL && dOrderSL >= dOrderOpenPrice))
            {
               bTradeAllowed = false;
               break;
            }
      }   

      dSpread = dAsk - dBid;
      if (dSpread > 0.1 * (UpBuffer[0] - LowBuffer[0])) bTradeAllowed = false;
      
      if (bTradeAllowed &&
          PositionsTotal() - RiskFreePosNo < MathAbs(MathRound(Total_Risk_Percent/Trade_Risk_Percent)) && 
          (AccountInfoDouble(ACCOUNT_BALANCE) - SumMaxLose) > (AccountInfoDouble(ACCOUNT_MARGIN) * MarginLevelRatio))
         {
            if (((iClose(_Symbol, _Period, 2) <= MidBuffer[2] && iClose(_Symbol, _Period, 1) > MidBuffer[1]) || 
                 (iHigh(_Symbol, _Period, 2) <= LowBuffer[2] && iClose(_Symbol, _Period, 1) > LowBuffer[1]))// ||
                 /*(iClose(_Symbol, _Period, 1) > iOpen(_Symbol, _Period, 1)  && dBid > iClose(_Symbol, _Period, 1)))*/  &&
                dAsk < MidBuffer[0] + ((UpBuffer[0] - MidBuffer[0]) / 2))
                  Buy();

            if (((iClose(_Symbol, _Period, 2) >= MidBuffer[2] && iClose(_Symbol, _Period, 1) < MidBuffer[1]) || 
                 (iClose(_Symbol, _Period, 2) >= UpBuffer[2] && iClose(_Symbol, _Period, 1) < UpBuffer[1]))//   ||
                 /*(iClose(_Symbol, _Period, 1) < iOpen(_Symbol, _Period, 1) && dAsk < iClose(_Symbol, _Period, 1)))*/ &&
                dBid > MidBuffer[0] - ((MidBuffer[0] - LowBuffer[0]) / 2))
                  Sell();
         }

      SLTrailing();
      CheckClose();
  }
//+------------------------------------------------------------------+
bool Buy()
   {
      long   lSD  = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double dAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
             dBid = SymbolInfoDouble(_Symbol, SYMBOL_BID),
             dLotSize,
             dSL  = MathMin(LowBuffer[1] - diATRBuffer[0], iLow(_Symbol, _Period, 1) - dSpread);

      dLotSize = CalcLotSize((dAsk - dSL) * MathPow(10, lSD));
      return (ctrade.PositionOpen(_Symbol, ORDER_TYPE_BUY, dLotSize, dAsk, dSL, 0, EnumToString(_Period) + ";" + DoubleToString(NormalizeDouble(dBid - dSL, (int)lSD))));
   }
//+------------------------------------------------------------------+
bool Sell()
   {
      long   lSD  = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double dAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
             dBid = SymbolInfoDouble(_Symbol, SYMBOL_BID),
             dLotSize,
             dSL  = MathMax(UpBuffer[1] + diATRBuffer[0], iHigh(_Symbol, _Period, 1) + dSpread);

      dLotSize = CalcLotSize((dSL - dBid) * MathPow(10, lSD));
      return (ctrade.PositionOpen(_Symbol, ORDER_TYPE_SELL, dLotSize, dBid, dSL, 0, EnumToString(_Period) + ";" + DoubleToString(NormalizeDouble(dSL - dAsk, (int)lSD))));
   }
//+------------------------------------------------------------------+
double CalcLotSize(const double iSL)
   {
      double dLotSize     = 0.0,
             dRiskCapital = (Trade_Risk_Percent / 100) * AccountInfoDouble(ACCOUNT_BALANCE),
             dTickValue   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
             dMinLot      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
             dMaxLot      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
             dLotStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
      if (iSL * dTickValue > 0)
         {
            dLotSize = NormalizeDouble(dRiskCapital/(iSL * dTickValue), 2);
            if(dLotSize > (dRiskCapital * lLeverage) / iLotSize)
               dLotSize = (dRiskCapital * lLeverage) / iLotSize;
         }
      
      if (dLotSize < dMinLot)      return 0.00;
      else if (dLotSize > dMaxLot) return dMaxLot;
      else if (dLotStep > 0)       return (int(dLotSize/dLotStep) * dLotStep);
      else                         return 0.0;   
   }
//+------------------------------------------------------------------+
void SLTrailing()
   {
      double dOrderOpenPrice = 0.0,
             dOrderProfit    = 0.0,
             dOrderSL        = 0.0,
             dAsk            = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
             dBid            = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      long   lSD             = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
             iOrderType;
      ulong  ulTicket = 0;  
      
      for (int iIndex = PositionsTotal() - 1; iIndex >= 0; iIndex--)
         {
            ulTicket = PositionGetTicket(iIndex);
            if (ulTicket == 0) continue;
            
            string sSplitedComment[2];
            StringSplit(PositionGetString(POSITION_COMMENT), ';', sSplitedComment);

            if (PositionGetSymbol(iIndex) != _Symbol || sSplitedComment[0] != EnumToString((ENUM_TIMEFRAMES)_Period)) continue;
            
            iOrderType      = PositionGetInteger(POSITION_TYPE);
            dOrderOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            dOrderSL        = PositionGetDouble(POSITION_SL);

            double dNewSL  = dOrderSL;
            if (iOrderType == ORDER_TYPE_BUY)
               {
                  if (dOrderSL < dOrderOpenPrice) 
                     dNewSL = MathMin(dBid - diATRBuffer[0], dBid - StringToDouble(sSplitedComment[1])); //Trailing SL
                  else
                     dNewSL = MathMax(dBid - diATRBuffer[0], dBid - StringToDouble(sSplitedComment[1]));
                     
                  if (dNewSL > dOrderSL || dOrderSL == 0)
                     {
                        ctrade.PositionModify(ulTicket, dNewSL, dOrderProfit);
                        ctrade.ResultRetcode();   
                     }
               }

            if (iOrderType == ORDER_TYPE_SELL)
               {
                  if (dOrderSL > dOrderOpenPrice) 
                     dNewSL = MathMax(dAsk + diATRBuffer[0], dAsk + StringToDouble(sSplitedComment[1])); //Trailing SL
                  else   
                     dNewSL = MathMin(dAsk + diATRBuffer[0], dAsk + StringToDouble(sSplitedComment[1])); 
                  
                  if (dNewSL < dOrderSL || dOrderSL == 0)
                     {
                        ctrade.PositionModify(ulTicket, dNewSL, dOrderProfit);
                        ctrade.ResultRetcode();   
                     }
               }
         }
   }
//+------------------------------------------------------------------+
void CheckClose()
{
   int    iIndex1,
          iOrdersCount = OrdersTotal();
   
   ulong  ulTicket;
          
   double dOrderProfit = 0.0,
          SumProfit    = 0.0;
   
   for (iIndex1 = PositionsTotal() - 1; iIndex1 >= 0; iIndex1--)
   {
      ulTicket = PositionGetTicket(iIndex1);
      if (ulTicket == 0) continue;

      dOrderProfit = PositionGetDouble(POSITION_PROFIT);

      if (dOrderProfit > AccountInfoDouble(ACCOUNT_BALANCE) * Auto_TP_Percent)
         ctrade.PositionClose(ulTicket);
      else
         SumProfit += dOrderProfit;    
   }
   
   if (SumProfit > AccountInfoDouble(ACCOUNT_BALANCE) * Auto_TP_Percent * 5)   
      {
         for (iIndex1 = PositionsTotal() - 1; iIndex1 >= 0; iIndex1--)
         {
            ulTicket = PositionGetTicket(iIndex1);
            if (ulTicket == 0) continue;
            ctrade.PositionClose(ulTicket);
         }
      }
}
//+------------------------------------------------------------------+
