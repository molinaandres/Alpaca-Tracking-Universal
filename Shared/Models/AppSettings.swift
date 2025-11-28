import Foundation
import SwiftUI

// MARK: - App Settings Model
struct AppSettings: Codable {
    var selectedAccountId: String?
    var defaultPeriod: PortfolioPeriod
    var defaultTimeframe: Timeframe
    var showExtendedHours: Bool
    var autoRefresh: Bool
    var refreshInterval: Int // in minutes
    var showTotalAccounts: Bool
    var accountsOrder: [String] // Persisted order of AlpacaAccount ids (uuidString)
    var twrPerAccount: [String: Bool] // accountId(uuidString) -> showTWR
    
    init() {
        self.selectedAccountId = nil
        self.defaultPeriod = .oneMonth
        self.defaultTimeframe = .oneDay
        self.showExtendedHours = false
        self.autoRefresh = true
        self.refreshInterval = 5
        self.showTotalAccounts = false
        self.accountsOrder = []
        self.twrPerAccount = [:]
    }
}


// MARK: - Portfolio Period
enum PortfolioPeriod: String, CaseIterable, Codable {
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case allTime = "All"
    case custom = "Custom"
    
    var displayName: String {
        switch self {
        case .oneDay: return "1 Day"
        case .oneWeek: return "1 Week"
        case .oneMonth: return "1 Month"
        case .threeMonths: return "3 Months"
        case .oneYear: return "1 Year"
        case .allTime: return "All"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Timeframe
enum Timeframe: String, CaseIterable, Codable {
    case oneMinute = "1Min"
    case fiveMinutes = "5Min"
    case fifteenMinutes = "15Min"
    case oneHour = "1Hour"
    case oneDay = "1Day"
    
    var displayName: String {
        switch self {
        case .oneMinute: return "1 Min"
        case .fiveMinutes: return "5 Min"
        case .fifteenMinutes: return "15 Min"
        case .oneHour: return "1 Hora"
        case .oneDay: return "1 Day"
        }
    }
}

// MARK: - Account Configuration
struct AccountConfiguration: Codable, Identifiable {
    let id: String
    let name: String
    let apiKey: String
    let secretKey: String
    let isLive: Bool
    let isDefault: Bool
    let createdAt: Date
    
    // Nuevos campos de configuración
    let leverage: Double
    let budget: Int // Porcentaje de 0 a 100 en saltos de 10
    let canCloseAllPositions: Bool
    let canDisconnectFromGrecia: Bool
    
    init(name: String, apiKey: String, secretKey: String, isLive: Bool, isDefault: Bool = false, leverage: Double = 1.0, budget: Int = 100, canCloseAllPositions: Bool = false, canDisconnectFromGrecia: Bool = false) {
        self.id = UUID().uuidString
        self.name = name
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.isLive = isLive
        self.isDefault = isDefault
        self.createdAt = Date()
        self.leverage = leverage
        self.budget = budget
        self.canCloseAllPositions = canCloseAllPositions
        self.canDisconnectFromGrecia = canDisconnectFromGrecia
    }
}

// MARK: - Convenience initializer to rebuild from existing id
extension AccountConfiguration {
    init(id: String, name: String, apiKey: String, secretKey: String, isLive: Bool, isDefault: Bool, createdAt: Date, leverage: Double, budget: Int, canCloseAllPositions: Bool, canDisconnectFromGrecia: Bool) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.isLive = isLive
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.leverage = leverage
        self.budget = budget
        self.canCloseAllPositions = canCloseAllPositions
        self.canDisconnectFromGrecia = canDisconnectFromGrecia
    }
}
