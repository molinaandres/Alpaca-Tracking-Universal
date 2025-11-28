import Foundation
import Charts

// MARK: - Portfolio History Models

struct PortfolioHistory: Codable {
    let timestamp: [Int]?
    let equity: [Double]?
    let profitLoss: [Double]?
    let profitLossPct: [Double?]?  // Cambiado a [Double?]? para manejar valores null
    let baseValue: [Double]?
    let timeFrame: String?
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case equity
        case profitLoss = "profit_loss"
        case profitLossPct = "profit_loss_pct"
        case baseValue = "base_value"
        case timeFrame = "timeframe"
    }
    
    init(timestamp: [Int]? = nil, equity: [Double]? = nil, profitLoss: [Double]? = nil, profitLossPct: [Double?]? = nil, baseValue: [Double]? = nil, timeFrame: String? = nil) {
        self.timestamp = timestamp
        self.equity = equity
        self.profitLoss = profitLoss
        self.profitLossPct = profitLossPct
        self.baseValue = baseValue
        self.timeFrame = timeFrame
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        timestamp = try container.decodeIfPresent([Int].self, forKey: .timestamp)
        equity = try container.decodeIfPresent([Double].self, forKey: .equity)
        profitLoss = try container.decodeIfPresent([Double].self, forKey: .profitLoss)
        profitLossPct = try container.decodeIfPresent([Double?].self, forKey: .profitLossPct)  // Cambiado a [Double?]
        timeFrame = try container.decodeIfPresent(String.self, forKey: .timeFrame)
        
        // Handle baseValue that can be either a single number or an array
        if let baseValueArray = try? container.decode([Double].self, forKey: .baseValue) {
            baseValue = baseValueArray
        } else if let baseValueSingle = try? container.decode(Double.self, forKey: .baseValue) {
            // If it's a single number, create an array with that value
            baseValue = [baseValueSingle]
        } else {
            baseValue = nil
        }
    }
}

struct PortfolioHistoryDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let equity: Double
    let profitLoss: Double
    let profitLossPct: Double  // Siempre será un valor válido (0.0 si era null)
    let baseValue: Double
}

enum PortfolioHistoryPeriod: String, CaseIterable, Identifiable {
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case all = "all"
    case custom = "custom"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .oneDay: return "1 Day"
        case .oneWeek: return "1 Week"
        case .oneMonth: return "1 Month"
        case .threeMonths: return "3 Months"
        case .oneYear: return "1 Year"
        case .all: return "All"
        case .custom: return "Custom"
        }
    }
    
    /// Returns the custom date range for predefined periods
    /// - Parameters:
    ///   - account: The account to check against firstTradeDate
    ///   - portfolioHistory: Optional portfolio history data to find first equity > 0 point
    /// - Returns: A tuple with startDate and endDate, ensuring startDate is not before firstTradeDate
    func customDateRange(for account: AlpacaAccount, portfolioHistory: [PortfolioHistoryDataPoint]? = nil) -> (startDate: Date, endDate: Date) {
        let calendar = Calendar.current
        let today = Date()
        
        let calculatedStartDate: Date
        switch self {
        case .oneDay:
            calculatedStartDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        case .oneWeek:
            calculatedStartDate = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        case .oneMonth:
            calculatedStartDate = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        case .threeMonths:
            calculatedStartDate = calendar.date(byAdding: .month, value: -3, to: today) ?? today
        case .oneYear:
            calculatedStartDate = calendar.date(byAdding: .year, value: -1, to: today) ?? today
        case .all:
            // For Total Accounts, use first equity > 0 point if available
            if account.name == "Total Accounts", let history = portfolioHistory {
                if let firstEquityPoint = history.first(where: { $0.equity > 0 }) {
                    calculatedStartDate = firstEquityPoint.timestamp
                } else {
                    calculatedStartDate = calendar.date(byAdding: .year, value: -5, to: today) ?? today
                }
            } else {
                calculatedStartDate = calendar.date(byAdding: .year, value: -5, to: today) ?? today
            }
        case .custom:
            // For custom, return default values that will be overridden by user selection
            calculatedStartDate = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        }
        
        // Ensure start date is not before the first trade date
        var finalStartDate: Date
        if let firstTradeDate = account.firstTradeDate {
            finalStartDate = max(calculatedStartDate, firstTradeDate)
        } else {
            finalStartDate = calculatedStartDate
        }

        // If Total Accounts and we have history, shift start to the first point where equity > 0
        // and there is a variation between day t and t+1
        if account.name == "Total Accounts", let history = portfolioHistory {
            if let idx = history.firstNonZeroChangeIndex(startDate: finalStartDate) {
                finalStartDate = history[idx].timestamp
            } else if let firstNonZero = history.first(where: { $0.timestamp >= finalStartDate && $0.equity > 0 }) {
                finalStartDate = firstNonZero.timestamp
            }
        }
        
        return (finalStartDate, today)
    }

    /// Value expected by Alpaca API for the `period` query param
    var apiQueryValue: String {
        switch self {
        case .oneYear:
            // Alpaca expects "A" for years, not "Y"
            return "1A"
        default:
            return self.rawValue
        }
    }
}

// MARK: - Helpers for history trimming rules
extension Array where Element == PortfolioHistoryDataPoint {
    /// Returns the first index i such that equity(i) > 0 and equity(i+1) != equity(i)
    /// Optionally enforces a minimum start date constraint
    func firstNonZeroChangeIndex(startDate: Date? = nil) -> Int? {
        guard count >= 2 else { return firstIndex(where: { ($0.equity > 0) && ($0.timestamp >= (startDate ?? Date.distantPast)) }) }
        for i in 0..<(count - 1) {
            let current = self[i]
            let next = self[i + 1]
            if let startDate = startDate, current.timestamp < startDate { continue }
            if current.equity > 0 && next.equity != current.equity {
                return i
            }
        }
        // Fallback: first equity > 0 honoring the startDate
        return firstIndex(where: { ($0.equity > 0) && ($0.timestamp >= (startDate ?? Date.distantPast)) })
    }
}

enum PortfolioHistoryTimeframe: String, CaseIterable, Identifiable {
    case oneMinute = "1Min"
    case fiveMinutes = "5Min"
    case fifteenMinutes = "15Min"
    case oneHour = "1H"
    case oneDay = "1D"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .oneMinute: return "1 Minuto"
        case .fiveMinutes: return "5 Minutos"
        case .fifteenMinutes: return "15 Minutos"
        case .oneHour: return "1 Hora"
        case .oneDay: return "1 Day"
        }
    }
}

// MARK: - Compatibility Matrix
extension PortfolioHistoryPeriod {
    /// Returns the valid timeframes for a given period based on Alpaca API limitations
    /// This is used for UI purposes and doesn't require account information
    var validTimeframes: [PortfolioHistoryTimeframe] {
        switch self {
        case .oneDay:
            // For 1 day, allow all timeframes including oneDay
            return [.oneMinute, .fiveMinutes, .fifteenMinutes, .oneHour, .oneDay]
        case .oneWeek:
            // For 1 week, only day timeframe is available
            return [.oneDay]
        case .oneMonth:
            // For 1 month, day timeframe is most appropriate
            return [.oneDay]
        case .threeMonths:
            // For 3 months, day timeframe is most appropriate
            return [.oneDay]
        case .oneYear:
            // For 1 year, day timeframe is most appropriate
            return [.oneDay]
        case .all:
            // For all time, day timeframe is most appropriate
            return [.oneDay]
        case .custom:
            // For custom periods, return all timeframes
            return PortfolioHistoryTimeframe.allCases
        }
    }
}

// MARK: - Date Adjustment Utilities

extension PortfolioHistoryTimeframe {
    /// Ajusta la fecha de Alpaca según la granularidad
    /// Para granularidades de horas o minutos: mantiene la fecha original
    /// Para granularidades >= 1 día: resta 2 horas y 1 minuto para ajustar al cierre del día anterior
    func adjustAlpacaDate(_ date: Date) -> Date {
        switch self {
        case .oneMinute, .fiveMinutes, .fifteenMinutes, .oneHour:
            // Para granularidades menores a 1 día, mantener la fecha original
            return date
        case .oneDay:
            // Para 1 día y superiores, restar 2 horas y 1 minuto
            let calendar = Calendar.current
            return calendar.date(byAdding: .minute, value: -121, to: date) ?? date // 2h 1min = 121 minutos
        }
    }
}