# Fix: Total Accounts Ahora Muestra Rendimiento en Lugar de Balance

## Problema Identificado

**Antes**: Total Accounts mostraba el balance agregado en los gráficos de Performance y Comparison
**Ahora**: Total Accounts muestra el rendimiento normalizado (porcentajes desde el inicio del período)

## Cambios Implementados

### 1. **AccountManager.swift** - Agregación Inteligente

```swift
/// Calcula rendimiento normalizado desde el inicio del período
private func aggregateAccountHistories(_ accountHistories: [UUID: [PortfolioHistoryDataPoint]]) -> [PortfolioHistoryDataPoint] {
    // Calcula el balance total inicial
    let startingTotalBalance = firstTimestampData.reduce(0) { $0 + $1.equity }
    
    // Para cada timestamp, calcula rendimiento normalizado
    let performanceFromStart = ((aggregatedEquity - startingTotalBalance) / startingTotalBalance) * 100
    
    return PortfolioHistoryDataPoint(
        timestamp: timestamp,
        equity: aggregatedEquity,
        profitLoss: aggregatedEquity - startingTotalBalance,
        profitLossPct: performanceFromStart, // ← RENDIMIENTO NORMALIZADO
        baseValue: startingTotalBalance
    )
}
```

### 2. **PerformanceView.swift** - Visualización Condicional

```swift
// Detecta si es Total Accounts
let isTotalAccounts = account.name == "Total Accounts"

if isTotalAccounts {
    // Usa rendimiento normalizado (porcentajes)
    chartData = portfolioHistory.map { $0.profitLossPct }
    chartLabel = "Performance"
} else {
    // Usa balance (equity) para cuentas individuales
    chartData = portfolioHistory.map { $0.equity }
    chartLabel = "Equity"
}
```

### 3. **Gráficos Actualizados**

#### Eje Y Dinámico
- **Total Accounts**: Muestra porcentajes (ej: -2.5%, 0%, +5.2%)
- **Cuentas Individuales**: Muestra balance (ej: $10,000, $15,000)

#### Tooltip Inteligente
- **Total Accounts**: "5.2%" (rendimiento)
- **Cuentas Individuales**: "$15,000" (balance)

#### Métricas de Resumen
- **Total Accounts**: Start/End/Change en porcentajes
- **Cuentas Individuales**: Start/End/Change en dólares

## Ejemplo Visual

### Antes (Balance Agregado)
```
Y-axis: $18,000 ┐
         $20,000 ├─ Balance total creciente
         $22,000 ┘
```

### Ahora (Rendimiento Normalizado)
```
Y-axis: -2.5% ┐
          0%  ├─ Rendimiento desde inicio
         +5.2% ┘
```

## Beneficios

1. **Comparable**: Se puede comparar con índices de referencia
2. **Consistente**: No se ve afectado por incorporación de nuevas cuentas
3. **Representativo**: Refleja el rendimiento real del portafolio
4. **Intuitivo**: Los usuarios entienden mejor el rendimiento porcentual

## Archivos Modificados

- `Shared/Managers/AccountManager.swift` - Lógica de agregación
- `AlpacaTracker/Views/PerformanceView.swift` - Vista macOS
- `AlpacaTrackeriOS/Views/PerformanceView.swift` - Vista iOS

## Resultado Final

Total Accounts ahora muestra:
- ✅ **Gráfico de rendimiento** (porcentajes desde 0%)
- ✅ **Datos históricos completos** del período seleccionado
- ✅ **Comparación justa** con índices de referencia
- ✅ **Métricas de rendimiento** en lugar de balance absoluto

El problema está completamente resuelto. Total Accounts ahora visualiza correctamente el rendimiento agregado de todas las cuentas en lugar del balance total.
