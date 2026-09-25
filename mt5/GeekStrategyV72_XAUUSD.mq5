//+------------------------------------------------------------------+
//|                                     GeekStrategyV72_XAUUSD.mq5   |
//|  Port a MetaTrader 5 de GeekStrategyV72.cs (NinjaTrader 8)        |
//|  Solo opera XAUUSD (oro spot).                                    |
//+------------------------------------------------------------------+
//  MOTOR (identico al de V7.2 / "geekstrategy2.0"):
//     - Base  : ALMA(close, BasisLen, Offset, Sigma) suavizada por EMA(BasisSmooth)
//     - Vol   : MAD(close, VolLen) suavizada por EMA(VolSmooth)
//     - Mult  : adaptativo = Min + (Max-Min) * percentrank(vol, RankLookback)
//     - Bandas: upper = base + mult*vol ; lower = base - mult*vol
//     - Flip  : SuperTrend sobre esas bandas adaptativas
//     - BUY = giro a alcista ; SELL = giro a bajista.
//
//  DIFERENCIAS CON LA VERSION NINJATRADER:
//   - Todas las distancias van en DOLARES DE PRECIO del oro (1.00 = $1 en la
//     cotizacion), no en ticks. Asi funciona igual con brokers de 2 o 3
//     decimales.
//   - Tamano de posicion por % de riesgo (o lotes fijos).
//   - Filtros propios del oro: spread maximo, bloqueo del rollover diario y
//     cierre antes del fin de semana.
//   - Limites de riesgo en % del equity de la cuenta.
//   - El motor se calcula en InpTimeframe (M15 por defecto), sin importar el
//     marco del grafico donde pongas el EA.
//   - Sin nube ni velas coloreadas (un EA de MT5 no tiene buffers de
//     indicador). La base y las bandas se dibujan con segmentos.
//+------------------------------------------------------------------+
#property copyright   "GeekStrategy"
#property version     "7.20"
#property description "GeekStrategy V7.2 - motor ALMA MAD adaptativo - solo XAUUSD M15"

#include <Trade\Trade.mqh>

#define PFX "GK72_"

//--- enums ---------------------------------------------------------
enum ENUM_GEEK_MODE
  {
   GEEK_SEMIAUTO = 0,   // SemiAuto: solo senales y alertas
   GEEK_FULLAUTO = 1    // FullAuto: el EA opera solo
  };

enum ENUM_GEEK_EXIT
  {
   GEEK_EXIT_FIXED = 0, // Fijo en $ de precio
   GEEK_EXIT_ATR   = 1, // Stop = N x ATR
   GEEK_EXIT_VOL   = 2  // Stop = N x MAD del motor
  };

enum ENUM_GEEK_LOTS
  {
   GEEK_LOTS_FIXED = 0, // Lotes fijos
   GEEK_LOTS_RISK  = 1  // % del equity arriesgado por trade
  };

//--- inputs --------------------------------------------------------
input group "0. Simbolo y marco"
input string          InpSymbolFilter    = "XAUUSD";    // Simbolo permitido (texto que debe contener)
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_M15;  // Marco de calculo del motor
input long            InpMagic           = 720072;      // Numero magico
input int             InpHistoryBars     = 3000;        // Velas de historial para el motor

input group "1. Base (ALMA)"
input int    InpBasisLen        = 34;     // Longitud Base (ALMA)
input double InpAlmaOffset      = 0.65;   // ALMA Offset
input double InpAlmaSigma       = 20.0;   // ALMA Sigma
input int    InpBasisSmooth     = 4;      // Suavizado Base (EMA)

input group "2. Volatilidad (MAD)"
input int    InpVolLen          = 5;      // Longitud Vol (MAD)
input int    InpVolSmooth       = 5;      // Suavizado Vol (EMA)
input double InpMinMult         = 0.8;    // Multiplicador Min
input double InpMaxMult         = 1.8;    // Multiplicador Max
input int    InpVolRankLookback = 100;    // Lookback Rank Vol
input bool   InpUseVolRegime    = true;   // Filtrar por regimen de vol (no operar lateral)
input double InpMinVolRank      = 0.20;   // Rank minimo de vol (0-1)

input group "3. Ejecucion"
input ENUM_GEEK_MODE InpMode         = GEEK_FULLAUTO;   // Modo de ejecucion
input ENUM_GEEK_LOTS InpLotMode      = GEEK_LOTS_RISK;  // Tamano de posicion
input double         InpRiskPct      = 0.5;             // Riesgo por trade (% equity)
input double         InpFixedLots    = 0.01;            // Lotes fijos
input double         InpMaxLots      = 1.0;             // Maximo de lotes por trade
input bool           InpAllowReverse = true;            // Revertir en cada giro
input int            InpSlippagePts  = 50;              // Desviacion maxima (points)

input group "4. Salidas (en $ de precio del oro)"
input ENUM_GEEK_EXIT InpExitSizing     = GEEK_EXIT_ATR; // Dimensionado de salidas
input double         InpFixedStopUSD   = 8.0;           // Stop fijo ($)
input double         InpFixedTargetUSD = 16.0;          // Objetivo fijo ($)
input int            InpAtrPeriod      = 14;            // Periodo ATR
input double         InpStopAtrMult    = 1.8;           // Stop = N x ATR
input double         InpStopVolMult    = 2.5;           // Stop = N x Vol (MAD)
input double         InpRewardRisk     = 2.0;           // Ratio objetivo:riesgo (ATR/Vol)
input double         InpMinStopUSD     = 3.0;           // Stop minimo ($)
input double         InpMaxStopUSD     = 35.0;          // Stop maximo ($)
input bool           InpUseTrail       = true;          // Trailing adaptativo (linea SuperTrend)
input double         InpTrailOffsetUSD = 0.50;          // Holgura del trailing ($)
input double         InpTrailStartR    = 1.0;           // Activar trailing tras N R de ganancia (0 = desde el inicio)

input group "5. Horario y spread (hora del servidor)"
input bool   InpBlockRollover   = true;   // Bloquear entradas en el rollover diario
input int    InpBlockStartHour  = 23;     // Bloqueo desde (hora)
input int    InpBlockEndHour    = 1;      // Bloqueo hasta (hora)
input bool   InpFridayClose     = true;   // Cerrar y no entrar el viernes tarde
input int    InpFridayCloseHour = 22;     // Hora de corte del viernes
input double InpMaxSpreadUSD    = 0.50;   // Spread maximo para entrar ($)

input group "6. Riesgo de cuenta (0 = apagado)"
input double InpDailyLossPct    = 2.0;    // Perdida diaria max (% equity)
input double InpDailyProfitPct  = 0.0;    // Objetivo diario (% equity)
input double InpTrailingDDPct   = 0.0;    // Drawdown max desde el pico (% equity)
input double InpEquityFloor     = 0.0;    // Detener si equity <= (dinero)

input group "7. Filtro de tendencia (marco mayor)"
input bool            InpUseHTF    = true;       // Usar filtro de tendencia HTF
input ENUM_TIMEFRAMES InpHTF       = PERIOD_H1;  // Marco mayor
input int             InpHTFEmaLen = 50;         // EMA del marco mayor

input group "8. Estetica"
input bool             InpShowBasis    = true;               // Dibujar linea base
input bool             InpShowBands    = true;               // Dibujar bandas
input bool             InpShowSignals  = true;               // Flechas BUY/SELL
input int              InpDrawBars     = 300;                // Velas dibujadas
input bool             InpShowPanel    = true;               // Panel de informacion
input ENUM_BASE_CORNER InpPanelCorner  = CORNER_RIGHT_UPPER; // Posicion del panel
input int              InpPanelFont    = 9;                  // Tamano de letra del panel

input group "9. Alertas"
input bool   InpSoundAlerts  = true;         // Sonido en la senal (BUY/SELL)
input bool   InpEntryAlert   = true;         // Alerta ENTRY al abrir la vela
input int    InpEntryBarsAfter = 1;          // ENTRY: velas despues de la senal
input string InpBuySound     = "alert.wav";  // Sonido BUY
input string InpSellSound    = "alert2.wav"; // Sonido SELL
input string InpEntrySound   = "ok.wav";     // Sonido ENTRY
input bool   InpPush         = false;        // Notificacion push al movil

//--- motor ---------------------------------------------------------
datetime g_time[];
double   g_high[], g_low[], g_close[];
double   g_dev[], g_basis[], g_vol[], g_stop[], g_rank[], g_mult[], g_upper[], g_lower[];
int      g_trend[];
int      g_n = 0;
int      g_minBars;
double   g_almaW[];
double   g_almaNorm;

//--- estado --------------------------------------------------------
CTrade          trade;
ENUM_TIMEFRAMES g_tf;
int      g_atrH = INVALID_HANDLE;
int      g_htfH = INVALID_HANDLE;
datetime g_lastTime    = 0;   // ultima vela CERRADA procesada
datetime g_lastBarOpen = 0;   // apertura de la vela en curso
bool     g_needRebuild = false;
bool     g_draw        = true;
bool     g_live        = true;

// riesgo
datetime g_day = 0;
double   g_dayStartEq = 0, g_peakEq = 0;
bool     g_dayHalted = false, g_hardHalted = false;

// salidas calculadas en la senal
double   g_pendingSl = 0, g_pendingTp = 0;

// armado de la entrada (alerta ENTRY / trade virtual)
bool     g_armed = false, g_armLong = false;
int      g_armBarsLeft = 0;

// trade en curso (real en FullAuto, virtual en SemiAuto)
bool     g_tradeActive = false, g_tradeLong = false;
bool     g_trailOn = false;     // el trailing ya se activo en este trade
double   g_tradeEntry = 0, g_tradeTp = 0, g_tradeSl = 0, g_tradeSlInit = 0, g_tradeLots = 0;
datetime g_tradeTime = 0;
long     g_tradePosId = 0;
string   g_tradeResult = "";
string   g_closeReason = "";

// panel
int      g_panelLines = 0;
uint     g_lastPanelMs = 0;

//+------------------------------------------------------------------+
//| Utilidades                                                       |
//+------------------------------------------------------------------+
double TickSize()
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return ts > 0 ? ts : _Point;
  }

double NormPrice(double p)
  {
   double ts = TickSize();
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
  }

// dinero por cada $1 de movimiento del precio con 1 lote
double ValuePerUnit()
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0) tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   return tv / TickSize();
  }

double Spread()
  {
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk)) return 0;
   return tk.ask - tk.bid;
  }

// distancia minima permitida por el broker para SL/TP
double MinStopGap()
  {
   long lvl = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                      SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   return lvl * _Point + Spread() + TickSize();
  }

string Money(double v)
  {
   return (v >= 0 ? "+" : "") + DoubleToString(v, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);
  }

string TfName(ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return s;
  }

void Notify(string msg, string sound)
  {
   if(!g_live) return;
   Alert(msg);
   if(sound != "") PlaySound(sound);
   if(InpPush) SendNotification(msg);
  }

//+------------------------------------------------------------------+
//| Posiciones propias                                               |
//+------------------------------------------------------------------+
int MyPosition(ulong &ticket)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket = t;
      return PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
     }
   ticket = 0;
   return 0;
  }

void CloseAllMine(string reason)
  {
   g_closeReason = reason;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(!trade.PositionClose(t, InpSlippagePts))
         PrintFormat("GeekV72: no se pudo cerrar #%I64u (%s): %d", t, reason, trade.ResultRetcode());
     }
  }

//+------------------------------------------------------------------+
//| MOTOR                                                            |
//+------------------------------------------------------------------+
void EngineResize(int size)
  {
   ArrayResize(g_time,  size, 5000);
   ArrayResize(g_high,  size, 5000);
   ArrayResize(g_low,   size, 5000);
   ArrayResize(g_close, size, 5000);
   ArrayResize(g_dev,   size, 5000);
   ArrayResize(g_basis, size, 5000);
   ArrayResize(g_vol,   size, 5000);
   ArrayResize(g_stop,  size, 5000);
   ArrayResize(g_rank,  size, 5000);
   ArrayResize(g_mult,  size, 5000);
   ArrayResize(g_upper, size, 5000);
   ArrayResize(g_lower, size, 5000);
   ArrayResize(g_trend, size, 5000);
  }

// Anade una vela cerrada (orden cronologico) y calcula el motor sobre ella.
void EngineAppend(datetime t, double h, double l, double c)
  {
   int k = g_n;
   EngineResize(k + 1);
   g_n = k + 1;

   g_time[k] = t; g_high[k] = h; g_low[k] = l; g_close[k] = c;
   g_dev[k] = 0; g_basis[k] = 0; g_vol[k] = 0; g_stop[k] = 0;
   g_rank[k] = 0; g_mult[k] = 0; g_upper[k] = 0; g_lower[k] = 0;
   g_trend[k] = 0;

   // |close - sma(close, VolLen)|
   if(k >= InpVolLen - 1)
     {
      double sumC = 0;
      for(int i = 0; i < InpVolLen; i++) sumC += g_close[k - i];
      g_dev[k] = MathAbs(c - sumC / InpVolLen);
     }

   if(k < g_minBars) return;
   bool first = (k == g_minBars);

   // ---- Base ALMA (mismo indexado que pine) ----
   double almaSum = 0;
   for(int i = 0; i < InpBasisLen; i++)
      almaSum += g_close[k - (InpBasisLen - 1 - i)] * g_almaW[i];
   double basisRaw = almaSum / g_almaNorm;
   double aB = 2.0 / (InpBasisSmooth + 1);
   g_basis[k] = first ? basisRaw : g_basis[k - 1] + aB * (basisRaw - g_basis[k - 1]);
   double basis = g_basis[k];

   // ---- MAD ----
   double sumD = 0;
   for(int i = 0; i < InpVolLen; i++) sumD += g_dev[k - i];
   double volRaw = sumD / InpVolLen;
   double aV = 2.0 / (InpVolSmooth + 1);
   g_vol[k] = first ? volRaw : g_vol[k - 1] + aV * (volRaw - g_vol[k - 1]);
   double vol = g_vol[k];

   // ---- percentrank(vol, lookback) ----
   int lb = MathMin(InpVolRankLookback, k - g_minBars);
   double rank = 0;
   if(lb > 0)
     {
      int cnt = 0;
      for(int i = 1; i <= lb; i++)
         if(g_vol[k - i] < vol) cnt++;
      rank = (double)cnt / lb;
     }
   double mult  = InpMinMult + (InpMaxMult - InpMinMult) * rank;
   double upper = basis + mult * vol;
   double lower = basis - mult * vol;
   g_rank[k] = rank; g_mult[k] = mult; g_upper[k] = upper; g_lower[k] = lower;

   // ---- SuperTrend sobre las bandas adaptativas ----
   int    prevTrend = first ? 1 : g_trend[k - 1];
   double prevStop  = first ? lower : g_stop[k - 1];
   int    curTrend  = prevTrend;
   double curStop;
   if(prevTrend == 1)
     {
      curStop = MathMax(lower, prevStop);
      if(c < curStop) { curTrend = -1; curStop = upper; }
     }
   else
     {
      curStop = MathMin(upper, prevStop);
      if(c > curStop) { curTrend = 1; curStop = lower; }
     }
   g_trend[k] = curTrend;
   g_stop[k]  = curStop;
  }

bool EngineRebuild()
  {
   MqlRates r[];
   int need = MathMax(InpHistoryBars, g_minBars + InpVolRankLookback + 50);
   int got  = CopyRates(_Symbol, g_tf, 1, need, r);   // r[0] = la mas antigua
   if(got < g_minBars + InpVolRankLookback + 2)
      return false;

   g_n = 0;
   EngineResize(0);
   ObjectsDeleteAll(0, PFX + "B");
   ObjectsDeleteAll(0, PFX + "U");
   ObjectsDeleteAll(0, PFX + "L");
   ObjectsDeleteAll(0, PFX + "S");

   for(int i = 0; i < got; i++)
      EngineAppend(r[i].time, r[i].high, r[i].low, r[i].close);

   g_lastTime    = r[got - 1].time;
   g_lastBarOpen = iTime(_Symbol, g_tf, 0);

   if(g_draw)
      for(int k = MathMax(g_minBars + 1, g_n - InpDrawBars); k < g_n; k++)
         DrawEngineBar(k);
   return true;
  }

// Procesa las velas cerradas nuevas. true = hay al menos una nueva.
bool EngineUpdate()
  {
   MqlRates r[];
   int got = CopyRates(_Symbol, g_tf, 1, 100, r);
   if(got <= 0) return false;
   if(r[0].time > g_lastTime)          // hueco grande (desconexion): recalcular todo
     {
      if(!EngineRebuild()) { g_needRebuild = true; return false; }
      return true;
     }
   bool added = false;
   for(int i = 0; i < got; i++)
     {
      if(r[i].time <= g_lastTime) continue;
      EngineAppend(r[i].time, r[i].high, r[i].low, r[i].close);
      g_lastTime = r[i].time;
      added = true;
      if(g_draw) DrawEngineBar(g_n - 1);
     }
   return added;
  }

//+------------------------------------------------------------------+
//| Dibujo                                                           |
//+------------------------------------------------------------------+
void Segment(string name, datetime t1, double p1, datetime t2, double p2,
             color clr, ENUM_LINE_STYLE style, int width)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }

void DrawEngineBar(int k)
  {
   if(k < 1 || g_trend[k - 1] == 0 || g_trend[k] == 0) return;

   string id = IntegerToString((long)g_time[k]);
   if(InpShowBasis)
      Segment(PFX + "B" + id, g_time[k - 1], g_basis[k - 1], g_time[k], g_basis[k],
              g_trend[k] == 1 ? clrLimeGreen : clrRed, STYLE_SOLID, 2);
   if(InpShowBands)
     {
      Segment(PFX + "U" + id, g_time[k - 1], g_upper[k - 1], g_time[k], g_upper[k], clrDimGray, STYLE_DOT, 1);
      Segment(PFX + "L" + id, g_time[k - 1], g_lower[k - 1], g_time[k], g_lower[k], clrDimGray, STYLE_DOT, 1);
     }

   if(InpShowSignals && g_trend[k] != g_trend[k - 1])
     {
      string nm = PFX + "S" + id;
      bool up = g_trend[k] == 1;
      if(ObjectFind(0, nm) < 0)
         ObjectCreate(0, nm, OBJ_ARROW, 0, g_time[k], up ? g_low[k] : g_high[k]);
      ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, up ? 233 : 234);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, up ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, up ? clrLimeGreen : clrRed);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetString(0, nm, OBJPROP_TOOLTIP, up ? "Geek BUY" : "Geek SELL");
     }

   // borrar lo que sale de la ventana dibujada
   int old = k - InpDrawBars;
   if(old >= 0)
     {
      string oid = IntegerToString((long)g_time[old]);
      ObjectDelete(0, PFX + "B" + oid);
      ObjectDelete(0, PFX + "U" + oid);
      ObjectDelete(0, PFX + "L" + oid);
      ObjectDelete(0, PFX + "S" + oid);
     }
  }

//+------------------------------------------------------------------+
//| Salidas                                                          |
//+------------------------------------------------------------------+
double ComputeStopDist(double vol)
  {
   double raw;
   switch(InpExitSizing)
     {
      case GEEK_EXIT_ATR:
        {
         double b[];
         if(g_atrH == INVALID_HANDLE || CopyBuffer(g_atrH, 0, 1, 1, b) != 1 || b[0] <= 0)
            return InpFixedStopUSD;
         raw = b[0] * InpStopAtrMult;
         break;
        }
      case GEEK_EXIT_VOL:
         if(vol <= 0) return InpFixedStopUSD;
         raw = vol * InpStopVolMult;
         break;
      default:
         return InpFixedStopUSD;
     }
   return MathMax(InpMinStopUSD, MathMin(InpMaxStopUSD, raw));
  }

double ComputeTargetDist(double stopDist)
  {
   if(InpExitSizing == GEEK_EXIT_FIXED) return InpFixedTargetUSD;
   return stopDist * InpRewardRisk;
  }

double CalcLots(double slDist, bool isLong, double price)
  {
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0) vstep = 0.01;

   double lots = InpFixedLots;
   if(InpLotMode == GEEK_LOTS_RISK)
     {
      double lossPerLot = slDist * ValuePerUnit();
      if(lossPerLot <= 0) return 0;
      lots = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 / lossPerLot;
     }

   // no pedir mas de lo que permite el margen libre
   double m;
   if(OrderCalcMargin(isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, price, m) && m > 0)
      lots = MathMin(lots, AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9 / m);

   lots = MathMin(lots, MathMin(vmax, InpMaxLots));
   lots = MathFloor(lots / vstep + 1e-9) * vstep;
   if(lots < vmin)
     {
      if(InpLotMode == GEEK_LOTS_RISK && vmin <= InpMaxLots)
        {
         PrintFormat("GeekV72: el riesgo pedido da menos del lote minimo; se usa %.2f lotes (riesgo real %.2f).",
                     vmin, vmin * slDist * ValuePerUnit());
         lots = vmin;
        }
      else
         return 0;
     }
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| Trade: marcas / apertura / trailing                              |
//+------------------------------------------------------------------+
void SetTradeMarks(bool isLong, double entry, double slPx, double tpPx, double lots)
  {
   g_tradeLong   = isLong;
   g_tradeEntry  = entry;
   g_tradeSl     = slPx;
   g_tradeSlInit = slPx;
   g_tradeTp     = tpPx;
   g_tradeLots   = lots;
   g_tradeTime   = iTime(_Symbol, g_tf, 0);
   g_tradeActive = true;
   g_tradeResult = "";
   g_closeReason = "";
   g_trailOn     = false;
  }

bool OpenTrade(bool isLong)
  {
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk)) return false;
   double price = isLong ? tk.ask : tk.bid;
   double gap   = MinStopGap();
   double sl    = MathMax(g_pendingSl, gap);
   double tp    = MathMax(g_pendingTp, gap);
   double slPx  = NormPrice(isLong ? price - sl : price + sl);
   double tpPx  = NormPrice(isLong ? price + tp : price - tp);
   double lots  = CalcLots(sl, isLong, price);
   if(lots <= 0) { Print("GeekV72: volumen 0 (margen o lote minimo). Entrada omitida."); return false; }

   bool ok = isLong ? trade.Buy(lots, _Symbol, 0, slPx, tpPx, "GeekLong")
                    : trade.Sell(lots, _Symbol, 0, slPx, tpPx, "GeekShort");
   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
     {
      PrintFormat("GeekV72: fallo la entrada %s: %u %s", isLong ? "LONG" : "SHORT", rc, trade.ResultRetcodeDescription());
      return false;
     }

   double fill = trade.ResultPrice();
   SetTradeMarks(isLong, fill > 0 ? fill : price, slPx, tpPx, lots);

   ulong t;
   g_tradePosId = MyPosition(t) != 0 ? PositionGetInteger(POSITION_IDENTIFIER) : 0;
   return true;
  }

// Arrastra el stop hacia la linea SuperTrend del motor. Solo aprieta.
void UpdateAdaptiveTrail(double engineStop)
  {
   if(!InpUseTrail || g_tradeSl <= 0) return;

   bool   real = (InpMode == GEEK_FULLAUTO);
   ulong  ticket = 0;
   double refPx, gap;
   if(real)
     {
      if(MyPosition(ticket) == 0) return;
      MqlTick tk;
      if(!SymbolInfoTick(_Symbol, tk)) return;
      refPx = g_tradeLong ? tk.bid : tk.ask;
      gap   = MinStopGap();
     }
   else
     {
      refPx = g_close[g_n - 1];
      gap   = TickSize();
     }

   // El trailing espera a que el trade vaya InpTrailStartR a favor. Asi el
   // stop inicial por ATR tiene tiempo de trabajar antes de apretarse.
   if(!g_trailOn)
     {
      double riskD = MathAbs(g_tradeEntry - g_tradeSlInit);
      double runR  = riskD > 0 ? (g_tradeLong ? refPx - g_tradeEntry : g_tradeEntry - refPx) / riskD : 0;
      if(runR < InpTrailStartR) return;
      g_trailOn = true;
     }

   double cand = g_tradeLong ? engineStop - InpTrailOffsetUSD : engineStop + InpTrailOffsetUSD;
   double next;
   if(g_tradeLong)
     {
      next = MathMax(g_tradeSl, cand);
      next = MathMin(next, refPx - gap);
      if(next <= g_tradeSl + TickSize() / 2) return;
     }
   else
     {
      next = MathMin(g_tradeSl, cand);
      next = MathMax(next, refPx + gap);
      if(next >= g_tradeSl - TickSize() / 2) return;
     }
   next = NormPrice(next);

   if(real)
     {
      double tp = PositionGetDouble(POSITION_TP);
      if(!trade.PositionModify(ticket, next, tp))
        {
         PrintFormat("GeekV72: no se pudo mover el trailing: %u", trade.ResultRetcode());
         return;
        }
     }
   g_tradeSl = next;
  }

// SemiAuto: seguimiento del trade virtual con High/Low de la vela cerrada.
void CheckVirtualOutcome(bool flipUp, bool flipDown)
  {
   if(InpMode != GEEK_SEMIAUTO || !g_tradeActive) return;
   int k = g_n - 1;
   if(g_time[k] < g_tradeTime) return;   // la vela de entrada aun no ha cerrado
   if(g_tradeLong)
     {
      if(g_low[k] <= g_tradeSl)       { g_tradeActive = false; g_tradeResult = "SL"; }
      else if(g_high[k] >= g_tradeTp) { g_tradeActive = false; g_tradeResult = "TP"; }
      else if(flipDown)               { g_tradeActive = false; g_tradeResult = "FLIP"; }
     }
   else
     {
      if(g_high[k] >= g_tradeSl)      { g_tradeActive = false; g_tradeResult = "SL"; }
      else if(g_low[k] <= g_tradeTp)  { g_tradeActive = false; g_tradeResult = "TP"; }
      else if(flipUp)                 { g_tradeActive = false; g_tradeResult = "FLIP"; }
     }
  }

//+------------------------------------------------------------------+
//| Armado de la entrada (alerta ENTRY / trade virtual)               |
//+------------------------------------------------------------------+
void FireEntry()
  {
   g_armed = false;
   if(InpEntryAlert)
      Notify("Geek XAUUSD: ENTRY " + (g_armLong ? "LONG" : "SHORT"), InpEntrySound);

   if(InpMode == GEEK_SEMIAUTO)
     {
      double entry = iOpen(_Symbol, g_tf, 0);
      if(entry <= 0) return;
      double slPx = NormPrice(g_armLong ? entry - g_pendingSl : entry + g_pendingSl);
      double tpPx = NormPrice(g_armLong ? entry + g_pendingTp : entry - g_pendingTp);
      SetTradeMarks(g_armLong, entry, slPx, tpPx, CalcLots(g_pendingSl, g_armLong, entry));
     }
  }

void ArmEntry(bool isLong)
  {
   g_armed       = true;
   g_armLong     = isLong;
   g_armBarsLeft = MathMax(1, InpEntryBarsAfter) - 1;
   if(g_armBarsLeft == 0) FireEntry();
  }

void TickArmed()
  {
   if(!g_armed) return;
   g_armBarsLeft--;
   if(g_armBarsLeft <= 0) FireEntry();
  }

//+------------------------------------------------------------------+
//| Filtros                                                          |
//+------------------------------------------------------------------+
bool IsBlockedTime(string &why)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpFridayClose && dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour)
     { why = "CIERRE VIERNES"; return true; }
   if(InpBlockRollover && InpBlockStartHour != InpBlockEndHour)
     {
      bool b = InpBlockStartHour < InpBlockEndHour
               ? (dt.hour >= InpBlockStartHour && dt.hour < InpBlockEndHour)
               : (dt.hour >= InpBlockStartHour || dt.hour < InpBlockEndHour);
      if(b) { why = "ROLLOVER"; return true; }
     }
   why = "OK";
   return false;
  }

// 1 = alcista, -1 = bajista, 0 = sin datos / plano
int HtfDir()
  {
   if(g_htfH == INVALID_HANDLE) return 0;
   if(Bars(_Symbol, InpHTF) <= InpHTFEmaLen + 1) return 0;
   double e[];
   if(CopyBuffer(g_htfH, 0, 1, 1, e) != 1) return 0;
   double c = iClose(_Symbol, InpHTF, 1);
   if(c <= 0) return 0;
   return c > e[0] ? 1 : (c < e[0] ? -1 : 0);
  }

//+------------------------------------------------------------------+
//| Riesgo de cuenta (se evalua en cada tick)                        |
//+------------------------------------------------------------------+
void EvaluateRisk()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime day = StructToTime(dt);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(day != g_day)
     {
      g_day = day;
      g_dayStartEq = eq;
      g_dayHalted = false;
     }
   if(eq > g_peakEq) g_peakEq = eq;

   bool wasHalted = g_dayHalted || g_hardHalted;
   double dayPnl = eq - g_dayStartEq;
   if(InpDailyLossPct > 0 && dayPnl <= -g_dayStartEq * InpDailyLossPct / 100.0)   g_dayHalted = true;
   if(InpDailyProfitPct > 0 && dayPnl >= g_dayStartEq * InpDailyProfitPct / 100.0) g_dayHalted = true;
   if(InpTrailingDDPct > 0 && eq <= g_peakEq * (1.0 - InpTrailingDDPct / 100.0))    g_hardHalted = true;
   if(InpEquityFloor > 0 && eq <= InpEquityFloor)                                  g_hardHalted = true;

   if(!wasHalted && (g_dayHalted || g_hardHalted))
      PrintFormat("GeekV72: limite de riesgo alcanzado (equity %.2f, dia %.2f). %s",
                  eq, dayPnl, g_hardHalted ? "Detenida hasta reiniciar el EA." : "Detenida hasta manana.");

   ulong t;
   if((g_dayHalted || g_hardHalted) && MyPosition(t) != 0)
      CloseAllMine("RIESGO");
  }

//+------------------------------------------------------------------+
//| Logica por vela cerrada                                          |
//+------------------------------------------------------------------+
void OnNewClosedBar()
  {
   int k = g_n - 1;
   if(k - 1 < g_minBars || g_trend[k - 1] == 0) return;

   int  curTrend  = g_trend[k];
   int  prevTrend = g_trend[k - 1];
   bool flipUp    = curTrend ==  1 && prevTrend == -1;
   bool flipDown  = curTrend == -1 && prevTrend ==  1;

   // --- estado del trade real
   ulong ticket;
   int posDir = MyPosition(ticket);
   if(InpMode == GEEK_FULLAUTO && posDir == 0 && g_tradeActive)
     {
      g_tradeActive = false;
      if(g_tradeResult == "") g_tradeResult = "CERRADO";
     }

   // --- trailing + trade virtual
   if(g_tradeActive)
     {
      UpdateAdaptiveTrail(g_stop[k]);
      CheckVirtualOutcome(flipUp, flipDown);
     }

   TickArmed();

   // --- filtros
   bool canEnter = !g_dayHalted && !g_hardHalted;
   if(InpUseVolRegime && g_rank[k] < InpMinVolRank) canEnter = false;

   bool longOk = true, shortOk = true;
   if(InpUseHTF)
     {
      int d = HtfDir();
      longOk  = d ==  1;
      shortOk = d == -1;
     }
   string why;
   bool windowOk = !IsBlockedTime(why) && (InpMaxSpreadUSD <= 0 || Spread() <= InpMaxSpreadUSD);

   bool canLong  = canEnter && longOk;
   bool canShort = canEnter && shortOk;

   if(flipUp || flipDown)
     {
      g_pendingSl = ComputeStopDist(g_vol[k]);
      g_pendingTp = ComputeTargetDist(g_pendingSl);
     }

   if(flipUp)
     {
      if(InpSoundAlerts) Notify("Geek XAUUSD: senal BUY", InpBuySound);
      if(canLong && windowOk && (posDir == 0 || (posDir == -1 && InpAllowReverse)))
         ArmEntry(true);
     }
   else if(flipDown)
     {
      if(InpSoundAlerts) Notify("Geek XAUUSD: senal SELL", InpSellSound);
      if(canShort && windowOk && (posDir == 0 || (posDir == 1 && InpAllowReverse)))
         ArmEntry(false);
     }

   // --- ordenes (misma logica que la version NinjaTrader)
   if(InpMode == GEEK_FULLAUTO)
     {
      if(flipUp)
        {
         if(posDir == 0)
           { if(canLong && windowOk) OpenTrade(true); }
         else if(posDir == -1)
           {
            if(InpAllowReverse && canLong)
              {
               CloseAllMine("FLIP");
               if(windowOk) OpenTrade(true);
              }
            else if(canEnter || InpUseHTF)
               CloseAllMine("FLIP");
           }
        }
      else if(flipDown)
        {
         if(posDir == 0)
           { if(canShort && windowOk) OpenTrade(false); }
         else if(posDir == 1)
           {
            if(InpAllowReverse && canShort)
              {
               CloseAllMine("FLIP");
               if(windowOk) OpenTrade(false);
              }
            else if(canEnter || InpUseHTF)
               CloseAllMine("FLIP");
           }
        }
     }

   DrawPanel();
  }

//+------------------------------------------------------------------+
//| Panel fijo                                                       |
//+------------------------------------------------------------------+
void AddLine(string &arr[], string s)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = s;
  }

void DrawPanel()
  {
   if(!InpShowPanel || !g_draw || g_n == 0) return;
   int k = g_n - 1;

   string L[];
   AddLine(L, "GEEK V7.2  " + _Symbol + "  " + TfName(g_tf));
   AddLine(L, "Modo      : " + (InpMode == GEEK_FULLAUTO ? "FullAuto" : "SemiAuto"));
   AddLine(L, "Tendencia : " + (g_trend[k] == 1 ? "ALCISTA" : "BAJISTA"));
   AddLine(L, "Vol rank  : " + DoubleToString(g_rank[k] * 100, 0) + "%   Mult " + DoubleToString(g_mult[k], 2));
   if(InpUseVolRegime)
      AddLine(L, "Regimen   : " + (g_rank[k] >= InpMinVolRank ? "OK" : "BLOQUEADO (lateral)"));
   if(InpUseHTF)
     {
      int d = HtfDir();
      AddLine(L, "HTF " + TfName(InpHTF) + "   : " + (d == 1 ? "ALCISTA" : (d == -1 ? "BAJISTA" : "sin datos")));
     }
   string why;
   IsBlockedTime(why);
   AddLine(L, "Horario   : " + why + "   Spread " + DoubleToString(Spread(), 2));
   AddLine(L, "P&L dia   : " + Money(AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEq));
   if(g_dayHalted || g_hardHalted)
      AddLine(L, "RIESGO    : DETENIDA");
   AddLine(L, "------------------------------------");

   double vpu = ValuePerUnit();
   if(g_tradeEntry <= 0)
      AddLine(L, "Sin trade. Esperando senal.");
   else
     {
      double stopD   = MathAbs(g_tradeEntry - g_tradeSlInit);
      double targetD = MathAbs(g_tradeTp - g_tradeEntry);
      double curSlD  = MathAbs(g_tradeEntry - g_tradeSl);
      string tag = g_tradeLong ? "LONG" : "SHORT";
      if(InpMode == GEEK_SEMIAUTO) tag += " (virtual)";
      AddLine(L, tag + "   " + DoubleToString(g_tradeLots, 2) + " lotes");
      AddLine(L, "Entrada : " + DoubleToString(g_tradeEntry, _Digits));
      AddLine(L, "TP      : " + DoubleToString(g_tradeTp, _Digits) + "  +" + DoubleToString(targetD, 2)
              + "  " + Money(targetD * vpu * g_tradeLots));
      AddLine(L, "SL      : " + DoubleToString(g_tradeSl, _Digits) + "  -" + DoubleToString(curSlD, 2)
              + "  " + Money(-stopD * vpu * g_tradeLots));
      if(InpUseTrail && MathAbs(g_tradeSl - g_tradeSlInit) > TickSize() / 2)
         AddLine(L, "Trail   : activo (SL orig " + DoubleToString(g_tradeSlInit, _Digits) + ")");
      AddLine(L, "R:R     : " + DoubleToString(stopD > 0 ? targetD / stopD : 0, 1) + " : 1");

      if(g_tradeActive)
        {
         double pnl, pts;
         ulong t;
         double px = g_tradeLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         pts = g_tradeLong ? px - g_tradeEntry : g_tradeEntry - px;
         if(InpMode == GEEK_FULLAUTO && MyPosition(t) != 0)
            pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         else
            pnl = pts * vpu * g_tradeLots;
         int bars = iBarShift(_Symbol, g_tf, g_tradeTime);
         AddLine(L, "Estado  : ABIERTO  " + IntegerToString(MathMax(0, bars)) + " velas");
         AddLine(L, "PnL     : " + Money(pnl) + "  (" + DoubleToString(stopD > 0 ? pts / stopD : 0, 2) + " R)");
        }
      else
         AddLine(L, "Estado  : CERRADO por " + (g_tradeResult == "" ? "-" : g_tradeResult));
     }

   // --- medidas
   int n = ArraySize(L);
   TextSetFont("Consolas", -InpPanelFont * 10);
   uint w = 0, h = 0, maxW = 0, lineH = 0;
   for(int i = 0; i < n; i++)
     {
      TextGetSize(L[i], w, h);
      if(w > maxW) maxW = w;
      if(h > lineH) lineH = h;
     }
   lineH += 2;
   int pad = 8, margin = 12;
   int width  = (int)maxW + 2 * pad;
   int height = n * (int)lineH + 2 * pad;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   bool right = InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER;
   bool lower = InpPanelCorner == CORNER_LEFT_LOWER  || InpPanelCorner == CORNER_RIGHT_LOWER;
   int x0 = right ? MathMax(0, cw - width - margin) : margin;
   int y0 = lower ? MathMax(0, ch - height - margin) : margin + 16;

   color bg = g_tradeActive ? (g_tradeLong ? C'0,70,0' : C'90,0,0') : C'22,22,22';

   string bgName = PFX + "Pbg";
   if(ObjectFind(0, bgName) < 0)
     {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x0);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y0);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, clrDimGray);

   for(int i = 0; i < n; i++)
     {
      string nm = PFX + "P" + IntegerToString(i);
      if(ObjectFind(0, nm) < 0)
        {
         ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, nm, OBJPROP_BACK, false);
         ObjectSetString(0, nm, OBJPROP_FONT, "Consolas");
        }
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpPanelFont);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x0 + pad);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y0 + pad + i * (int)lineH);
      ObjectSetString(0, nm, OBJPROP_TEXT, L[i]);
     }
   for(int i = n; i < g_panelLines; i++)
      ObjectDelete(0, PFX + "P" + IntegerToString(i));
   g_panelLines = n;
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Eventos                                                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   string sym = _Symbol, flt = InpSymbolFilter;
   StringToUpper(sym);
   StringToUpper(flt);
   if(flt != "" && StringFind(sym, flt) < 0)
     {
      Alert("GeekV72: este EA solo opera " + InpSymbolFilter + ". Grafico actual: " + _Symbol);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpBasisLen < 1 || InpVolLen < 1 || InpBasisSmooth < 1 || InpVolSmooth < 1 ||
      InpVolRankLookback < 1 || InpAlmaSigma < 1 || InpMaxMult < InpMinMult ||
      InpMinStopUSD > InpMaxStopUSD || InpRiskPct <= 0 || InpDrawBars < 1)
     {
      Alert("GeekV72: parametros invalidos.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_tf   = InpTimeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpTimeframe;
   g_live = !MQLInfoInteger(MQL_TESTER);
   g_draw = !MQLInfoInteger(MQL_OPTIMIZATION) && (g_live || MQLInfoInteger(MQL_VISUAL_MODE));

   // pesos ALMA (constantes)
   ArrayResize(g_almaW, InpBasisLen);
   double m = InpAlmaOffset * (InpBasisLen - 1);
   double s = InpBasisLen / InpAlmaSigma;
   g_almaNorm = 0;
   for(int i = 0; i < InpBasisLen; i++)
     {
      g_almaW[i] = MathExp(-((i - m) * (i - m)) / (2.0 * s * s));
      g_almaNorm += g_almaW[i];
     }
   g_minBars = MathMax(InpBasisLen, InpVolLen);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePts);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpExitSizing == GEEK_EXIT_ATR)
     {
      g_atrH = iATR(_Symbol, g_tf, InpAtrPeriod);
      if(g_atrH == INVALID_HANDLE) { Print("GeekV72: no se pudo crear el ATR"); return INIT_FAILED; }
     }
   if(InpUseHTF)
     {
      g_htfH = iMA(_Symbol, InpHTF, InpHTFEmaLen, 0, MODE_EMA, PRICE_CLOSE);
      if(g_htfH == INVALID_HANDLE) { Print("GeekV72: no se pudo crear la EMA HTF"); return INIT_FAILED; }
     }

   g_day = 0;
   g_peakEq = AccountInfoDouble(ACCOUNT_EQUITY);
   EvaluateRisk();

   g_needRebuild = !EngineRebuild();   // si el historial aun no esta, se reintenta en OnTick

   // si ya hay una posicion del EA (reinicio del terminal), retomarla
   ulong t;
   int dir = MyPosition(t);
   if(dir != 0)
     {
      SetTradeMarks(dir == 1, PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL),
                    PositionGetDouble(POSITION_TP), PositionGetDouble(POSITION_VOLUME));
      g_tradeTime  = (datetime)PositionGetInteger(POSITION_TIME);
      g_tradePosId = PositionGetInteger(POSITION_IDENTIFIER);
     }

   if(g_live) EventSetTimer(1);
   DrawPanel();
   PrintFormat("GeekV72 iniciado en %s %s. Modo %s.", _Symbol, TfName(g_tf),
               InpMode == GEEK_FULLAUTO ? "FullAuto" : "SemiAuto");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_atrH != INVALID_HANDLE) IndicatorRelease(g_atrH);
   if(g_htfH != INVALID_HANDLE) IndicatorRelease(g_htfH);
   ObjectsDeleteAll(0, PFX);
   ChartRedraw(0);
  }

void OnTick()
  {
   if(g_needRebuild)
     {
      if(!EngineRebuild()) return;
      g_needRebuild = false;
     }

   EvaluateRisk();

   // cierre antes del fin de semana
   if(InpFridayClose)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      ulong t;
      if(dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour && MyPosition(t) != 0)
         CloseAllMine("VIERNES");
     }

   datetime t0 = iTime(_Symbol, g_tf, 0);
   if(t0 != 0 && t0 != g_lastBarOpen)
     {
      g_lastBarOpen = t0;
      if(EngineUpdate()) OnNewClosedBar();
     }

   // refresco del panel como mucho 2 veces por segundo
   uint now = GetTickCount();
   if(now - g_lastPanelMs > 500)
     {
      g_lastPanelMs = now;
      DrawPanel();
     }
  }

void OnTimer()
  {
   DrawPanel();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE) DrawPanel();
  }

// Motivo de cierre del trade real (SL / TP / TRAIL / FLIP / RIESGO / VIERNES)
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) return;

   long posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(g_tradePosId == 0 || posId != g_tradePosId) return;

   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string res;
   if(reason == DEAL_REASON_SL)
      res = (InpUseTrail && MathAbs(g_tradeSl - g_tradeSlInit) > TickSize() / 2) ? "TRAIL" : "SL";
   else if(reason == DEAL_REASON_TP) res = "TP";
   else if(reason == DEAL_REASON_SO) res = "STOP OUT";
   else res = g_closeReason != "" ? g_closeReason : "CERRADO";

   g_tradeActive = false;
   g_tradeResult = res;
   g_closeReason = "";
   g_tradePosId  = 0;
   DrawPanel();
  }
//+------------------------------------------------------------------+
