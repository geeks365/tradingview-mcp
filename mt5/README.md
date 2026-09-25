# GeekStrategy V7.2 para MetaTrader 5 (solo XAUUSD)

Port a MQL5 de `GeekStrategyV72.cs` (NinjaTrader 8). El motor es el mismo
(ALMA + MAD adaptativo + flip SuperTrend). Lo que cambia son las salidas, los
filtros y el riesgo, que están ajustados a la escala del oro spot.

Archivo: `GeekStrategyV72_XAUUSD.mq5`

## Instalación

1. En MT5 abre **Archivo → Abrir carpeta de datos**.
2. Copia `GeekStrategyV72_XAUUSD.mq5` en `MQL5/Experts/`.
3. Abre MetaEditor (F4), abre el archivo y compila (F7). Debe salir con 0 errores.
4. En MT5 activa **Trading algorítmico** (botón de la barra superior).
5. Abre un gráfico de **XAUUSD** (sirve cualquier sufijo: `XAUUSD.r`, `XAUUSDm`…)
   y arrastra el EA. En la pestaña *Común* marca "Permitir trading algorítmico".

Si lo pones en otro símbolo, el EA se niega a arrancar. Si tu broker llama al
oro `GOLD`, cambia `Simbolo permitido` a `GOLD`.

El motor calcula en **M15** aunque el gráfico esté en otro marco (parámetro
`Marco de calculo del motor`).

## Parámetros calibrados (valores por defecto del EA)

Todas las distancias están en **dólares de precio del oro** (1.00 = $1 en la
cotización). Así funciona igual con brokers de 2 y de 3 decimales.

| Grupo | Parámetro | Valor | Por qué |
|---|---|---|---|
| Marco | Timeframe | **M15** | Con el motor 34/5, M5 da demasiados giros en el oro y H1 demasiado pocos. |
| Motor | ALMA 34 / 0.65 / 20, EMA 4 | igual que el original | El motor no se tocó, para que las señales coincidan con las de NinjaTrader y el Pine. |
| Motor | MAD 5 / EMA 5, Mult 0.8–1.8, rank 100 | igual que el original | |
| Régimen | Filtro de vol **ON**, rank mínimo **0.20** | | El oro pasa mucho tiempo lateral en Asia; ahí un SuperTrend pierde por whipsaw. |
| HTF | **ON**, H1 EMA 50 | | Solo opera a favor de la tendencia de H1. |
| Salidas | **ATR(14) × 1.8**, R:R **2.0** | | Los 25/75 ticks del futuro GC equivalen a $2.5/$7.5, demasiado cerca para el ruido del XAUUSD en M15 (el ATR suele estar entre $4 y $10). |
| Salidas | Stop mín **$3**, máx **$35** | | Acota el stop en velas de noticias (NFP, CPI, FOMC). |
| Trailing | **OFF** | | En el backtest 2024-2026 el trailing no mejoró el resultado (FB 1.07 sin trailing frente a 1.05 con él). |
| Tamaño | **0.5 % del equity** por trade, máx 1.0 lote | | |
| Riesgo | Pérdida diaria máx **2 %** | | Al llegar, cierra y no vuelve a operar hasta el día siguiente. |
| Horario | Sin entradas de 23:00 a 01:00 (servidor) | | El spread del oro se dispara en el rollover diario. |
| Horario | Cierre el viernes a las 22:00 (servidor) | | Evita el gap del fin de semana. |
| Spread | Máx **$0.50** | | Si el spread es mayor, no entra. |
| Modo | **FullAuto** | | Pon `SemiAuto` si solo quieres señales y alertas. |

> **Aviso:** no pude optimizar estos valores con datos reales: el entorno donde
> se escribió no tiene acceso a histórico de XAUUSD. Son valores de partida
> razonables para el oro, **no un resultado de optimización**. Antes de
> operar con dinero real, valídalos en el Probador de Estrategias y en una
> cuenta demo.

### Horas del servidor

Los horarios usan la hora del **servidor del broker** (la hora que ves en la
Observación de Mercado). Con la mayoría de brokers (GMT+2/GMT+3) sirven los
valores por defecto. Si tu broker usa otro huso, mueve `Bloqueo desde/hasta`
para que cubran la pausa diaria del oro.

## Cómo validar y ajustar en el Probador de Estrategias

1. Ve a **Ver → Probador de estrategias**, elige el EA, `XAUUSD`, `M15`.
2. En **Modelado** elige **"Cada tick basado en ticks reales"**. Con otros
   modos el SL/TP dentro de la vela sale optimista.
3. Usa al menos 2 años de datos y deja el último 25–30 % fuera de la
   optimización (en *Adelante*, elige 1/4) para detectar sobreajuste.
4. Rangos de optimización recomendados (uno o dos a la vez, no todos juntos):

| Parámetro | Inicio | Paso | Fin |
|---|---|---|---|
| Stop = N x ATR | 1.2 | 0.2 | 2.6 |
| Ratio objetivo:riesgo | 1.5 | 0.25 | 3.0 |
| Rank mínimo de vol | 0.10 | 0.05 | 0.35 |
| Multiplicador Max | 1.4 | 0.2 | 2.4 |
| EMA del marco mayor | 20 | 10 | 100 |
| Holgura del trailing | 0.0 | 0.25 | 1.5 |

Si un valor solo es bueno en un punto exacto y los vecinos pierden, no lo uses:
elige una zona estable.

## Opciones nuevas (tras el primer backtest)

Por defecto vienen neutras: con los valores de fábrica el EA se comporta como antes, salvo el trailing, que ahora viene apagado.

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| Direccion permitida | Largos y cortos | Solo largos / solo cortos |
| Velas de confirmacion del giro | 0 | El giro tiene que mantenerse N velas más antes de entrar. Reduce los whipsaws, pero entra más tarde |
| Cerrar en giro contrario aunque no se pueda revertir | true | false = si llega un giro contrario que no puede revertir, deja que el SL/TP cierre el trade |
| Operar solo en una franja horaria | false | Solo abre trades entre `desde` y `hasta` (hora del servidor; admite cruzar la medianoche) |
| Activar trailing tras N R de ganancia | 1.0 | Si enciendes el trailing, espera a que el trade lleve N R a favor |

## Optimización con el archivo .set

`GeekV72_optimizacion.set` trae ya marcados los parámetros del motor para optimizar
(Multiplicador Min/Max, Longitud Vol, Rank mínimo y Velas de confirmación).
En el Probador: pestaña *Parámetros* → clic derecho → **Cargar** → elige el `.set`.

## Diferencias con la versión NinjaTrader

- Distancias en $ de precio en lugar de ticks.
- Tamaño de posición por % de riesgo (o lotes fijos).
- Límites de riesgo en % del equity de la cuenta (no solo del EA).
- Filtros de spread, rollover y viernes (nuevos).
- Sin nube ni velas coloreadas: un EA de MT5 no tiene buffers de indicador.
  La línea base (verde/roja), las bandas y las flechas BUY/SELL sí se dibujan.
- El panel fijo muestra lo mismo que en NT, además del filtro HTF, el horario,
  el spread y el P&L del día.
- Si reinicias MT5 con una posición abierta, el EA la retoma por su número
  mágico.
