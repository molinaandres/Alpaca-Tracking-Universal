# Agregación de Datos Históricos para Total Accounts

## Problema Resuelto

**Antes**: Total Accounts solo mostraba 1 punto de datos (balance actual)
**Ahora**: Total Accounts muestra el historial completo del período seleccionado

## Flujo de Agregación

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Cuenta A      │    │   Cuenta B      │    │   Cuenta C      │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Historial   │ │    │ │ Historial   │ │    │ │ Historial   │ │
│ │ 1M, 1D      │ │    │ │ 1M, 1D      │ │    │ │ 1M, 1D      │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   Agregación    │
                    │                 │
                    │ ┌─────────────┐ │
                    │ │ Por fecha:  │ │
                    │ │ - Suma      │ │
                    │ │ - Ponderado │ │
                    │ │ - Promedio  │ │
                    │ └─────────────┘ │
                    └─────────────────┘
                                 │
                    ┌─────────────────┐
                    │ Total Accounts  │
                    │                 │
                    │ ┌─────────────┐ │
                    │ │ Historial   │ │
                    │ │ Completo    │ │
                    │ │ 1M, 1D      │ │
                    │ └─────────────┘ │
                    └─────────────────┘
```

## Implementación Técnica

### 1. Recolección Paralela de Datos

```swift
// Para cada cuenta real
for account in accounts {
    group.enter()
    
    apiService.getPortfolioHistoryWithCustomDateRange(
        startDate: startDate,
        endDate: endDate,
        timeframe: timeframe
    ) { result in
        // Procesar y almacenar datos
        accountHistories[account.id] = processedData
        group.leave()
    }
}
```

### 2. Agregación por Timestamp

```swift
// Para cada fecha única
for timestamp in sortedTimestamps {
    var totalWeightedEquity: Double = 0
    var totalWeight: Double = 0
    var totalWeightedChange: Double = 0
    
    // Sumar datos de todas las cuentas para esta fecha
    for account in accounts {
        let weight = dataPoint.equity
        totalWeightedEquity += dataPoint.equity
        totalWeightedChange += dataPoint.profitLossPct * weight
        totalWeight += weight
    }
    
    // Crear punto agregado
    let aggregatedDataPoint = PortfolioHistoryDataPoint(
        timestamp: timestamp,
        equity: totalWeightedEquity,
        profitLossPct: totalWeightedChange / totalWeight
    )
}
```

### 3. Manejo de Datos Faltantes

- **Cuentas sin datos**: Se omiten del cálculo para esa fecha
- **Fechas parciales**: Solo se incluyen fechas con al menos una cuenta con datos
- **Validación**: Se requiere al menos una cuenta con datos válidos

## Ejemplo Práctico

### Datos de Entrada (1 mes, granularidad diaria)

| Fecha | Cuenta A ($10K) | Cuenta B ($6K) | Cuenta C ($4K) |
|-------|----------------|----------------|----------------|
| 1 Ene | +1.2%          | +0.8%          | +2.1%          |
| 2 Ene | +0.5%          | +1.5%          | -0.3%          |
| 3 Ene | +2.1%          | +0.9%          | +1.8%          |

### Cálculo Agregado

**1 Ene**: `(1.2% × $10K + 0.8% × $6K + 2.1% × $4K) / $20K = 1.26%`
**2 Ene**: `(0.5% × $10K + 1.5% × $6K + (-0.3%) × $4K) / $20K = 0.49%`
**3 Ene**: `(2.1% × $10K + 0.9% × $6K + 1.8% × $4K) / $20K = 1.68%`

### Resultado Final

| Fecha | Total Accounts (Balance) | Total Accounts (Rendimiento) |
|-------|-------------------------|------------------------------|
| 1 Ene | $20,252                | +1.26%                       |
| 2 Ene | $20,351                | +0.49%                       |
| 3 Ene | $20,693                | +1.68%                       |

## Beneficios

1. **Historial Completo**: Gráficos con datos de todo el período
2. **Rendimiento Real**: Refleja el rendimiento agregado, no solo el balance
3. **Comparable**: Se puede comparar con índices de referencia
4. **Consistente**: La métrica es estable a lo largo del tiempo
5. **Robusto**: Maneja cuentas con diferentes fechas de inicio

## Casos de Uso

- **Performance View**: Muestra el rendimiento histórico de Total Accounts
- **Comparison View**: Compara con S&P 500, NASDAQ, etc.
- **Análisis Temporal**: Permite ver tendencias a lo largo del tiempo
- **Toma de Decisiones**: Proporciona contexto para decisiones de inversión
