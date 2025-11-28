import Foundation

// MARK: - Index Models

/// Representa un índice financiero para comparación
struct Index: Identifiable, Codable, Equatable {
    let id: String
    let symbol: String
    let name: String
    let description: String
    let currency: String
    let isAvailable: Bool
    
    static let sp500 = Index(
        id: "sp500",
        symbol: "^GSPC",
        name: "S&P 500",
        description: "Standard & Poor's 500",
        currency: "USD",
        isAvailable: true
    )
    
    static let nasdaq = Index(
        id: "nasdaq",
        symbol: "^IXIC",
        name: "NASDAQ",
        description: "NASDAQ Composite",
        currency: "USD",
        isAvailable: true
    )
    
    static let msciWorld = Index(
        id: "msci_world",
        symbol: "URTH",
        name: "MSCI World",
        description: "MSCI World Index (via URTH ETF)",
        currency: "USD",
        isAvailable: true
    )
    
    static let allIndices: [Index] = [.sp500, .nasdaq, .msciWorld]
}

/// Punto de datos históricos de un índice
struct IndexDataPoint: Identifiable, Codable, Equatable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let change: Double
    let changePercent: Double
    
    enum CodingKeys: String, CodingKey {
        case timestamp, value, change, changePercent
    }
}

/// Datos históricos completos de un índice
struct IndexHistory: Codable, Equatable {
    let index: Index
    let dataPoints: [IndexDataPoint]
    let startDate: Date
    let endDate: Date
    let timeframe: String
    
    enum CodingKeys: String, CodingKey {
        case index, dataPoints, startDate, endDate, timeframe
    }
}

/// Resultado de comparación entre portfolio e índice
struct IndexComparison: Identifiable, Codable, Equatable {
    let id = UUID()
    let index: Index
    let portfolioReturn: Double
    let indexReturn: Double
    let outperformance: Double
    let correlation: Double
    let volatilityRatio: Double
    
    enum CodingKeys: String, CodingKey {
        case index, portfolioReturn, indexReturn, outperformance, correlation, volatilityRatio
    }
}

// MARK: - Yahoo Finance API Models

/// Respuesta de la API de Yahoo Finance
struct YahooFinanceResponse: Codable {
    let chart: YahooChart?
}

struct YahooChart: Codable {
    let result: [YahooResult]?
    let error: YahooError?
}

struct YahooResult: Codable {
    let meta: YahooMeta?
    let timestamp: [Int]?
    let indicators: YahooIndicators?
}

struct YahooMeta: Codable {
    let currency: String?
    let symbol: String?
    let exchangeName: String?
    let instrumentType: String?
    let firstTradeDate: Int?
    let regularMarketTime: Int?
    let gmtoffset: Int?
    let timezone: String?
    let exchangeTimezoneName: String?
    let regularMarketPrice: Double?
    let chartPreviousClose: Double?
    let previousClose: Double?
    let scale: Int?
    let priceHint: Int?
    let currentTradingPeriod: YahooTradingPeriod?
    let tradingPeriods: [[YahooTradingPeriod]]?
    let dataGranularity: String?
    let range: String?
    let validRanges: [String]?
}

struct YahooTradingPeriod: Codable {
    let timezone: String?
    let start: Int?
    let end: Int?
    let gmtoffset: Int?
}

struct YahooIndicators: Codable {
    let quote: [YahooQuote]?
    let adjclose: [YahooAdjClose]?
}

struct YahooQuote: Codable {
    let open: [Double?]?
    let high: [Double?]?
    let low: [Double?]?
    let close: [Double?]?
    let volume: [Int?]?
}

struct YahooAdjClose: Codable {
    let adjclose: [Double?]?
}

struct YahooError: Codable {
    let code: String?
    let description: String?
}

// MARK: - Index Data Manager

class IndexDataManager: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var indexHistories: [String: IndexHistory] = [:]
    @Published var lastUpdateTimes: [String: Date] = [:]
    
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.httpMaximumConnectionsPerHost = 6
        self.session = URLSession(configuration: config)
    }
    
    /// Obtiene datos históricos de un índice
    func fetchIndexHistory(
        index: Index,
        startDate: Date,
        endDate: Date,
        completion: @escaping (Result<IndexHistory, Error>) -> Void
    ) {
        isLoading = true
        errorMessage = nil
        
        // Normalizar a límites de día en UTC para alinear exactamente con Alpaca
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let normalizedStart = utcCalendar.startOfDay(for: startDate)
        // Yahoo usa period2 EXCLUSIVO. Para incluir el último día, sumamos 1 día al inicio del día final
        let normalizedEndExclusive = utcCalendar.date(byAdding: .day, value: 1, to: utcCalendar.startOfDay(for: endDate)) ?? endDate
        
        // Construir URL para Yahoo Finance API
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(index.symbol)?period1=\(Int(normalizedStart.timeIntervalSince1970))&period2=\(Int(normalizedEndExclusive.timeIntervalSince1970))&interval=1d&includePrePost=true&events=div%2Csplit"
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.isLoading = false
                completion(.failure(IndexDataError.invalidURL))
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        self?.errorMessage = "HTTP error: \(httpResponse.statusCode)"
                        completion(.failure(IndexDataError.apiError("HTTP error: \(httpResponse.statusCode)")))
                        return
                    }
                }
                
                guard let data = data else {
                    self?.errorMessage = "No se recibieron datos"
                    completion(.failure(IndexDataError.noData))
                    return
                }
                
                
                do {
                    let yahooResponse = try JSONDecoder().decode(YahooFinanceResponse.self, from: data)
                    
                    
                    if let error = yahooResponse.chart?.error {
                        self?.errorMessage = error.description ?? "Error desconocido"
                        completion(.failure(IndexDataError.apiError(error.description ?? "Error de la API")))
                        return
                    }
                    
                    guard let result = yahooResponse.chart?.result?.first,
                          let timestamps = result.timestamp,
                          let quotes = result.indicators?.quote?.first,
                          let closes = quotes.close else {
                        self?.errorMessage = "Index data not available"
                        completion(.failure(IndexDataError.noData))
                        return
                    }
                    
                    
                    let indexHistory = self?.processYahooData(
                        index: index,
                        timestamps: timestamps,
                        closes: closes,
                        startDate: normalizedStart,
                        endDate: utcCalendar.date(byAdding: .second, value: -1, to: normalizedEndExclusive) ?? endDate
                    )
                    
                    if let history = indexHistory {
                        self?.indexHistories[index.id] = history
                        self?.lastUpdateTimes[index.id] = Date()
                        completion(.success(history))
                    } else {
                        completion(.failure(IndexDataError.processingError))
                    }
                    
                } catch {
                    self?.errorMessage = "Error al procesar datos: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }
        
        task.resume()
    }
    
    /// Obtiene datos históricos de múltiples índices
    func fetchMultipleIndexHistories(
        indices: [Index],
        startDate: Date,
        endDate: Date,
        completion: @escaping (Result<[IndexHistory], Error>) -> Void
    ) {
        let group = DispatchGroup()
        var results: [IndexHistory] = []
        var errors: [Error] = []
        
        for index in indices {
            group.enter()
            fetchIndexHistory(index: index, startDate: startDate, endDate: endDate) { result in
                switch result {
                case .success(let history):
                    results.append(history)
                case .failure(let error):
                    errors.append(error)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if errors.isEmpty {
                completion(.success(results))
            } else {
                completion(.failure(IndexDataError.multipleErrors(errors)))
            }
        }
    }
    
    /// Refreshes all indices data
    func refreshAllIndices(completion: @escaping (Result<[IndexHistory], Error>) -> Void) {
        let indices = Index.allIndices
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) ?? endDate
        
        fetchMultipleIndexHistories(
            indices: indices,
            startDate: startDate,
            endDate: endDate,
            completion: completion
        )
    }
    
    private func processYahooData(
        index: Index,
        timestamps: [Int],
        closes: [Double?],
        startDate: Date,
        endDate: Date
    ) -> IndexHistory? {
        
        var dataPoints: [IndexDataPoint] = []
        
        for (index, timestamp) in timestamps.enumerated() {
            guard index < closes.count,
                  let close = closes[index] else { 
                continue 
            }
            
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            
            // Filtrar por rango de fechas
            if date >= startDate && date <= endDate {
                let change = index > 0 ? close - (closes[index - 1] ?? close) : 0
                let changePercent = index > 0 && closes[index - 1] != nil ? (change / closes[index - 1]!) * 100 : 0
                
                let dataPoint = IndexDataPoint(
                    timestamp: date,
                    value: close,
                    change: change,
                    changePercent: changePercent
                )
                dataPoints.append(dataPoint)
            }
        }
        
        // Ordenar por fecha
        dataPoints.sort { $0.timestamp < $1.timestamp }
        
        // Aplicar filtro adicional de value > 0 DESPUÉS del filtro de fechas
        // para ser consistente con el filtrado de Alpaca (equity > 0)
        let filteredDataPoints = dataPoints.filter { $0.value > 0 }
        
        return IndexHistory(
            index: index,
            dataPoints: filteredDataPoints,
            startDate: startDate,
            endDate: endDate,
            timeframe: "1d"
        )
    }
    
    /// Calcula comparación entre portfolio e índice
    func calculateComparison(
        portfolioHistory: [PortfolioHistoryDataPoint],
        indexHistory: IndexHistory,
        isTotalAccounts: Bool = false
    ) -> IndexComparison? {
        guard !portfolioHistory.isEmpty,
              !indexHistory.dataPoints.isEmpty else {
            return nil
        }
        
        // Aplicar el mismo filtro que usa el gráfico: solo fechas que existen en el portfolio procesado
        let portfolioDates = Set(portfolioHistory.map { normalizeDateToDay($0.timestamp) })
        
        let filteredIndexDataPoints = indexHistory.dataPoints.filter { dataPoint in
            let normalizedDate = normalizeDateToDay(dataPoint.timestamp)
            return portfolioDates.contains(normalizedDate)
        }
        
        guard !filteredIndexDataPoints.isEmpty,
              let firstPortfolio = portfolioHistory.first,
              let lastPortfolio = portfolioHistory.last,
              let firstIndex = filteredIndexDataPoints.first,
              let lastIndex = filteredIndexDataPoints.last else {
            return nil
        }
        
        // Calcular retornos usando los datos filtrados (igual que el gráfico)
        // Si la serie de portfolio proviene de TWR (profitLossPct poblado o baseValue == equity),
        // usar directamente el porcentaje acumulado (último punto). Evita divisiones por 0 e infinitos.
        let isTWRSourced = portfolioHistory.contains { $0.profitLossPct != 0 } 
            || portfolioHistory.allSatisfy { $0.baseValue == $0.equity }
        
        let portfolioReturn: Double
        if isTotalAccounts || isTWRSourced {
            portfolioReturn = lastPortfolio.profitLossPct
        } else {
            let denom = firstPortfolio.equity
            portfolioReturn = denom != 0 ? ((lastPortfolio.equity - denom) / denom) * 100 : 0
        }
        let indexReturn = ((lastIndex.value - firstIndex.value) / firstIndex.value) * 100
        
        // Calcular outperformance
        let outperformance = portfolioReturn - indexReturn
        
        // Calcular correlación usando los datos filtrados
        let filteredIndexHistory = IndexHistory(
            index: indexHistory.index,
            dataPoints: filteredIndexDataPoints,
            startDate: indexHistory.startDate,
            endDate: indexHistory.endDate,
            timeframe: indexHistory.timeframe
        )
        let correlation = calculateCorrelation(portfolioHistory: portfolioHistory, indexHistory: filteredIndexHistory)
        
        // Calcular ratio de volatilidad usando los datos filtrados
        let portfolioVolatility = calculateVolatility(portfolioHistory: portfolioHistory)
        let indexVolatility = calculateVolatility(indexHistory: filteredIndexHistory)
        let volatilityRatio = indexVolatility > 0 ? portfolioVolatility / indexVolatility : 1.0
        
        return IndexComparison(
            index: indexHistory.index,
            portfolioReturn: portfolioReturn,
            indexReturn: indexReturn,
            outperformance: outperformance,
            correlation: correlation,
            volatilityRatio: volatilityRatio
        )
    }
    
    // Función auxiliar para normalizar fechas (igual que en el gráfico)
    private func normalizeDateToDay(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? date
    }
    
    private func calculateCorrelation(
        portfolioHistory: [PortfolioHistoryDataPoint],
        indexHistory: IndexHistory
    ) -> Double {
        // Correlación de Pearson entre retornos diarios emparejados por fecha (NY timezone)
        guard portfolioHistory.count > 1 && indexHistory.dataPoints.count > 1 else { return 0.0 }

        var nyCal = Calendar.current
        nyCal.timeZone = TimeZone(identifier: "America/New_York") ?? nyCal.timeZone

        func day(_ d: Date) -> Date { nyCal.startOfDay(for: d) }

        // Serie diaria única por día (portfolio)
        // Si hubiese múltiples puntos en un día, usamos el último (cierre)
        var portfolioByDay: [Date: Double] = [:]
        for p in portfolioHistory {
            portfolioByDay[day(p.timestamp)] = p.equity
        }

        // Serie diaria única por día (índice)
        var indexByDay: [Date: Double] = [:]
        for p in indexHistory.dataPoints {
            indexByDay[day(p.timestamp)] = p.value
        }

        // Fechas comunes ordenadas
        let commonDays = Array(Set(portfolioByDay.keys).intersection(indexByDay.keys)).sorted()
        guard commonDays.count > 2 else { return 0.0 }

        // Construir retornos diarios emparejados (requiere día anterior también común)
        var portfolioReturns: [Double] = []
        var indexReturns: [Double] = []

        for i in 1..<commonDays.count {
            let dPrev = commonDays[i - 1]
            let dCurr = commonDays[i]
            guard let pPrev = portfolioByDay[dPrev], let pCurr = portfolioByDay[dCurr], pPrev != 0,
                  let iPrev = indexByDay[dPrev], let iCurr = indexByDay[dCurr], iPrev != 0 else { continue }

            let pr = (pCurr - pPrev) / pPrev
            let ir = (iCurr - iPrev) / iPrev
            portfolioReturns.append(pr)
            indexReturns.append(ir)
        }

        let n = min(portfolioReturns.count, indexReturns.count)
        guard n > 1 else { return 0.0 }

        let pMean = portfolioReturns.prefix(n).reduce(0, +) / Double(n)
        let iMean = indexReturns.prefix(n).reduce(0, +) / Double(n)

        var num = 0.0
        var pVar = 0.0
        var iVar = 0.0
        for i in 0..<n {
            let pd = portfolioReturns[i] - pMean
            let id = indexReturns[i] - iMean
            num += pd * id
            pVar += pd * pd
            iVar += id * id
        }

        let den = sqrt(pVar * iVar)
        return den > 0 ? num / den : 0.0
    }
    
    private func calculateVolatility(portfolioHistory: [PortfolioHistoryDataPoint]) -> Double {
        guard portfolioHistory.count > 1 else { return 0.0 }
        
        let returns = portfolioHistory.enumerated().compactMap { index, point in
            index > 0 ? (point.equity - portfolioHistory[index - 1].equity) / portfolioHistory[index - 1].equity : nil
        }
        
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count)
        return sqrt(variance) * sqrt(252) // Anualizado
    }
    
    private func calculateVolatility(indexHistory: IndexHistory) -> Double {
        guard indexHistory.dataPoints.count > 1 else { return 0.0 }
        
        let returns = indexHistory.dataPoints.enumerated().compactMap { index, point in
            index > 0 ? (point.value - indexHistory.dataPoints[index - 1].value) / indexHistory.dataPoints[index - 1].value : nil
        }
        
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count)
        return sqrt(variance) * sqrt(252) // Anualizado
    }
}

// MARK: - Errors

enum IndexDataError: Error, LocalizedError {
    case invalidURL
    case noData
    case apiError(String)
    case processingError
    case multipleErrors([Error])
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No index data received"
        case .apiError(let message):
            return "API Error: \(message)"
        case .processingError:
            return "Error processing index data"
        case .multipleErrors(let errors):
            return "Multiple errors: \(errors.map { $0.localizedDescription }.joined(separator: ", "))"
        }
    }
}
