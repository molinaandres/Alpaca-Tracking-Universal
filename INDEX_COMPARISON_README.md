# Funcionalidad de Comparación con Índices

## Descripción

Esta funcionalidad permite comparar el rendimiento de tu portfolio de Alpaca con los principales índices del mercado, incluyendo:

- **S&P 500** (^GSPC) - Índice de las 500 empresas más grandes de EE.UU.
- **NASDAQ** (^IXIC) - Índice compuesto de NASDAQ
- **MSCI World** (EWRD) - Índice mundial a través del ETF EWRD

## Características

### 1. Comparación Visual
- Gráficos superpuestos que muestran la evolución del portfolio vs índices
- Colores distintivos para cada índice (S&P 500: rojo, NASDAQ: naranja, MSCI World: púrpura)
- Interpolación suavizada para mejor visualización

### 2. Métricas de Comparación
- **Retorno del Portfolio**: Porcentaje de ganancia/pérdida del portfolio
- **Retorno del Índice**: Porcentaje de ganancia/pérdida del índice
- **Outperformance**: Diferencia entre el retorno del portfolio y el índice
- **Correlación**: Medida de qué tan relacionado está el portfolio con el índice
- **Ratio de Volatilidad**: Comparación de la volatilidad entre portfolio e índice

### 3. Selector de Índices
- Interfaz intuitiva para seleccionar qué índices comparar
- Información detallada de cada índice
- Selección múltiple con indicadores visuales

### 4. Períodos de Comparación
- Mismos períodos que la vista de Performance
- Soporte para rangos personalizados
- Datos históricos sincronizados

## Cómo Usar

### Acceso a la Funcionalidad
1. Abre la aplicación Grecia Tracker
2. Ve a la pestaña "Comparación" en la barra de navegación
3. Selecciona una cuenta de tu lista
4. Elige los índices que quieres comparar
5. Selecciona el período de tiempo

### Interpretación de Resultados

#### Outperformance Positivo
- Tu portfolio ha superado al índice en el período seleccionado
- Indica que tu estrategia de inversión está funcionando bien

#### Outperformance Negativo
- El índice ha superado a tu portfolio
- Puede indicar la necesidad de revisar tu estrategia

#### Correlación Alta (>0.7)
- Tu portfolio se mueve de manera similar al índice
- Menor diversificación, mayor riesgo sistemático

#### Correlación Baja (<0.3)
- Tu portfolio es independiente del índice
- Mayor diversificación, menor riesgo sistemático

#### Ratio de Volatilidad
- >1.0: Tu portfolio es más volátil que el índice
- <1.0: Tu portfolio es menos volátil que el índice

## Fuentes de Datos

### Yahoo Finance API
- **Ventaja**: Gratuito, sin límites estrictos
- **Datos**: Históricos completos para todos los índices
- **Actualización**: En tiempo real durante horario de mercado

### Símbolos Utilizados
- S&P 500: `^GSPC`
- NASDAQ: `^IXIC`
- MSCI World: `EWRD` (ETF que replica el índice)

## Limitaciones

1. **Datos Históricos**: Limitados por la disponibilidad de Yahoo Finance
2. **Sincronización**: Los datos se actualizan según el horario de mercado
3. **Correlación**: Cálculo simplificado para mejor rendimiento
4. **Volatilidad**: Anualizada asumiendo 252 días de trading

## Solución de Problemas

### No se cargan los datos de índices
- Verifica tu conexión a internet
- Los datos pueden no estar disponibles fuera del horario de mercado
- Intenta con un período de tiempo diferente

### Errores de correlación
- Asegúrate de que hay suficientes puntos de datos
- Verifica que el período seleccionado tenga datos válidos

### Rendimiento lento
- Reduce el número de índices seleccionados
- Usa períodos de tiempo más cortos
- Los datos se cachean para mejorar el rendimiento

## Arquitectura Técnica

### Modelos de Datos
- `Index`: Representa un índice financiero
- `IndexDataPoint`: Punto de datos históricos
- `IndexHistory`: Historial completo de un índice
- `IndexComparison`: Resultado de comparación

### Servicios
- `IndexDataManager`: Gestiona la obtención de datos de índices
- `YahooFinanceResponse`: Modelos para la API de Yahoo Finance

### Vistas
- `IndexComparisonView`: Vista principal de comparación
- `IndexSelector`: Selector de índices reutilizable
- `ComparisonChartView`: Gráfico de comparación
- `ComparisonMetricsCard`: Tarjeta de métricas

## Futuras Mejoras

1. **Más Índices**: Añadir índices sectoriales y regionales
2. **Análisis Avanzado**: Sharpe ratio, beta, alpha
3. **Alertas**: Notificaciones cuando se supere/descienda del índice
4. **Exportación**: Guardar comparaciones como PDF o imagen
5. **Comparación de Múltiples Cuentas**: Comparar diferentes cuentas simultáneamente
