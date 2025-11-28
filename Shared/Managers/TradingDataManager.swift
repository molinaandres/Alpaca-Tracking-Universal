import Foundation
import Combine

/// Manager para manejar datos de trading (posiciones, trades, P&L)
class TradingDataManager: ObservableObject {
    @Published var positions: [UUID: [Position]] = [:]
    @Published var trades: [UUID: [Trade]] = [:]
    @Published var isLoading = false
    @Published var lastUpdateTime: Date?
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let positionsFileURL: URL
    private let tradesFileURL: URL
    
    private var updateTimer: Timer?
    private var apiServices: [UUID: AlpacaAPIService] = [:]
    
    init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        positionsFileURL = documentsDirectory.appendingPathComponent("alpaca_positions.json")
        tradesFileURL = documentsDirectory.appendingPathComponent("alpaca_trades.json")
        
        loadPositions()
        loadTrades()
        startPeriodicUpdates()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Configura el manager con los servicios API de las cuentas
    func configure(with apiServices: [UUID: AlpacaAPIService]) {
        self.apiServices = apiServices
        updateAllTradingData()
    }
    
    /// Actualiza los datos de trading para una cuenta específica
    func updateTradingData(for accountId: UUID) {
        guard let apiService = apiServices[accountId] else {
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        // Actualizar posiciones
        apiService.getPositions { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let positions):
                    self?.positions[accountId] = positions
                    self?.savePositions()
                case .failure(_):
                    // En caso de error, mantener las posiciones anteriores
                    break
                }
            }
        }
        
        // Actualizar trades
        apiService.getTrades { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.lastUpdateTime = Date()
                
                switch result {
                case .success(let trades):
                    self?.trades[accountId] = trades
                    self?.saveTrades()
                case .failure(_):
                    // En caso de error, mantener los trades anteriores
                    break
                }
            }
        }
    }
    
    /// Actualiza los datos de trading para todas las cuentas
    func updateAllTradingData() {
        for accountId in apiServices.keys {
            updateTradingData(for: accountId)
        }
    }
    
    /// Obtiene las posiciones para una cuenta específica
    func getPositions(for accountId: UUID) -> [Position] {
        return positions[accountId] ?? []
    }
    
    /// Obtiene los trades para una cuenta específica
    func getTrades(for accountId: UUID) -> [Trade] {
        return trades[accountId] ?? []
    }
    
    /// Obtiene el P&L total no realizado para una cuenta
    func getTotalUnrealizedPL(for accountId: UUID) -> Double {
        let accountPositions = getPositions(for: accountId)
        return accountPositions.reduce(0.0) { $0 + $1.unrealizedPLDouble }
    }
    
    /// Obtiene el P&L intradía total para una cuenta
    func getTotalIntradayPL(for accountId: UUID) -> Double {
        let accountPositions = getPositions(for: accountId)
        return accountPositions.reduce(0.0) { $0 + (Double($1.unrealizedIntradayPl) ?? 0.0) }
    }
    
    /// Obtiene el valor total de mercado para una cuenta
    func getTotalMarketValue(for accountId: UUID) -> Double {
        let accountPositions = getPositions(for: accountId)
        return accountPositions.reduce(0.0) { $0 + $1.marketValueDouble }
    }
    
    /// Obtiene el costo total base para una cuenta
    func getTotalCostBasis(for accountId: UUID) -> Double {
        let accountPositions = getPositions(for: accountId)
        return accountPositions.reduce(0.0) { $0 + (Double($1.costBasis) ?? 0.0) }
    }
    
    /// Obtiene las posiciones más rentables para una cuenta
    func getTopProfitablePositions(for accountId: UUID, limit: Int = 5) -> [Position] {
        let accountPositions = getPositions(for: accountId)
        return accountPositions
            .filter { $0.isProfitable }
            .sorted { $0.unrealizedPLDouble > $1.unrealizedPLDouble }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Obtiene las posiciones con mayores pérdidas para una cuenta
    func getTopLossPositions(for accountId: UUID, limit: Int = 5) -> [Position] {
        let accountPositions = getPositions(for: accountId)
        return accountPositions
            .filter { $0.unrealizedPLDouble < 0 }
            .sorted { $0.unrealizedPLDouble < $1.unrealizedPLDouble }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Obtiene los trades más recientes para una cuenta
    func getRecentTrades(for accountId: UUID, limit: Int = 10) -> [Trade] {
        let accountTrades = getTrades(for: accountId)
        return accountTrades
            .sorted { $0.filledAtDate > $1.filledAtDate }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Obtiene los trades ejecutados hoy para una cuenta
    func getTodayTrades(for accountId: UUID) -> [Trade] {
        let accountTrades = getTrades(for: accountId)
        let today = Calendar.current.startOfDay(for: Date())
        
        return accountTrades.filter { trade in
            Calendar.current.isDate(trade.filledAtDate, inSameDayAs: today)
        }
    }
    
    /// Obtiene los trades por símbolo para una cuenta
    func getTradesForSymbol(_ symbol: String, for accountId: UUID) -> [Trade] {
        let accountTrades = getTrades(for: accountId)
        return accountTrades.filter { $0.symbol == symbol }
    }
    
    // MARK: - Private Methods
    
    private func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { [weak self] _ in
            self?.updateAllTradingData()
        }
    }
    
    private func loadPositions() {
        do {
            if fileManager.fileExists(atPath: positionsFileURL.path) {
                let data = try Data(contentsOf: positionsFileURL)
                let decodedPositions = try JSONDecoder().decode([String: [Position]].self, from: data)
                positions = decodedPositions.compactMapKeys { UUID(uuidString: $0) }
            }
        } catch {
            // Error loading positions
        }
    }
    
    private func savePositions() {
        do {
            let stringKeys = positions.mapKeys { $0.uuidString }
            let data = try JSONEncoder().encode(stringKeys)
            try data.write(to: positionsFileURL)
        } catch {
            // Error saving positions
        }
    }
    
    private func loadTrades() {
        do {
            if fileManager.fileExists(atPath: tradesFileURL.path) {
                let data = try Data(contentsOf: tradesFileURL)
                let decodedTrades = try JSONDecoder().decode([String: [Trade]].self, from: data)
                trades = decodedTrades.compactMapKeys { UUID(uuidString: $0) }
            }
        } catch {
            // Error loading trades
        }
    }
    
    private func saveTrades() {
        do {
            let stringKeys = trades.mapKeys { $0.uuidString }
            let data = try JSONEncoder().encode(stringKeys)
            try data.write(to: tradesFileURL)
        } catch {
            // Error saving trades
        }
    }
}

// MARK: - Extensions

extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[transform(key)] = value
        }
        return result
    }
    
    func compactMapKeys<T: Hashable>(_ transform: (Key) -> T?) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            if let newKey = transform(key) {
                result[newKey] = value
            }
        }
        return result
    }
}
