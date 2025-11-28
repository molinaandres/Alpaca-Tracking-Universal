import Foundation

struct TWRPoint: Identifiable, Codable {
    var id = UUID()
    let date: String
    let equity: Double
    let pnl: Double
    let pnl_pct: Double
    let deposits: Double
    let withdrawals: Double
    let net_cash_flow: Double
    let daily_return: Double
    let cumulative_twr: Double
    
    var timestamp: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.date(from: date) ?? Date()
    }
}

enum TWRCalculatorError: Error, LocalizedError {
    case noPortfolioData
    case noActivitiesData
    case calculationError(String)
    
    var errorDescription: String? {
        switch self {
        case .noPortfolioData: return "No portfolio data available"
        case .noActivitiesData: return "No activities data available"
        case .calculationError(let msg): return "TWR calculation error: \(msg)"
        }
    }
}

final class TWRCalculator {
    
    static func calculateTWR(
        portfolioHistory: [PortfolioHistoryPoint],
        activities: [AccountActivity],
        startDate: Date,
        endDate: Date
    ) throws -> [TWRPoint] {
        
        guard !portfolioHistory.isEmpty else {
            throw TWRCalculatorError.noPortfolioData
        }
        
        // Filter activities for CSD and CSW within date range
        let cashFlowActivities = activities.filter { activity in
            guard let activityDate = activity.date else { return false }
            return (activity.activity_type == "CSD" || activity.activity_type == "CSW") &&
                   activityDate >= startDate && activityDate <= endDate
        }
        
        // Create cash flow map by date
        var cashFlowMap: [String: Double] = [:]
        for activity in cashFlowActivities {
            guard let activityDate = activity.date else { continue }
            let dateString = formatDate(activityDate)
            let amount = Double(activity.net_amount ?? "0.0") ?? 0.0
            
            if activity.activity_type == "CSD" {
                cashFlowMap[dateString, default: 0.0] += amount
            } else if activity.activity_type == "CSW" {
                cashFlowMap[dateString, default: 0.0] -= amount
            }
        }
        
        // Sort portfolio history by date
        let sortedHistory = portfolioHistory.sorted { $0.timestamp < $1.timestamp }
        
        var twrPoints: [TWRPoint] = []
        var cumulativeTWR: Double = 1.0
        var previousEquity: Double = 0.0
        
        for (index, point) in sortedHistory.enumerated() {
            let dateString = formatDate(point.timestamp)
            let currentEquity = point.equity
            let pnl = point.profit_loss
            let pnlPct = point.profit_loss_percentage
            
            // Get cash flow for this date
            let netCashFlow = cashFlowMap[dateString] ?? 0.0
            let deposits = max(0, netCashFlow)
            let withdrawals = max(0, -netCashFlow)
            
            // Calculate daily return
            var dailyReturn: Double = 0.0
            
            if index == 0 {
                // First day - no previous equity to compare
                dailyReturn = 0.0
            } else if previousEquity == 0.0 {
                // Previous equity was zero
                dailyReturn = 0.0
            } else {
                // Calculate return adjusting for cash flows
                // Cash flow should be applied to the day it affects equity (next trading day)
                let adjustedEquity = currentEquity - netCashFlow
                dailyReturn = (adjustedEquity / previousEquity) - 1.0
            }
            
            // Update cumulative TWR
            cumulativeTWR *= (1.0 + dailyReturn)
            
            let twrPoint = TWRPoint(
                date: dateString,
                equity: currentEquity,
                pnl: pnl,
                pnl_pct: pnlPct,
                deposits: deposits,
                withdrawals: withdrawals,
                net_cash_flow: netCashFlow,
                daily_return: dailyReturn,
                cumulative_twr: cumulativeTWR - 1.0 // Convert to percentage change
            )
            
            twrPoints.append(twrPoint)
            previousEquity = currentEquity
        }
        
        return twrPoints
    }
    
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter.string(from: date)
    }
}
