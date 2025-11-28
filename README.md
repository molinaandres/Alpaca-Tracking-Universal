# Alpaca Tracking - Universal

Aplicación multiplataforma (macOS e iOS) para el seguimiento y análisis de portfolios de trading en Alpaca Markets.

## 📋 Tabla de Contenidos

- [Características Principales](#características-principales)
- [Arquitectura](#arquitectura)
- [Funcionalidades](#funcionalidades)
- [Instalación](#instalación)
- [Uso](#uso)
- [APIs Utilizadas](#apis-utilizadas)
- [Seguridad](#seguridad)
- [Estructura del Proyecto](#estructura-del-proyecto)

## 🚀 Características Principales

### Gestión de Múltiples Cuentas
- Soporte para múltiples cuentas de Alpaca (Paper Trading y Live Trading)
- Agregación de cuentas en vista "Total Accounts"
- Cifrado local de credenciales usando AES-GCM
- Sincronización automática de balances y posiciones

### Análisis de Performance
- Gráficos históricos de equity y rendimiento
- Cálculo de Time-Weighted Returns (TWR) ajustado por flujos de caja
- Visualización de rendimiento normalizado para Total Accounts
- Métricas de resumen: Start, End, Change, P&L

### Comparación con Índices
- Comparación con S&P 500, NASDAQ y MSCI World
- Cálculo de métricas: Outperformance, Correlación, Ratio de Volatilidad
- Gráficos superpuestos para visualización comparativa
- Análisis de rendimiento relativo

### Gestión de Posiciones
- Vista detallada de todas las posiciones abiertas
- Información de P&L realizado y no realizado
- Filtrado y ordenamiento de posiciones
- Actualización automática periódica

## 🏗️ Arquitectura

### Flujo de Datos

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   ContentView   │    │ PerformanceView  │    │IndexComparisonView│
│                 │    │                  │    │                 │
│ - Tab Navigation│    │ - Portfolio Data │    │ - Index Selection│
│ - Account List  │    │ - Performance    │    │ - Comparison UI  │
└─────────┬───────┘    └─────────┬────────┘    └─────────┬───────┘
          │                      │                       │
          ▼                      ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  AccountManager │    │ AlpacaAPIService │    │ IndexDataManager│
│                 │    │                  │    │                 │
│ - Account Data  │    │ - Portfolio API  │    │ - Yahoo Finance │
│ - Balance Cache │    │ - History API    │    │ - Index Data    │
└─────────┬───────┘    └─────────┬────────┘    └─────────┬───────┘
          │                      │                       │
          ▼                      ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Alpaca API    │    │   Portfolio      │    │  Yahoo Finance  │
│                 │    │   History        │    │      API        │
│ - Account Info  │    │ - Equity Data    │    │ - Index Prices  │
│ - Positions     │    │ - P&L Data       │    │ - Historical    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Componentes Principales

#### Managers
- **AccountManager**: Gestiona cuentas, balances y agregación de datos
- **TradingDataManager**: Maneja posiciones, trades y datos de trading
- **IndexDataManager**: Obtiene y procesa datos de índices de mercado

#### Services
- **AlpacaAPIService**: Cliente para la API de Alpaca Markets
- **EncryptionService**: Cifrado/descifrado de credenciales sensibles
- **SettingsManager**: Gestión de configuración de la aplicación
- **TWRCalculator/TWRRunner**: Cálculo de Time-Weighted Returns

#### Models
- **AlpacaAccount**: Modelo de cuenta con credenciales cifradas
- **PortfolioHistory**: Historial de portfolio con timestamps y equity
- **Position**: Información de posiciones abiertas
- **IndexData**: Modelos para datos de índices financieros

## 📊 Funcionalidades Detalladas

### 1. Vista de Performance

Muestra el rendimiento histórico del portfolio con:

- **Gráficos interactivos**: Visualización de equity o rendimiento porcentual
- **Métricas de resumen**: 
  - Balance inicial y final
  - Cambio absoluto y porcentual
  - P&L total
- **Períodos configurables**: 1D, 1W, 1M, 3M, 1Y, All Time, Custom
- **Granularidad**: 1Min, 5Min, 15Min, 1H, 1D según el período

#### Total Accounts

La vista "Total Accounts" agrega todas las cuentas configuradas:

- **Agregación inteligente**: Suma de equity por fecha
- **Rendimiento normalizado**: Muestra porcentajes desde el inicio del período
- **Cálculo ponderado**: Las cuentas con mayor balance tienen más peso
- **Historial completo**: Datos históricos de todo el período seleccionado

**Ejemplo de cálculo agregado:**
```
Fecha | Cuenta A ($10K) | Cuenta B ($6K) | Total Accounts
1 Ene | +1.2%          | +0.8%          | +1.26% (ponderado)
2 Ene | +0.5%          | +1.5%          | +0.49% (ponderado)
```

### 2. Comparación con Índices

Compara el rendimiento del portfolio con índices de referencia:

#### Índices Disponibles
- **S&P 500** (^GSPC): 500 empresas más grandes de EE.UU.
- **NASDAQ** (^IXIC): Índice compuesto de NASDAQ
- **MSCI World** (URTH): Índice mundial a través de ETF

#### Métricas Calculadas
- **Retorno del Portfolio**: Porcentaje de ganancia/pérdida
- **Retorno del Índice**: Porcentaje de ganancia/pérdida del índice
- **Outperformance**: Diferencia entre portfolio e índice
- **Correlación**: Medida de relación entre movimientos (0-1)
- **Ratio de Volatilidad**: Comparación de volatilidad

#### Interpretación

**Outperformance Positivo**
- El portfolio supera al índice
- Estrategia funcionando bien

**Outperformance Negativo**
- El índice supera al portfolio
- Revisar estrategia

**Correlación Alta (>0.7)**
- Portfolio se mueve similar al índice
- Menor diversificación, mayor riesgo sistemático

**Correlación Baja (<0.3)**
- Portfolio independiente del índice
- Mayor diversificación, menor riesgo sistemático

**Ratio de Volatilidad**
- >1.0: Portfolio más volátil que el índice
- <1.0: Portfolio menos volátil que el índice

### 3. Time-Weighted Returns (TWR)

Cálculo preciso de retornos ajustados por flujos de caja:

- **Ajuste por depósitos/retiros**: Considera CSD (Cash Settlement Deposit) y CSW (Cash Settlement Withdrawal)
- **Cálculo diario**: Retorno diario ajustado por flujos de caja
- **TWR acumulado**: Retorno acumulado desde el inicio del período
- **Script embebido**: Cálculo robusto usando bash script integrado

**Fórmula de retorno diario:**
```
daily_return = (adjusted_equity - previous_equity) / previous_equity
donde adjusted_equity = current_equity - net_cash_flow
```

### 4. Gestión de Posiciones

- Lista de todas las posiciones abiertas
- Información detallada: Símbolo, cantidad, precio promedio, P&L
- Filtrado por cuenta
- Actualización automática cada hora

## 🔧 Instalación

### Requisitos
- Xcode 14.0 o superior
- macOS 12.0+ (para versión macOS)
- iOS 15.0+ (para versión iOS)
- Cuenta de Alpaca Markets con API keys

### Pasos

1. Clonar el repositorio:
```bash
git clone https://github.com/molinaandres/Alpaca-Tracking-Universal.git
cd Alpaca-Tracking-Universal
```

2. Abrir el proyecto en Xcode:
```bash
open AlpacaTracker.xcodeproj
```

3. Seleccionar el target deseado:
   - `AlpacaTracker` para macOS
   - `AlpacaTrackeriOS` para iOS

4. Compilar y ejecutar (⌘R)

## 📖 Uso

### Agregar una Cuenta

1. Abre la aplicación
2. Haz clic en "Add Account"
3. Ingresa:
   - Nombre de la cuenta
   - API Key de Alpaca
   - Secret Key de Alpaca
   - Tipo: Paper Trading o Live Trading
   - Fecha del primer trade (opcional)
4. Haz clic en "Test Connection" para verificar
5. Guarda la cuenta

### Ver Performance

1. Ve a la pestaña "Performance"
2. Selecciona una cuenta o "Total Accounts"
3. Elige el período y granularidad
4. Visualiza el gráfico y métricas

### Comparar con Índices

1. Ve a la pestaña "Comparison"
2. Selecciona una cuenta
3. Elige los índices a comparar
4. Selecciona el período
5. Analiza las métricas de comparación

### Ver Posiciones

1. Ve a la pestaña "Positions"
2. Selecciona una cuenta
3. Revisa todas las posiciones abiertas
4. Filtra u ordena según necesites

## 🔌 APIs Utilizadas

### Alpaca Markets API

**Endpoints utilizados:**
- `GET /v2/account`: Información de la cuenta
- `GET /v2/positions`: Posiciones abiertas
- `GET /v2/orders`: Historial de órdenes
- `GET /v2/account/portfolio/history`: Historial de portfolio
- `GET /v2/account/activities`: Actividades (depósitos/retiros)

**Autenticación:**
- API Key y Secret Key en headers:
  - `APCA-API-KEY-ID`
  - `APCA-API-SECRET-KEY`

**Entornos:**
- Paper Trading: `https://paper-api.alpaca.markets`
- Live Trading: `https://api.alpaca.markets`

### Yahoo Finance API

**Endpoint:**
- `GET https://query1.finance.yahoo.com/v8/finance/chart/{symbol}`

**Parámetros:**
- `period1`: Timestamp de inicio
- `period2`: Timestamp de fin
- `interval`: 1d (diario)

**Símbolos:**
- S&P 500: `^GSPC`
- NASDAQ: `^IXIC`
- MSCI World: `URTH`

## 🔒 Seguridad

### Cifrado de Credenciales

Las credenciales de Alpaca se cifran localmente usando:

- **Algoritmo**: AES-GCM (Advanced Encryption Standard - Galois/Counter Mode)
- **Clave**: Derivada del identificador único del dispositivo
- **Almacenamiento**: Archivos JSON encriptados en el directorio de documentos

**Proceso de cifrado:**
1. Al agregar una cuenta, las credenciales se cifran inmediatamente
2. Se almacenan en formato cifrado en `alpaca_accounts.json`
3. Al usar las credenciales, se descifran en memoria
4. Las credenciales nunca se almacenan en texto plano

### Persistencia Local

- **Cuentas**: `~/Documents/alpaca_accounts.json` (cifrado)
- **Balances**: `~/Documents/alpaca_balances.json`
- **Posiciones**: `~/Documents/alpaca_positions.json`
- **Trades**: `~/Documents/alpaca_trades.json`
- **Configuración**: UserDefaults (tema, períodos, etc.)

## 📁 Estructura del Proyecto

```
Alpaca-Tracking-Universal/
├── AlpacaTracker/              # Target macOS
│   ├── AlpacaTrackerApp.swift
│   ├── ContentView.swift
│   └── Views/
│       ├── PerformanceView.swift
│       ├── PositionsView.swift
│       ├── IndexComparisonView.swift
│       └── SettingsView.swift
│
├── AlpacaTrackeriOS/           # Target iOS
│   ├── AlpacaTrackeriOSApp.swift
│   ├── ContentView.swift
│   └── Views/
│       ├── AccountBalanceCard.swift
│       ├── PerformanceView.swift
│       └── ...
│
├── Shared/                     # Código compartido
│   ├── Managers/
│   │   ├── AccountManager.swift
│   │   └── TradingDataManager.swift
│   ├── Models/
│   │   ├── AlpacaAccount.swift
│   │   ├── PortfolioHistory.swift
│   │   ├── Position.swift
│   │   └── IndexData.swift
│   └── Services/
│       ├── AlpacaAPIService.swift
│       ├── EncryptionService.swift
│       ├── SettingsManager.swift
│       └── TWRCalculator.swift
│
└── AlpacaTracker.xcodeproj/   # Proyecto Xcode
```

## 🛠️ Desarrollo

### Tecnologías

- **Lenguaje**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Charts**: Swift Charts
- **Crypto**: CryptoKit (AES-GCM)
- **Networking**: URLSession

### Características Técnicas

- **Arquitectura**: MVVM con ObservableObject
- **Concurrencia**: DispatchGroup para operaciones paralelas
- **Caché**: Almacenamiento local para balances y posiciones
- **Actualización automática**: Timers para refrescar datos periódicamente

## 📝 Notas

### Limitaciones

1. **Datos históricos**: Limitados por la disponibilidad de las APIs
2. **Sincronización**: Los datos se actualizan según el horario de mercado
3. **Correlación**: Cálculo simplificado para mejor rendimiento
4. **Volatilidad**: Anualizada asumiendo 252 días de trading

### Solución de Problemas

**No se cargan los datos de índices**
- Verifica tu conexión a internet
- Los datos pueden no estar disponibles fuera del horario de mercado
- Intenta con un período de tiempo diferente

**Errores de conexión con Alpaca**
- Verifica que las API keys sean correctas
- Confirma que la cuenta esté activa
- Revisa si estás usando el entorno correcto (Paper/Live)

**Rendimiento lento**
- Reduce el número de índices seleccionados
- Usa períodos de tiempo más cortos
- Los datos se cachean para mejorar el rendimiento

## 🔮 Futuras Mejoras

- [ ] Más índices: Añadir índices sectoriales y regionales
- [ ] Análisis avanzado: Sharpe ratio, beta, alpha
- [ ] Alertas: Notificaciones cuando se supere/descienda del índice
- [ ] Exportación: Guardar comparaciones como PDF o imagen
- [ ] Sincronización en la nube: Backup de cuentas y configuración
- [ ] Autenticación remota: Sistema de login/registro con Supabase

## 📄 Licencia

Este proyecto es privado y de uso interno.

## 👥 Contribuidores

- Desarrollado para Grecia Trading

---

**Versión**: Universal (macOS + iOS)  
**Última actualización**: 2025

