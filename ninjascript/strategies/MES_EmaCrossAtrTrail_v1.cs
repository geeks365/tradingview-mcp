using System;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.NinjaScript;

namespace NinjaTrader.NinjaScript.Strategies
{
    public class MES_EmaCrossAtrTrail_v1 : Strategy
    {
        private NinjaTrader.NinjaScript.Indicators.EMA emaFast;
        private NinjaTrader.NinjaScript.Indicators.EMA emaSlow;
        private NinjaTrader.NinjaScript.Indicators.ATR atr;

        private const string LongSignal  = "LongEntry";
        private const string ShortSignal = "ShortEntry";

        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Name                         = "MES_EmaCrossAtrTrail_v1";
                Description                  = "EMA crossover (long/short, reversing) with an ATR-sized trailing stop. Built for MES 5-minute.";
                Calculate                    = Calculate.OnBarClose;
                EntriesPerDirection          = 1;
                EntryHandling                = EntryHandling.AllEntries;
                IsExitOnSessionCloseStrategy = true;
                ExitOnSessionCloseSeconds    = 30;
                StartBehavior                = StartBehavior.WaitUntilFlat;
                StopTargetHandling           = StopTargetHandling.PerEntryExecution;
                BarsRequiredToTrade          = 21;

                FastPeriod    = 9;
                SlowPeriod    = 21;
                AtrPeriod     = 14;
                AtrMultiplier = 2.0;
                TradeQuantity = 1;
            }
            else if (State == State.DataLoaded)
            {
                emaFast = EMA(Close, FastPeriod);
                emaSlow = EMA(Close, SlowPeriod);
                atr     = ATR(AtrPeriod);

                AddChartIndicator(emaFast);
                AddChartIndicator(emaSlow);
            }
        }

        protected override void OnBarUpdate()
        {
            if (BarsInProgress != 0)
                return;

            if (CurrentBar < BarsRequiredToTrade)
                return;

            // SetTrailStop's offset is fixed once the entry fills, so size it from ATR on the signal bar.
            int trailTicks = Math.Max(1, (int)Math.Ceiling(atr[0] * AtrMultiplier / TickSize));

            if (CrossAbove(emaFast, emaSlow, 1) && Position.MarketPosition != MarketPosition.Long)
            {
                SetTrailStop(LongSignal, CalculationMode.Ticks, trailTicks, false);
                EnterLong(TradeQuantity, LongSignal);
            }
            else if (CrossBelow(emaFast, emaSlow, 1) && Position.MarketPosition != MarketPosition.Short)
            {
                SetTrailStop(ShortSignal, CalculationMode.Ticks, trailTicks, false);
                EnterShort(TradeQuantity, ShortSignal);
            }
        }

        #region Properties
        [NinjaScriptProperty]
        [Range(1, int.MaxValue)]
        [Display(Name = "Fast EMA Period", Order = 1, GroupName = "Parameters")]
        public int FastPeriod { get; set; }

        [NinjaScriptProperty]
        [Range(1, int.MaxValue)]
        [Display(Name = "Slow EMA Period", Order = 2, GroupName = "Parameters")]
        public int SlowPeriod { get; set; }

        [NinjaScriptProperty]
        [Range(1, int.MaxValue)]
        [Display(Name = "ATR Period", Order = 3, GroupName = "Parameters")]
        public int AtrPeriod { get; set; }

        [NinjaScriptProperty]
        [Range(0.1, double.MaxValue)]
        [Display(Name = "ATR Multiplier", Order = 4, GroupName = "Parameters")]
        public double AtrMultiplier { get; set; }

        [NinjaScriptProperty]
        [Range(1, int.MaxValue)]
        [Display(Name = "Quantity", Order = 5, GroupName = "Parameters")]
        public int TradeQuantity { get; set; }
        #endregion
    }
}
