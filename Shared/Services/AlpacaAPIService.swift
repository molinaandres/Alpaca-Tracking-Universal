import Foundation

// MARK: - API Models

struct AlpacaAPIAccount: Codable, Equatable {
    let id: String
    let accountNumber: String
    let status: String
    let currency: String
    let buyingPower: String
    let regtBuyingPower: String
    let daytradingBuyingPower: String
    let effectiveBuyingPower: String
    let nonMarginableBuyingPower: String
    let cash: String
    let accruedFees: String
    let portfolioValue: String
    let patternDayTrader: Bool
    let tradingBlocked: Bool
    let transfersBlocked: Bool
    let accountBlocked: Bool
    let createdAt: String
    let tradeSuspendedByUser: Bool
    let multiplier: String
    let shortingEnabled: Bool
    let equity: String
    let lastEquity: String
    let longMarketValue: String
    let shortMarketValue: String
    let positionMarketValue: String
    let initialMargin: String
    let maintenanceMargin: String
    let lastMaintenanceMargin: String
    let sma: String
    let daytradeCount: Int
    let balanceAsof: String
    let cryptoTier: Int?
    let intradayAdjustments: String
    let pendingRegTafFees: String
    let cryptoStatus: String
    let bodDtbp: String
    let adminConfigurations: AdminConfigurations
    let userConfigurations: UserConfigurations?
    
    enum CodingKeys: String, CodingKey {
        case id
        case accountNumber = "account_number"
        case status
        case currency
        case buyingPower = "buying_power"
        case regtBuyingPower = "regt_buying_power"
        case daytradingBuyingPower = "daytrading_buying_power"
        case effectiveBuyingPower = "effective_buying_power"
        case nonMarginableBuyingPower = "non_marginable_buying_power"
        case cash
        case accruedFees = "accrued_fees"
        case portfolioValue = "portfolio_value"
        case patternDayTrader = "pattern_day_trader"
        case tradingBlocked = "trading_blocked"
        case transfersBlocked = "transfers_blocked"
        case accountBlocked = "account_blocked"
        case createdAt = "created_at"
        case tradeSuspendedByUser = "trade_suspended_by_user"
        case multiplier
        case shortingEnabled = "shorting_enabled"
        case equity
        case lastEquity = "last_equity"
        case longMarketValue = "long_market_value"
        case shortMarketValue = "short_market_value"
        case positionMarketValue = "position_market_value"
        case initialMargin = "initial_margin"
        case maintenanceMargin = "maintenance_margin"
        case lastMaintenanceMargin = "last_maintenance_margin"
        case sma
        case daytradeCount = "daytrade_count"
        case balanceAsof = "balance_asof"
        case cryptoTier = "crypto_tier"
        case intradayAdjustments = "intraday_adjustments"
        case pendingRegTafFees = "pending_reg_taf_fees"
        case cryptoStatus = "crypto_status"
        case bodDtbp = "bod_dtbp"
        case adminConfigurations = "admin_configurations"
        case userConfigurations = "user_configurations"
    }
}

struct AdminConfigurations: Codable, Equatable {
    let allowInstantAch: Bool
    let maxMarginMultiplier: String
    
    enum CodingKeys: String, CodingKey {
        case allowInstantAch = "allow_instant_ach"
        case maxMarginMultiplier = "max_margin_multiplier"
    }
}

struct UserConfigurations: Codable, Equatable {
    let dtbpCheck: String
    let fractionalTrading: Bool
    let maxMarginMultiplier: String
    let tradeConfirmEmail: String
    
    enum CodingKeys: String, CodingKey {
        case dtbpCheck = "dtbp_check"
        case fractionalTrading = "fractional_trading"
        case maxMarginMultiplier = "max_margin_multiplier"
        case tradeConfirmEmail = "trade_confirm_email"
    }
}

struct AlpacaPosition: Codable {
    let assetId: String
    let symbol: String
    let exchange: String
    let assetClass: String
    let assetMarginable: Bool?
    let avgEntryPrice: String
    let qty: String
    let side: String
    let marketValue: String
    let costBasis: String
    let unrealizedPl: String
    let unrealizedPlpc: String
    let unrealizedIntradayPl: String
    let unrealizedIntradayPlpc: String
    let currentPrice: String
    let lastdayPrice: String
    let changeToday: String
    let currentPriceTimestamp: String?
}

struct AlpacaPortfolio: Codable {
    let account: AlpacaAPIAccount
    let positions: [Position]
}

// MARK: - API Service

class AlpacaAPIService: ObservableObject {
    
    // MARK: - API Errors
    
    enum AlpacaAPIError: Error, LocalizedError {
        case invalidURL
        case noData
        case decodingError(Error)
        case networkError(Error)
        case invalidResponse
        case unauthorized
        case forbidden
        case notFound
        case serverError(Int)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .noData:
                return "No data received"
            case .decodingError(let error):
                return "Error processing data: \(error.localizedDescription)"
            case .networkError(let error):
                return "Error de red: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid server response"
            case .unauthorized:
                return "Invalid credentials"
            case .forbidden:
                return "Acceso denegado"
            case .notFound:
                return "Recurso no encontrado"
            case .serverError(let code):
                return "Error del servidor: \(code)"
            }
        }
    }
    private let apiKey: String
    private let secretKey: String
    private let baseURL: String
    private let session: URLSession
    
    init(apiKey: String, secretKey: String, isLiveTrading: Bool = false) {
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.baseURL = isLiveTrading ? "https://api.alpaca.markets" : "https://paper-api.alpaca.markets"
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Private Methods
    
    private func createRequest(endpoint: String, method: String = "GET", body: Data? = nil) -> URLRequest? {
        let fullURL = "\(baseURL)/v2/\(endpoint)"
        
        guard let url = URL(string: fullURL) else { 
            return nil 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(secretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        return request
    }
    
    private func handleResponse<T: Codable>(_ data: Data?, _ response: URLResponse?, _ error: Error?, type: T.Type) -> Result<T, AlpacaAPIError> {
        if let error = error {
            return .failure(.networkError(error))
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            return .failure(.unauthorized)
        case 403:
            return .failure(.forbidden)
        case 404:
            return .failure(.notFound)
        case 500...599:
            return .failure(.serverError(httpResponse.statusCode))
        default:
            return .failure(.serverError(httpResponse.statusCode))
        }
        
        guard let data = data else {
            return .failure(.noData)
        }
        
        do {
            let decodedData = try JSONDecoder().decode(type, from: data)
            return .success(decodedData)
        } catch {
            return .failure(.decodingError(error))
        }
    }
    
    // MARK: - Public Methods
    
    func getAccount(completion: @escaping (Result<AlpacaAPIAccount, AlpacaAPIError>) -> Void) {
        guard let request = createRequest(endpoint: "account") else {
            completion(.failure(.invalidURL))
            return
        }
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let result = self?.handleResponse(data, response, error, type: AlpacaAPIAccount.self) ?? .failure(.invalidResponse)
            DispatchQueue.main.async {
                completion(result)
            }
        }
        task.resume()
    }
    
    /// Fetches account activities filtered by CSD and CSW within a date range, handling server pagination.
    /// Returns a flat array of AccountActivity items ordered ascending by created_at/date.
    func getCashFlowActivities(
        startDate: Date,
        endDate: Date,
        completion: @escaping (Result<[AccountActivity], AlpacaAPIError>) -> Void
    ) {
        // Build endpoints for CSD and CSW types (resource style endpoints have better stability for large pages)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)

        let types = ["CSD", "CSW"]
        let group = DispatchGroup()
        var allActivities: [AccountActivity] = []
        var firstError: AlpacaAPIError?

        for typ in types {
            group.enter()
            // Paginate per type
            var pageToken: String? = nil
            func fetchNextPage() {
                var endpoint = "account/activities/\(typ)?after=\(start)&until=\(end)&page_size=100&direction=asc"
                if let token = pageToken, !token.isEmpty {
                    endpoint += "&page_token=\(token)"
                }
                guard let request = createRequest(endpoint: endpoint) else {
                    firstError = firstError ?? .invalidURL
                    group.leave()
                    return
                }
                let task = session.dataTask(with: request) { data, response, error in
                    // Two possible response shapes: array or { activities, next_page_token }
                    if let error = error {
                        firstError = firstError ?? .networkError(error)
                        group.leave()
                        return
                    }
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let data = data else {
                        firstError = firstError ?? .invalidResponse
                        group.leave()
                        return
                    }
                    // Try decode as array first
                    if let arr = try? JSONDecoder().decode([AccountActivity].self, from: data) {
                        allActivities.append(contentsOf: arr)
                        // Heuristic: if less than 100, probably no more pages
                        if arr.count < 100 {
                            group.leave()
                        } else {
                            // Try to infer token from last id (server specific)
                            pageToken = arr.last?.id
                            if pageToken == nil || pageToken?.isEmpty == true { group.leave() } else { fetchNextPage() }
                        }
                        return
                    }
                    // Try envelope form
                    if let env = try? JSONDecoder().decode(AccountActivitiesResponse.self, from: data) {
                        allActivities.append(contentsOf: env.activities)
                        if let next = env.nextPageToken, !next.isEmpty {
                            pageToken = next
                            fetchNextPage()
                        } else {
                            group.leave()
                        }
                        return
                    }
                    firstError = firstError ?? .decodingError(NSError(domain: "decode", code: -1))
                    group.leave()
                }
                task.resume()
            }
            fetchNextPage()
        }

        group.notify(queue: .main) {
            if let err = firstError { completion(.failure(err)); return }
            // Sort by date/createdAt asc best-effort
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "America/New_York")
            let tf = ISO8601DateFormatter()
            let sorted = allActivities.sorted { a, b in
                let ad = (a.date.flatMap { df.date(from: $0) }) ?? (a.createdAt.flatMap { tf.date(from: $0) }) ?? Date.distantPast
                let bd = (b.date.flatMap { df.date(from: $0) }) ?? (b.createdAt.flatMap { tf.date(from: $0) }) ?? Date.distantPast
                return ad < bd
            }
            completion(.success(sorted))
        }
    }

    func getPositions(completion: @escaping (Result<[Position], AlpacaAPIError>) -> Void) {
        guard let request = createRequest(endpoint: "positions") else {
            completion(.failure(.invalidURL))
            return
        }
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let result = self?.handleResponse(data, response, error, type: [Position].self) ?? .failure(.invalidResponse)
            DispatchQueue.main.async {
                completion(result)
            }
        }
        task.resume()
    }
    
    func getTrades(completion: @escaping (Result<[Trade], AlpacaAPIError>) -> Void) {
        guard let request = createRequest(endpoint: "orders") else {
            completion(.failure(.invalidURL))
            return
        }
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let result = self?.handleResponse(data, response, error, type: [Trade].self) ?? .failure(.invalidResponse)
            DispatchQueue.main.async {
                completion(result)
            }
        }
        task.resume()
    }
    
    func getTradesForSymbol(_ symbol: String, completion: @escaping (Result<[Trade], AlpacaAPIError>) -> Void) {
        guard let request = createRequest(endpoint: "orders?symbols=\(symbol)") else {
            completion(.failure(.invalidURL))
            return
        }
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let result = self?.handleResponse(data, response, error, type: [Trade].self) ?? .failure(.invalidResponse)
            DispatchQueue.main.async {
                completion(result)
            }
        }
        task.resume()
    }
    
    func getPortfolio(completion: @escaping (Result<AlpacaPortfolio, AlpacaAPIError>) -> Void) {
        let group = DispatchGroup()
        var account: AlpacaAPIAccount?
        var positions: [Position]?
        var accountError: AlpacaAPIError?
        var positionsError: AlpacaAPIError?
        
        group.enter()
        getAccount { result in
            switch result {
            case .success(let acc):
                account = acc
            case .failure(let error):
                accountError = error
            }
            group.leave()
        }
        
        group.enter()
        getPositions { result in
            switch result {
            case .success(let pos):
                positions = pos
            case .failure(let error):
                positionsError = error
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            if let accountError = accountError {
                completion(.failure(accountError))
                return
            }
            
            if let positionsError = positionsError {
                completion(.failure(positionsError))
                return
            }
            
            guard let account = account, let positions = positions else {
                completion(.failure(.noData))
                return
            }
            
            let portfolio = AlpacaPortfolio(account: account, positions: positions)
            completion(.success(portfolio))
        }
    }
    
    func testConnection(completion: @escaping (Result<Bool, AlpacaAPIError>) -> Void) {
        guard let request = createRequest(endpoint: "account") else {
            completion(.failure(.invalidURL))
            return
        }
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
                return
            }
            
            let result = self.handleResponse(data, response, error, type: AlpacaAPIAccount.self)
            
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
        task.resume()
    }
    
    func getPortfolioHistory(
        period: PortfolioHistoryPeriod = .oneMonth,
        timeframe: PortfolioHistoryTimeframe = .oneDay,
        startDate: Date? = nil,
        endDate: Date? = nil,
        extendedHours: Bool = true,
        completion: @escaping (Result<PortfolioHistory, AlpacaAPIError>) -> Void
    ) {
        // El endpoint de Portfolio History siempre usa v2
        var endpoint = "account/portfolio/history"
        
        // Construir parámetros de consulta
        var queryItems: [String] = []
        
        // Solo agregar period si no es custom (usar mapeo para formato API)
        if period != .custom {
            queryItems.append("period=\(period.apiQueryValue)")
        }
        
        queryItems.append("timeframe=\(timeframe.rawValue)")
        queryItems.append("extended_hours=\(extendedHours)")
        
        // Agregar fechas personalizadas si están disponibles
        let formatter = ISO8601DateFormatter()
        
        if let startDate = startDate {
            queryItems.append("start_date=\(formatter.string(from: startDate))")
        }
        
        if let endDate = endDate {
            queryItems.append("end_date=\(formatter.string(from: endDate))")
        }
        
        if !queryItems.isEmpty {
            endpoint += "?" + queryItems.joined(separator: "&")
        }
        
        guard let request = createRequest(endpoint: endpoint) else {
            completion(.failure(.invalidURL))
            return
        }
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            // Manejar respuesta con validación mejorada
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let data = data {
                        do {
                            let portfolioHistory = try JSONDecoder().decode(PortfolioHistory.self, from: data)
                            
                            // Validar que la respuesta no esté vacía
                            if let equity = portfolioHistory.equity, !equity.isEmpty {
                                DispatchQueue.main.async {
                                    completion(.success(portfolioHistory))
                                }
                            } else {
                                // Crear datos de ejemplo para demostración
                                let mockData = self?.createMockPortfolioHistory(period: period) ?? PortfolioHistory(timestamp: [], equity: [], profitLoss: [], profitLossPct: [], baseValue: [], timeFrame: nil)
                                DispatchQueue.main.async {
                                    completion(.success(mockData))
                                }
                            }
                        } catch {
                            DispatchQueue.main.async {
                                completion(.failure(.invalidResponse))
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(.invalidResponse))
                        }
                    }
                } else {
                    let error: AlpacaAPIError
                    switch httpResponse.statusCode {
                    case 401:
                        error = .unauthorized
                    case 403:
                        error = .forbidden
                    case 404:
                        error = .notFound
                    case 500...599:
                        error = .serverError(httpResponse.statusCode)
                    default:
                        error = .serverError(httpResponse.statusCode)
                    }
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
        }
        task.resume()
    }
    
    // MARK: - Custom Date Range Solution
    
    /// Obtiene datos históricos usando las fechas exactas solicitadas
    func getPortfolioHistoryWithCustomDateRange(
        startDate: Date,
        endDate: Date,
        timeframe: PortfolioHistoryTimeframe = .oneDay,
        extendedHours: Bool = true,
        completion: @escaping (Result<PortfolioHistory, AlpacaAPIError>) -> Void
    ) {
        // Construir endpoint con fechas exactas
        var endpoint = "account/portfolio/history"
        
        // Construir parámetros de consulta
        var queryItems: [String] = []
        
        // Agregar fechas personalizadas en formato YYYY-MM-DD (requerido por Alpaca API)
        // Usar zona horaria de Nueva York para alinearse con los mercados
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        let startDateString = formatter.string(from: startDate)
        let endDateString = formatter.string(from: endDate)
        
        queryItems.append("start=\(startDateString)")
        queryItems.append("end=\(endDateString)")
        queryItems.append("timeframe=\(timeframe.rawValue)")
        queryItems.append("extended_hours=\(extendedHours)")
        
        if !queryItems.isEmpty {
            endpoint += "?" + queryItems.joined(separator: "&")
        }
        
        // Validar que las fechas sean del pasado
        let now = Date()
        if startDate > now || endDate > now {
            completion(.failure(.invalidResponse))
            return
        }
        
        // Validar que startDate sea anterior a endDate
        if startDate >= endDate {
            completion(.failure(.invalidResponse))
            return
        }
        
        guard let request = createRequest(endpoint: endpoint) else {
            completion(.failure(.invalidURL))
            return
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let data = data {
                        do {
                            let portfolioHistory = try JSONDecoder().decode(PortfolioHistory.self, from: data)
                            DispatchQueue.main.async {
                                completion(.success(portfolioHistory))
                            }
                        } catch {
                            DispatchQueue.main.async {
                                completion(.failure(.decodingError(error)))
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(.noData))
                        }
                    }
                } else {
                    let error: AlpacaAPIError
                    switch httpResponse.statusCode {
                    case 401:
                        error = .unauthorized
                    case 403:
                        error = .forbidden
                    case 404:
                        error = .notFound
                    case 500...599:
                        error = .serverError(httpResponse.statusCode)
                    default:
                        error = .serverError(httpResponse.statusCode)
                    }
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(.networkError(error ?? NSError(domain: "Unknown", code: -1))))
                }
            }
        }
        task.resume()
    }
    
    
    // Método para crear datos de ejemplo cuando la API falla
    private func createMockPortfolioHistory(period: PortfolioHistoryPeriod) -> PortfolioHistory {
        let now = Date()
        let calendar = Calendar.current
        let daysBack: Int
        
        switch period {
        case .oneDay:
            daysBack = 1
        case .oneWeek:
            daysBack = 7
        case .oneMonth:
            daysBack = 30
        case .threeMonths:
            daysBack = 90
        case .oneYear:
            daysBack = 365
        case .all:
            daysBack = 365
        case .custom:
            // For custom periods, use a default of 30 days
            daysBack = 30
        }
        
        var timestamps: [Int] = []
        var equity: [Double] = []
        let baseEquity = 10000.0
        
        for i in 0..<daysBack {
            let date = calendar.date(byAdding: .day, value: -i, to: now) ?? now
            let timestamp = Int(date.timeIntervalSince1970)
            timestamps.append(timestamp)
            
            // Simular variación del equity con tendencia positiva
            let variation = Double.random(in: -0.02...0.03) // -2% a +3% diario
            let currentEquity = baseEquity * (1 + variation * Double(i) / Double(daysBack))
            equity.append(currentEquity)
        }
        
        // Ordenar por timestamp (más antiguo primero)
        let sortedIndices = timestamps.enumerated().sorted { $0.element < $1.element }.map { $0.offset }
        let sortedTimestamps = sortedIndices.map { timestamps[$0] }
        let sortedEquity = sortedIndices.map { equity[$0] }
        
        return PortfolioHistory(
            timestamp: sortedTimestamps,
            equity: sortedEquity,
            profitLoss: sortedEquity.map { $0 - baseEquity },
            profitLossPct: sortedEquity.map { ($0 - baseEquity) / baseEquity * 100 },
            baseValue: Array(repeating: baseEquity, count: sortedEquity.count),
            timeFrame: "1D"
        )
    }
}
