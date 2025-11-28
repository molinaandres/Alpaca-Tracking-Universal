# Arquitectura de la Funcionalidad de Comparación con Índices

## Diagrama de Flujo de Datos

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   ContentView   │    │ PerformanceView  │    │IndexComparisonView│
│                 │    │                  │    │                 │
│ - Tab Navigation│    │ - Portfolio Data │    │ - Index Selection│
│ - Account List  │    │ - Performance    │    │ - Comparison UI  │
└─────────┬───────┘    └─────────┬────────┘    └─────────┬───────┘
          │                      │                       │
          │                      │                       │
          ▼                      ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  AccountManager │    │ AlpacaAPIService │    │ IndexDataManager│
│                 │    │                  │    │                 │
│ - Account Data  │    │ - Portfolio API  │    │ - Yahoo Finance │
│ - Balance Cache │    │ - History API    │    │ - Index Data    │
└─────────┬───────┘    └─────────┬────────┘    └─────────┬───────┘
          │                      │                       │
          │                      │                       │
          ▼                      ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Alpaca API    │    │   Portfolio      │    │  Yahoo Finance  │
│                 │    │   History        │    │      API        │
│ - Account Info  │    │ - Equity Data    │    │ - Index Prices  │
│ - Positions     │    │ - P&L Data       │    │ - Historical    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Modelos de Datos

```
┌─────────────────┐
│      Index      │
├─────────────────┤
│ - id: String    │
│ - symbol: String│
│ - name: String  │
│ - description   │
│ - currency      │
└─────────────────┘
         │
         ▼
┌─────────────────┐
│  IndexDataPoint │
├─────────────────┤
│ - timestamp     │
│ - value: Double │
│ - change        │
│ - changePercent │
└─────────────────┘
         │
         ▼
┌─────────────────┐
│  IndexHistory   │
├─────────────────┤
│ - index: Index  │
│ - dataPoints    │
│ - startDate     │
│ - endDate       │
└─────────────────┘
         │
         ▼
┌─────────────────┐
│IndexComparison  │
├─────────────────┤
│ - portfolioReturn│
│ - indexReturn   │
│ - outperformance│
│ - correlation   │
│ - volatilityRatio│
└─────────────────┘
```

## Flujo de Comparación

```
1. Usuario selecciona cuenta y índices
   │
   ▼
2. IndexDataManager obtiene datos históricos de Yahoo Finance
   │
   ▼
3. AlpacaAPIService obtiene datos del portfolio
   │
   ▼
4. Se calculan métricas de comparación:
   - Retornos
   - Outperformance
   - Correlación
   - Volatilidad
   │
   ▼
5. Se muestran resultados en:
   - Gráfico comparativo
   - Tarjetas de resumen
   - Tabla de métricas
```

## Componentes de UI

```
IndexComparisonView
├── IndexSelector
│   └── IndexSelectionCard
├── ComparisonChartView
├── IndexComparisonSummary
│   └── ComparisonSummaryCard
└── ComparisonMetricsCard
```

## APIs Utilizadas

### Yahoo Finance API
- **Endpoint**: `https://query1.finance.yahoo.com/v8/finance/chart/{symbol}`
- **Parámetros**: 
  - `period1`: Timestamp de inicio
  - `period2`: Timestamp de fin
  - `interval`: 1d (diario)
- **Respuesta**: JSON con datos históricos

### Alpaca API (existente)
- **Portfolio History**: `/v2/account/portfolio/history`
- **Account Info**: `/v2/account`
- **Positions**: `/v2/positions`

## Caching y Optimización

```
IndexDataManager
├── Cache de datos históricos por índice
├── Validación de fechas
├── Filtrado local de rangos
└── Cálculos de métricas en background
```

## Manejo de Errores

```
┌─────────────────┐
│   Error Types   │
├─────────────────┤
│ - Network Error │
│ - API Error     │
│ - No Data       │
│ - Processing    │
└─────────────────┘
         │
         ▼
┌─────────────────┐
│  Error Handling │
├─────────────────┤
│ - User Messages │
│ - Retry Logic   │
│ - Fallback Data │
└─────────────────┘
```
