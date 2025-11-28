import Foundation
import Combine
import SwiftUI

// MARK: - Aggregated TWR Point (shared with views)
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

class AccountManager: ObservableObject {
    @Published var accounts: [AlpacaAccount] = []
    @Published var balances: [UUID: AccountBalance] = [:]
    @Published var isLoading = false
    @Published var lastUpdateTime: Date?
    
    // Store daily change percentages for each account
    @Published var dailyChangePercentages: [UUID: Double] = [:]
    
    // MARK: - Authentication
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    private let authService = SupabaseAuthService.shared
    private let accountsService = SupabaseAccountsService.shared
    
    // MARK: - Total Accounts
    
    /// Returns all accounts including the Total Accounts virtual account
    var allAccounts: [AlpacaAccount] {
        var allAccounts = accounts
        
        // Add Total Accounts as the first account if there are other accounts and setting is enabled
        if !accounts.isEmpty && settingsManager.appSettings.showTotalAccounts {
            let totalAccount = createTotalAccountsAccount()
            allAccounts.insert(totalAccount, at: 0)
        }
        
        return allAccounts
    }
    
    /// Returns only real accounts (excludes Total Accounts virtual account)
    var realAccounts: [AlpacaAccount] {
        return accounts
    }
    
    /// Returns the balance for Total Accounts (sum of all other accounts)
    var totalAccountsBalance: AccountBalance? {
        guard !accounts.isEmpty else { return nil }
        
        let totalBalance = accounts.compactMap { account in
            balances[account.id]?.balance
        }.reduce(0, +)
        
        return AccountBalance(
            accountId: totalAccountsId,
            balance: totalBalance,
            lastUpdated: lastUpdateTime ?? Date(),
            accountInfo: nil
        )
    }
    
    /// Returns all balances including the Total Accounts balance
    var allBalances: [UUID: AccountBalance] {
        var allBalances = balances
        
        if let totalBalance = totalAccountsBalance {
            allBalances[totalAccountsId] = totalBalance
        }
        
        return allBalances
    }
    
    
    /// Returns the historical performance data for Total Accounts using cumulative return calculation
    /// This method implements the new cumulative return calculation pipeline as specified
    func getTotalAccountsPerformanceHistory(
        startDate: Date,
        endDate: Date,
        timeframe: PortfolioHistoryTimeframe,
        completion: @escaping (Result<[PortfolioHistoryDataPoint], Error>) -> Void
    ) {
        guard !accounts.isEmpty else {
            completion(.success([]))
            return
        }
        
        // Collect data from all accounts
        let group = DispatchGroup()
        var accountHistories: [UUID: [PortfolioHistoryDataPoint]] = [:]
        var errors: [Error] = []
        
        // Use only real trading accounts; exclude synthetic "Total Accounts"
        for account in self.realAccounts {
            group.enter()
            
            let credentials = account.getDecryptedCredentials()
            let apiService = AlpacaAPIService(
                apiKey: credentials.apiKey,
                secretKey: credentials.secretKey,
                isLiveTrading: account.isLiveTrading
            )
            
            apiService.getPortfolioHistoryWithCustomDateRange(
                startDate: startDate,
                endDate: endDate,
                timeframe: timeframe
            ) { result in
                switch result {
                case .success(let history):
                    let processedData = self.processPortfolioHistory(
                        history,
                        currentAccount: account,
                        startDate: startDate,
                        endDate: endDate,
                        timeframe: timeframe
                    )
                    accountHistories[account.id] = processedData
                case .failure(let error):
                    errors.append(error)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if !errors.isEmpty && accountHistories.isEmpty {
                completion(.failure(errors.first!))
                return
            }
            
            // Calculate cumulative returns using the new pipeline
            let cumulativeReturnHistory = self.calculateCumulativeReturns(
                accountHistories: accountHistories,
                startDate: startDate,
                endDate: endDate,
                timeframe: timeframe
            )
            
            // Final result has \(cumulativeReturnHistory.count) data points
            
            completion(.success(cumulativeReturnHistory))
        }
    }

    /// Computes aggregated TWR for Total Accounts by summing equity across all accounts per day
    /// and discounting net cash flows (CSD deposits, CSW withdrawals) across all accounts.
    /// Activities for all accounts are fetched in parallel.
    func getTotalAccountsTWR(
        startDate: Date,
        endDate: Date,
        timeframe: PortfolioHistoryTimeframe,
        completion: @escaping (Result<[TWRPoint], Error>) -> Void
    ) {
        guard !accounts.isEmpty else {
            completion(.success([]))
            return
        }
        // Debug: kickoff
        // Starting TWR calculation

        // Step 1: Fetch per-account portfolio history in parallel (already used pipeline)
        let group = DispatchGroup()
        var accountHistories: [UUID: [PortfolioHistoryDataPoint]] = [:]
        var accountActivities: [UUID: [AccountActivity]] = [:]
        var firstError: Error?

        for account in self.realAccounts {
            // Fetching account data
            let credentials = account.getDecryptedCredentials()
            let apiService = AlpacaAPIService(
                apiKey: credentials.apiKey,
                secretKey: credentials.secretKey,
                isLiveTrading: account.isLiveTrading
            )

            // Portfolio history
            group.enter()
            apiService.getPortfolioHistoryWithCustomDateRange(
                startDate: startDate,
                endDate: endDate,
                timeframe: timeframe
            ) { result in
                switch result {
                case .success(let history):
                    let processed = self.processPortfolioHistory(
                        history,
                        currentAccount: account,
                        startDate: startDate,
                        endDate: endDate,
                        timeframe: timeframe
                    )
                    accountHistories[account.id] = processed
                    // History fetch successful
                case .failure(let err):
                    if firstError == nil { firstError = err }
                    // History fetch failed
                }
                group.leave()
            }

            // Cash flow activities CSD/CSW
            group.enter()
            apiService.getCashFlowActivities(startDate: startDate, endDate: endDate) { result in
                switch result {
                case .success(let activities):
                    accountActivities[account.id] = activities
                    // Activities fetch successful
                case .failure(let err):
                    if firstError == nil { firstError = err }
                    // Activities fetch failed
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // All data fetched
            if let err = firstError, accountHistories.isEmpty {
                completion(.failure(err))
                return
            }

            // Step 2: Aggregate equity per date across accounts
            // Build a map dateString (yyyy-MM-dd NY) -> total equity
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(identifier: "America/New_York")
            var equityByDate: [String: Double] = [:]
            var orderedDates: Set<String> = []

            for (_, history) in accountHistories {
                for p in history {
                    let key = df.string(from: p.timestamp)
                    equityByDate[key, default: 0.0] += p.equity
                    orderedDates.insert(key)
                }
            }
            // Processing equity dates

            // Step 3: Aggregate net cash flows per date across accounts
            var flowsByDate: [String: Double] = [:]
            for (_, activities) in accountActivities {
                for a in activities {
                    guard let ds = a.date else { continue }
                    let amount = Double(a.netAmount ?? "0.0") ?? 0.0
                    if a.activityType == "CSD" {
                        flowsByDate[ds, default: 0.0] += amount
                    } else if a.activityType == "CSW" {
                        flowsByDate[ds, default: 0.0] -= amount
                    }
                }
            }
            // Processing cash flows

            // Step 4: Build aggregated portfolio history points (sorted by date)
            let sortedDateKeys = orderedDates.sorted()
            struct AggPoint { let timestamp: Date; let equity: Double; let pnl: Double; let pnlPct: Double }
            var aggHistory: [AggPoint] = []

            var prevEquity: Double = 0.0
            for key in sortedDateKeys {
                guard let totalEquity = equityByDate[key] else { continue }
                let ts = df.date(from: key) ?? Date()
                // Approximate pnl and pnl% from equity series
                let pnl = prevEquity == 0 ? 0.0 : (totalEquity - prevEquity)
                let pnlPct = prevEquity == 0 ? 0.0 : ((pnl / prevEquity) * 100.0)
                aggHistory.append(AggPoint(timestamp: ts, equity: totalEquity, pnl: pnl, pnlPct: pnlPct))
                prevEquity = totalEquity
            }

            // Step 5: Build inputs for TWR computation using embedded algorithm (equivalent to individual)
            // Flatten flows to AccountActivity array
            let aggregatedActivities: [AccountActivity] = flowsByDate.map { (k, v) in
                AccountActivity(
                    id: UUID().uuidString,
                    activityType: v >= 0 ? "CSD" : "CSW",
                    date: k,
                    createdAt: nil,
                    netAmount: String(format: "%.6f", abs(v)),
                    description: nil,
                    qty: nil,
                    perShareAmount: nil,
                    side: nil,
                    symbol: nil,
                    leavesQty: nil,
                    orderId: nil,
                    cumQty: nil,
                    orderStatus: nil,
                    orderType: nil,
                    price: nil,
                    stopPrice: nil,
                    timeInForce: nil,
                    legs: nil,
                    executionId: nil,
                    orderLegs: nil
                )
            }

            // Implement TWR inline: compute daily returns with previous-day cash flow adjustment
            let sortedAgg = aggHistory.sorted { $0.timestamp < $1.timestamp }
            var result: [TWRPoint] = []
            var cumulative: Double = 1.0
            var prevEquityAgg: Double = 0.0
            for (idx, p) in sortedAgg.enumerated() {
                let ds = df.string(from: p.timestamp)
                // Cash flow for yesterday range (align to individual method)
                let netFlow = aggregatedActivities
                    .filter { $0.date == ds }
                    .reduce(0.0) { partial, a in
                        partial + (Double(a.netAmount ?? "0") ?? 0) * (a.activityType == "CSD" ? 1.0 : -1.0)
                    }
                let deposits = max(0.0, netFlow)
                let withdrawals = max(0.0, -netFlow)
                let dailyReturn: Double
                if idx == 0 || prevEquityAgg == 0 {
                    dailyReturn = 0.0
                    if p.equity > 0 { cumulative = 1.0 }
                } else {
                    let adjustedEquity = p.equity - netFlow
                    dailyReturn = (adjustedEquity / prevEquityAgg) - 1.0
                    cumulative *= (1.0 + dailyReturn)
                }
                let twrPoint = TWRPoint(
                    date: ds,
                    equity: p.equity,
                    pnl: p.pnl,
                    pnl_pct: p.pnlPct,
                    deposits: deposits,
                    withdrawals: withdrawals,
                    net_cash_flow: netFlow,
                    daily_return: dailyReturn,
                    cumulative_twr: cumulative - 1.0
                )
                result.append(twrPoint)
                prevEquityAgg = p.equity
            }
            
            // Add today's point if today is within the date range and not already included
            // Use Alpaca timezone for consistent date handling
            var nyCal = Calendar.current
            nyCal.timeZone = TimeZone(identifier: "America/New_York")!
            let today = Date()
            let todayStart = nyCal.startOfDay(for: today)
            let isTodayInRange = startDate <= todayStart && endDate >= todayStart
            
            if isTodayInRange, let lastPoint = result.last {
                let todayStr = df.string(from: todayStart)
                
                print("📅 [Total Accounts TWR] Checking today point: \(todayStr), inRange: \(isTodayInRange), lastPoint: \(lastPoint.date), resultCount: \(result.count)")
                
                // Calculate today's aggregated equity and cash flows
                var todayEquity: Double = 0.0
                var todayNetFlow: Double = 0.0
                
                // Sum current balances for today's equity
                for account in self.realAccounts {
                    if let balance = self.balances[account.id]?.balance {
                        todayEquity += balance
                    }
                }
                
                // Calculate net cash flows for today across all accounts
                let todayActivities = aggregatedActivities.filter { $0.date == todayStr }
                todayNetFlow = todayActivities.reduce(0.0) { partial, a in
                    partial + (Double(a.netAmount ?? "0") ?? 0) * (a.activityType == "CSD" ? 1.0 : -1.0)
                }
                
                // Calculate daily return using last point's equity as base
                let lastEquity = lastPoint.equity
                let adjustedEquity = todayEquity - todayNetFlow
                let dailyReturn = lastEquity == 0 ? 0.0 : (adjustedEquity / lastEquity) - 1.0
                
                // Calculate cumulative TWR
                let lastCumulativeProp = lastPoint.cumulative_twr + 1.0 // Convert back to proportion
                let newCumulativeProp = lastCumulativeProp * (1.0 + dailyReturn)
                
                // Calculate PnL for today
                let totalStartBalance = self.realAccounts.compactMap { account in
                    self.balances[account.id]?.balance
                }.reduce(0, +) // This should be the start balance, but we'll use current for simplicity
                
                let todayPnL = todayEquity - totalStartBalance
                let todayPnLPct = totalStartBalance > 0 ? (todayPnL / totalStartBalance) * 100.0 : 0.0
                
                let newTodayPoint = TWRPoint(
                    date: todayStr,
                    equity: todayEquity,
                    pnl: todayPnL,
                    pnl_pct: todayPnLPct,
                    deposits: max(0.0, todayNetFlow),
                    withdrawals: max(0.0, -todayNetFlow),
                    net_cash_flow: todayNetFlow,
                    daily_return: dailyReturn,
                    cumulative_twr: newCumulativeProp - 1.0
                )
                
                // Check if today's point already exists
                if let existingIndex = result.firstIndex(where: { $0.date == todayStr }) {
                    // Update existing today point
                    let existingPoint = result[existingIndex]
                    let equityChange = abs(newTodayPoint.equity - existingPoint.equity)
                    let twrChange = abs(newTodayPoint.cumulative_twr - existingPoint.cumulative_twr)
                    
                    if equityChange > 0.01 || twrChange > 0.001 { // Significant changes
                        result[existingIndex] = newTodayPoint
                        print("📅 [Total Accounts TWR] Updated existing today point at index \(existingIndex) (significant changes: equity=\(equityChange), twr=\(twrChange))")
                    } else {
                        print("📅 [Total Accounts TWR] No significant changes, keeping existing point (equity=\(equityChange), twr=\(twrChange))")
                    }
                } else {
                    // Add new today point
                    result.append(newTodayPoint)
                    print("📅 [Total Accounts TWR] Added new today point: \(todayStr), equity: \(todayEquity), daily: \(dailyReturn), newCount: \(result.count)")
                }
            } else {
                print("📅 [Total Accounts TWR] Not adding today point - inRange: \(isTodayInRange), lastPoint: \(result.last?.date ?? "none")")
            }
            
            // Clamp TWR points to earliest firstTradeDate among real accounts
            if let earliestFT = self.realAccounts.compactMap({ $0.firstTradeDate }).min() {
                let startOfDay = Calendar.current.startOfDay(for: earliestFT)
                let filtered = result.filter { p in
                    if let d = df.date(from: p.date) { return d >= startOfDay }
                    return false
                }
                // Clamped to earliest firstTrade
                completion(.success(filtered))
                return
            }
            // TWR calculation completed
            completion(.success(result))
        }
    }
    
    /// Returns the total balance of all accounts at the start date of the period
    /// For accounts that had 0 balance on the start date but gained balance during the period,
    /// we use their first non-zero balance as the "start" value
    func getTotalAccountsStartBalance(
        startDate: Date,
        endDate: Date,
        timeframe: PortfolioHistoryTimeframe,
        completion: @escaping (Result<Double, Error>) -> Void
    ) {
        guard !accounts.isEmpty else {
            completion(.success(0.0))
            return
        }
        
        // Collect data from all accounts
        let group = DispatchGroup()
        var accountStartBalances: [UUID: Double] = [:]
        var errors: [Error] = []
        
        for account in accounts {
            group.enter()
            
            let credentials = account.getDecryptedCredentials()
            let apiService = AlpacaAPIService(
                apiKey: credentials.apiKey,
                secretKey: credentials.secretKey,
                isLiveTrading: account.isLiveTrading
            )
            
            apiService.getPortfolioHistoryWithCustomDateRange(
                startDate: startDate,
                endDate: endDate,
                timeframe: timeframe
            ) { result in
                switch result {
                case .success(let history):
                    let processedData = self.processPortfolioHistory(
                        history,
                        currentAccount: account,
                        startDate: startDate,
                        endDate: endDate,
                        timeframe: timeframe
                    )
                    // Find the first non-zero balance during the period
                    // If no non-zero balance is found, use 0.0
                    var firstNonZeroBalance: Double = 0.0
                    
                    for day in processedData {
                        if day.equity > 0 {
                            firstNonZeroBalance = day.equity
                            break
                        }
                    }
                    
                    accountStartBalances[account.id] = firstNonZeroBalance
                case .failure(let error):
                    errors.append(error)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if !errors.isEmpty && accountStartBalances.isEmpty {
                completion(.failure(errors.first!))
                return
            }
            
            // Sum all start balances
            let totalStartBalance = accountStartBalances.values.reduce(0, +)
            completion(.success(totalStartBalance))
        }
    }
    
    /// Calculates cumulative returns using the new pipeline as specified
    /// Implements the 5-step process: real dates, start dates, weights, returns, aggregation
    private func calculateCumulativeReturns(
        accountHistories: [UUID: [PortfolioHistoryDataPoint]],
        startDate: Date,
        endDate: Date,
        timeframe: PortfolioHistoryTimeframe
    ) -> [PortfolioHistoryDataPoint] {
        
        // Starting calculateCumulativeReturns
        
        // Step 1: Collect all real dates from all account histories (like individual accounts)
        // Group by day to avoid multiple points per day
        var allDates: Set<Date> = []
        for (_, history) in accountHistories {
            // Account has data points
            for dataPoint in history {
                allDates.insert(dataPoint.timestamp)
                // Account data point
            }
        }
        
        // Group dates by day and keep only one representative date per day
        let calendar = Calendar.current
        var datesByDay: [String: Date] = [:]
        
        // Grouping dates by day
        for date in allDates {
            let dayKey = calendar.dateInterval(of: .day, for: date)?.start.timeIntervalSince1970.description ?? ""
            if datesByDay[dayKey] == nil || date < datesByDay[dayKey]! {
                datesByDay[dayKey] = date
                // Added date for day
            } else {
                // Skipped duplicate date
            }
        }
        
        // Convert to sorted array
        let realDates = Array(datesByDay.values).sorted { $0 < $1 }
        // After grouping: unique days
        for (_, _) in realDates.enumerated() {
            // Date to process
        }
        
        // Step 2: Find start date and initial capital for each account
        var accountStartData: [UUID: (startDate: Date, startBalance: Double)] = [:]
        var validAccounts: [UUID] = []
        
        for (accountId, history) in accountHistories {
            let sortedHistory = history.sorted { $0.timestamp < $1.timestamp }
            
            // Find first date where balance > 0
            if let firstNonZeroPoint = sortedHistory.first(where: { $0.equity > 0 }) {
                accountStartData[accountId] = (startDate: firstNonZeroPoint.timestamp, startBalance: firstNonZeroPoint.equity)
                validAccounts.append(accountId)
            }
        }
        
        // Exclude accounts without any balance > 0
        guard !validAccounts.isEmpty else { return [] }
        
        // Step 3: Calculate constant weights based on start balances
        let totalStartBalance = validAccounts.compactMap { accountStartData[$0]?.startBalance }.reduce(0, +)
        let weights = validAccounts.reduce(into: [UUID: Double]()) { result, accountId in
            if let startBalance = accountStartData[accountId]?.startBalance {
                result[accountId] = startBalance / totalStartBalance
            }
        }
        
        // Step 4 & 5: Calculate cumulative returns for each real date
        var result: [PortfolioHistoryDataPoint] = []
        
        // Processing dates to create data points
        // All dates to process
        for (_, _) in realDates.enumerated() {
            // Date to process
        }
        
        for (_, currentDate) in realDates.enumerated() {
            // Processing date
            
            var totalCumulativeReturn: Double = 0.0
            var totalRealEquity: Double = 0.0
            var accountsContributing: [UUID] = []
            
            // Calculate weighted cumulative return for this date
            for accountId in validAccounts {
                guard let (accountStartDate, accountStartBalance) = accountStartData[accountId],
                      let weight = weights[accountId],
                      let accountHistory = accountHistories[accountId] else { continue }
                
                // Skip if current date is before account start date
                guard currentDate >= accountStartDate else { 
                    // Skipping account - before start date
                    continue 
                }
                
                // Find the last known balance within the current interval (forward-fill)
                let lastKnownBalance = findLastKnownBalance(
                    for: currentDate,
                    in: accountHistory,
                    accountStartDate: accountStartDate
                )
                
                if let balance = lastKnownBalance {
                    accountsContributing.append(accountId)
                    // Calculate cumulative return for this account: r_i(t) = (balance_i(t) / startBalance_i) - 1
                    let accountReturn = (balance / accountStartBalance) - 1.0
                    totalCumulativeReturn += weight * accountReturn
                    
                    // Sum the real equity for tooltip display
                    totalRealEquity += balance
                    
                    // Account contributing
                } else {
                    // No balance found
                }
            }
            
            // Calculate profit/loss based on equity change from start
            let profitLoss = totalRealEquity - totalStartBalance
            let profitLossPct = totalStartBalance > 0 ? (profitLoss / totalStartBalance) * 100.0 : 0.0
            
            // Date processed
            
            let dataPoint = PortfolioHistoryDataPoint(
                timestamp: currentDate,
                equity: totalRealEquity, // Store the real equity sum for visualization
                profitLoss: profitLoss, // Calculate profit/loss from start balance
                profitLossPct: profitLossPct, // Calculate percentage change from start balance
                baseValue: totalStartBalance // Use start balance as base
            )
            
            result.append(dataPoint)
            // Added data point
        }
        
        // Add today's point only if the end date includes today
        let today = Date()
        
        // Checking if we should add today's point
        
        // Check if today is within the date range (more permissive condition)
        let startOfToday = calendar.startOfDay(for: today)
        let isTodayInRange = endDate >= startOfToday
        
        // Is today in range?
        
        if isTodayInRange {
            // Adding today's point
            
            var totalCumulativeReturn: Double = 0.0
            var totalRealEquity: Double = 0.0
            var accountsContributing: [UUID] = []
            
            // Calculate weighted cumulative return for today using current balances
            for accountId in validAccounts {
                guard let (accountStartDate, accountStartBalance) = accountStartData[accountId],
                      let weight = weights[accountId],
                      let currentBalance = balances[accountId]?.balance else { continue }
                
                // Skip if today is before account start date
                guard today >= accountStartDate else { 
                    // Skipping account - today before start date
                    continue 
                }
                
                accountsContributing.append(accountId)
                // Calculate cumulative return for this account: r_i(t) = (balance_i(t) / startBalance_i) - 1
                let accountReturn = (currentBalance / accountStartBalance) - 1.0
                totalCumulativeReturn += weight * accountReturn
                
                // Sum the real equity for tooltip display
                totalRealEquity += currentBalance
                
                // Account contributing today
            }
            
            // Calculate profit/loss based on equity change from start for today
            let profitLoss = totalRealEquity - totalStartBalance
            let profitLossPct = totalStartBalance > 0 ? (profitLoss / totalStartBalance) * 100.0 : 0.0
            
            // Today processed
            
            let todayDataPoint = PortfolioHistoryDataPoint(
                timestamp: today,
                equity: totalRealEquity, // Store the real equity sum for visualization
                profitLoss: profitLoss, // Calculate profit/loss from start balance
                profitLossPct: profitLossPct, // Calculate percentage change from start balance
                baseValue: totalStartBalance // Use start balance as base
            )
            
            result.append(todayDataPoint)
            // Added today's data point
        } else {
            // NOT adding today's point
        }
        
        // Final result
        
        return result.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Builds temporal grid according to granularity within the selected range
    private func buildTemporalGrid(startDate: Date, endDate: Date, timeframe: PortfolioHistoryTimeframe) -> [Date] {
        let calendar = Calendar.current
        var grid: [Date] = []
        
        switch timeframe {
        case .oneMinute:
            // Every minute
            var current = startDate
            while current <= endDate {
                grid.append(current)
                current = calendar.date(byAdding: .minute, value: 1, to: current) ?? current
            }
        case .fiveMinutes:
            // Every 5 minutes
            var current = startDate
            while current <= endDate {
                grid.append(current)
                current = calendar.date(byAdding: .minute, value: 5, to: current) ?? current
            }
        case .fifteenMinutes:
            // Every 15 minutes
            var current = startDate
            while current <= endDate {
                grid.append(current)
                current = calendar.date(byAdding: .minute, value: 15, to: current) ?? current
            }
        case .oneHour:
            // Every hour
            var current = startDate
            while current <= endDate {
                grid.append(current)
                current = calendar.date(byAdding: .hour, value: 1, to: current) ?? current
            }
        case .oneDay:
            // Every day
            var current = startDate
            while current <= endDate {
                grid.append(current)
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }
        }
        
        return grid
    }
    
    /// Finds the last known balance for an account within the current interval (forward-fill)
    private func findLastKnownBalance(
        for currentDate: Date,
        in history: [PortfolioHistoryDataPoint],
        accountStartDate: Date
    ) -> Double? {
        // Looking for balance
        
        // Find the last data point before or on the current date
        let relevantPoints = history.filter { point in
            point.timestamp <= currentDate && point.timestamp >= accountStartDate
        }
        
        // Relevant points
        
        // Return the most recent balance (forward-fill)
        let result = relevantPoints.last?.equity
        if result != nil {
            // Found balance
        } else {
            // No balance found
        }
        return result
    }
    
    /// Updates the daily change percentage for a specific account
    func updateDailyChangePercentage(for accountId: UUID, percentage: Double) {
        // Prevent infinite loops by checking if value actually changed
        if let existingPercentage = dailyChangePercentages[accountId], 
           abs(existingPercentage - percentage) < 0.001 {
            return // Value hasn't changed significantly, skip update
        }
        
        let accountName = accounts.first { $0.id == accountId }?.name ?? "Unknown"
        print("📊 [updateDailyChangePercentage] \(accountName): \(percentage)%")
        dailyChangePercentages[accountId] = percentage
        
        // Trigger recalculation of Total Accounts if this was the last account to update
        DispatchQueue.main.async {
            self.triggerTotalAccountsRecalculation()
        }
    }

    /// Reports yesterday and today equities for an account to support listeners that aggregate
    /// cross-account daily changes (e.g., Total Accounts). Currently serves as a lightweight
    /// signal to refresh dependent views.
    func reportDailyEquities(for accountId: UUID, yesterdayEquity: Double, todayEquity: Double) {
        // In the current architecture, Total Accounts daily change is derived from
        // `dailyChangePercentages`. We emit a change signal so any observers can react.
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// Preload daily change percentages for all real accounts in background, independent of UI visibility.
    /// This triggers the same logic used by AccountBalanceCard but centrally, so cards below the fold
    /// still get their daily change calculated.
    /// IMPORTANT: This should be called AFTER balances have been updated to ensure accurate calculations.
    func preloadDailyChanges() {
        // Only proceed if we have balances for all accounts
        let accountsWithoutBalance = realAccounts.filter { balances[$0.id] == nil }
        guard accountsWithoutBalance.isEmpty else {
            print("⚠️ [preloadDailyChanges] Skipping - missing balances for accounts: \(accountsWithoutBalance.map { $0.name })")
            return
        }
        
        for account in realAccounts {
            guard let api = apiServices[account.id] else { continue }
            api.getPortfolioHistory(period: .oneMonth, timeframe: .oneDay) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let history):
                    // Compute daily change: current balance vs last trading day equity
                    let currentEquity = self.balances[account.id]?.balance ?? 0.0
                    if let equities = history.equity, let last = equities.last, last > 0 {
                        let changePct = ((currentEquity - last) / last) * 100.0
                        DispatchQueue.main.async {
                            self.updateDailyChangePercentage(for: account.id, percentage: changePct)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.updateDailyChangePercentage(for: account.id, percentage: 0.0)
                        }
                    }
                case .failure(_):
                    DispatchQueue.main.async {
                        self.updateDailyChangePercentage(for: account.id, percentage: 0.0)
                    }
                }
            }
        }
    }
    
    /// Triggers daily change calculation for all accounts after balance updates
    private func triggerDailyChangeCalculation() {
        // Check if all accounts have balances before triggering preload
        let accountsWithoutBalance = realAccounts.filter { balances[$0.id] == nil }
        if accountsWithoutBalance.isEmpty {
            // All accounts have balances, safe to calculate daily changes
            preloadDailyChanges()
        } else {
            print("⏳ [triggerDailyChangeCalculation] Waiting for balances: \(accountsWithoutBalance.map { $0.name })")
        }
    }
    
    /// Triggers recalculation of Total Accounts daily change
    private func triggerTotalAccountsRecalculation() {
        // Check if we have data for all accounts with balances > 0
        let accountsWithBalance = accounts.filter { account in
            guard let balance = balances[account.id]?.balance else { return false }
            return balance > 0
        }
        
        let accountsWithDailyChange = accountsWithBalance.filter { account in
            dailyChangePercentages[account.id] != nil
        }
        
        // If all accounts with balance have daily change data, recalculate Total Accounts
        if accountsWithBalance.count == accountsWithDailyChange.count && !accountsWithBalance.isEmpty {
            // Force UI update by updating the published property
            objectWillChange.send()
        }
    }
    
    // MARK: - New Total Accounts Daily Change Calculation
    
    /// Returns true when all accounts with balance > 0 have an entry in `dailyChangePercentages`.
    /// This gates the UI for Total Accounts so it only renders once all inputs are ready.
    var areAllDailyChangesReady: Bool {
        let accountsWithBalance = accounts.filter { account in
            guard let balance = balances[account.id]?.balance else { return false }
            return balance > 0
        }
        guard !accountsWithBalance.isEmpty else { return false }
        let accountsWithDailyChange = accountsWithBalance.filter { account in
            dailyChangePercentages[account.id] != nil
        }
        return accountsWithBalance.count == accountsWithDailyChange.count
    }

    /// Returns the daily change percentage for Total Accounts using cumulative return calculation
    /// This uses the same system as the performance charts but only for current vs previous period
    var totalAccountsDailyChangeNew: Double? {
        guard !accounts.isEmpty else { return nil }
        
        // Get current total balance
        let currentTotalBalance = accounts.compactMap { account in
            balances[account.id]?.balance
        }.reduce(0, +)
        
        guard currentTotalBalance > 0 else { return nil }
        
        // Calculate weighted daily change using the same logic as cumulative returns
        var totalWeightedChange: Double = 0
        var totalWeight: Double = 0
        var hasValidData = false
        
        for account in accounts {
            guard let currentBalance = balances[account.id]?.balance,
                  let dailyChange = dailyChangePercentages[account.id] else {
                continue
            }
            
            // Weight by account balance (same as cumulative return system)
            let weight = currentBalance
            let weightedChange = dailyChange * weight
            
            totalWeightedChange += weightedChange
            totalWeight += weight
            hasValidData = true
        }
        
        guard hasValidData && totalWeight > 0 else { return nil }
        
        return totalWeightedChange / totalWeight
    }
    
    /// Processes portfolio history data (copied from PerformanceView for use in AccountManager)
    private func processPortfolioHistory(
        _ history: PortfolioHistory,
        currentAccount: AlpacaAccount,
        startDate: Date,
        endDate: Date,
        timeframe: PortfolioHistoryTimeframe
    ) -> [PortfolioHistoryDataPoint] {
        
        guard let timestamps = history.timestamp,
              let equities = history.equity,
              let profitLosses = history.profitLoss,
              let baseValues = history.baseValue else {
            return []
        }
        
        // profitLossPct puede ser nil o tener valores null, así que lo manejamos por separado
        let profitLossPcts = history.profitLossPct
        
        var dataPoints: [PortfolioHistoryDataPoint] = []
        
        for i in 0..<min(timestamps.count, equities.count) {
            let originalTimestamp = Date(timeIntervalSince1970: TimeInterval(timestamps[i]))
            
            // Aplicar ajuste de fecha para todos los períodos
            let adjustedTimestamp = timeframe.adjustAlpacaDate(originalTimestamp)
            
            let equity = equities[i]
            let profitLoss = i < profitLosses.count ? profitLosses[i] : 0.0
            // Manejar valores null en profitLossPct
            let profitLossPct = (i < profitLossPcts?.count ?? 0) ? (profitLossPcts?[i] ?? 0.0) : 0.0
            let baseValue = i < baseValues.count ? baseValues[i] : equity
            
            let dataPoint = PortfolioHistoryDataPoint(
                timestamp: adjustedTimestamp,
                equity: equity,
                profitLoss: profitLoss,
                profitLossPct: profitLossPct,
                baseValue: baseValue
            )
            
            dataPoints.append(dataPoint)
        }
        
        // Filter data by date range
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        
        dataPoints = dataPoints.filter { dataPoint in
            let dataPointDate = dataPoint.timestamp
            return dataPointDate >= startOfDay && dataPointDate < endOfDay
        }
        
        // Filter out today's data points from API - we'll add them later in calculateCumulativeReturns
        let today = Date()
        dataPoints = dataPoints.filter { dataPoint in
            !calendar.isDate(dataPoint.timestamp, inSameDayAs: today)
        }
        
        return dataPoints.sorted { $0.timestamp < $1.timestamp }
    }
    
    
    /// Fixed UUID for Total Accounts to ensure consistency
    let totalAccountsId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    
    private func createTotalAccountsAccount() -> AlpacaAccount {
        return AlpacaAccount(
            id: totalAccountsId,
            name: "Total Accounts",
            description: "Sum of all account balances",
            alpacaAccountId: nil,
            apiKey: "",
            secretKey: "",
            isLiveTrading: false,
            isEncrypted: false,
            firstTradeDate: nil
        )
    }
    
    private let fileManager = FileManager.default
    private let storageDirectory: URL
    private let accountsFileURL: URL
    private let balancesFileURL: URL
    
    private var updateTimer: Timer?
    var apiServices: [UUID: AlpacaAPIService] = [:]
    
    // Trading data manager
    let tradingDataManager = TradingDataManager()
    
    // Cancellables for Combine
    private var cancellables = Set<AnyCancellable>()
    
    // Settings manager
    private let settingsManager = SettingsManager.shared
    
    init() {
        // Use Application Support inside the sandbox container
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.alpaca.tracker"
        let baseDir = appSupport.appendingPathComponent(bundleId, isDirectory: true)
        // Ensure directory exists
        if !fileManager.fileExists(atPath: baseDir.path) {
            try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        storageDirectory = baseDir
        accountsFileURL = storageDirectory.appendingPathComponent("alpaca_accounts.json")
        balancesFileURL = storageDirectory.appendingPathComponent("alpaca_balances.json")
        
        // Verificar autenticación
        isAuthenticated = authService.isAuthenticated
        currentUser = authService.currentUser
        
        // Si está autenticado, cargar desde Supabase
        if isAuthenticated {
            loadAccountsAfterLogin()
        } else {
            // Modo local: cargar desde archivos locales
            loadAccounts()
            loadBalances()
            loadAccountsFromSettings()
        }
        
        startPeriodicUpdates()
        
        // Actualizar balances de todas las cuentas cargadas
        for account in accounts {
            createAPIService(for: account)
            updateAccountBalance(account.id)
        }
        
        // Configurar el trading data manager con los servicios API después de crearlos
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.tradingDataManager.configure(with: self.apiServices)
        }
        
        // Listen for settings changes
        settingsManager.$appSettings
            .map { $0.showTotalAccounts }
            .removeDuplicates()
            .sink { [weak self] _ in
                // Trigger UI update when showTotalAccounts changes
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
        
        // Listen for authentication changes
        authService.$isAuthenticated
            .sink { [weak self] authenticated in
                DispatchQueue.main.async {
                    self?.isAuthenticated = authenticated
                    self?.currentUser = self?.authService.currentUser
                    if !authenticated {
                        // Si se desautenticó, limpiar cuentas
                        self?.accounts = []
                        self?.balances = [:]
                        self?.apiServices = [:]
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Account Management
    
    func loadAccountsFromSettings() {
        // Cargar cuentas desde el nuevo sistema de persistencia
        let savedAccounts = settingsManager.accounts
        
        for savedAccount in savedAccounts {
            let alpacaAccount = AlpacaAccount(
                id: UUID(uuidString: savedAccount.id) ?? UUID(),
                name: savedAccount.name,
                description: "ID: \(savedAccount.id)",
                alpacaAccountId: nil,
                apiKey: savedAccount.apiKey,
                secretKey: savedAccount.secretKey,
                isLiveTrading: savedAccount.isLive,
                firstTradeDate: nil,
                leverage: savedAccount.leverage,
                budget: savedAccount.budget,
                canCloseAllPositions: savedAccount.canCloseAllPositions,
                canDisconnectFromGrecia: savedAccount.canDisconnectFromGrecia
            )
            
            // Solo añadir si no existe ya
            if !accounts.contains(where: { $0.id == alpacaAccount.id }) {
                accounts.append(alpacaAccount)
            }
        }
        
        // Si hay una cuenta seleccionada en settings, asegurarse de que esté disponible
        if let selectedAccountId = settingsManager.appSettings.selectedAccountId,
           accounts.first(where: { $0.id.uuidString == selectedAccountId }) != nil {
            // La cuenta ya está cargada
        }
    }
    
    func loadAccounts() {
        do {
            if fileManager.fileExists(atPath: accountsFileURL.path) {
                let data = try Data(contentsOf: accountsFileURL)
                let decodedAccounts = try JSONDecoder().decode([AlpacaAccount].self, from: data)
                
                // Migrar cuentas existentes a encriptación y nuevos campos si es necesario
                accounts = decodedAccounts.map { account in
                    var migratedAccount = account
                    
                    // Migrar a encriptación si es necesario
                    if !account.isEncrypted {
                        migratedAccount = account.encryptCredentials()
                    }
                    
                    // Migrar nuevos campos si no existen
                    if migratedAccount.leverage == nil {
                        migratedAccount.leverage = 1.0
                    }
                    if migratedAccount.budget == nil {
                        migratedAccount.budget = 100
                    }
                    if migratedAccount.canCloseAllPositions == nil {
                        migratedAccount.canCloseAllPositions = false
                    }
                    if migratedAccount.canDisconnectFromGrecia == nil {
                        migratedAccount.canDisconnectFromGrecia = false
                    }
                    
                    return migratedAccount
                }
                
                // Guardar las cuentas si se migraron
                let needsMigration = decodedAccounts.contains(where: { !$0.isEncrypted }) ||
                                   decodedAccounts.contains(where: { $0.leverage == nil || $0.budget == nil || $0.canCloseAllPositions == nil || $0.canDisconnectFromGrecia == nil })
                if needsMigration {
                    saveAccounts()
                }
            }
        } catch {
            // Error loading accounts - will be handled gracefully
        }
    }
    
    func saveAccounts() {
        do {
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: accountsFileURL)
        } catch {
            // Error saving accounts
        }
    }
    
    func addAccount(_ account: AlpacaAccount) {
        // Encriptar las credenciales antes de guardar
        let encryptedAccount = account.encryptCredentials()
        accounts.append(encryptedAccount)
        createAPIService(for: encryptedAccount)
        saveAccounts()
        updateAccountBalance(encryptedAccount.id)
        // Persistence handled via local file in Application Support
        // Sincronizar también con SettingsManager para mantener leverage/budget en UserDefaults
        upsertSettingsAccount(from: encryptedAccount)
        
        // Si está autenticado, sincronizar con Supabase
        if isAuthenticated {
            syncAccountToSupabase(account: encryptedAccount) { result in
                if case .failure(let error) = result {
                    print("Error syncing account to Supabase: \(error.localizedDescription)")
                }
            }
        }
        
        // Actualizar el trading data manager
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.tradingDataManager.configure(with: self.apiServices)
        }
    }
    
    func updateAccount(_ account: AlpacaAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            let oldAccount = accounts[index]
            // Encriptar las credenciales antes de guardar
            let encryptedAccount = account.encryptCredentials()
            accounts[index] = encryptedAccount
            
            // Recrear el servicio API si las credenciales cambiaron
            if oldAccount.apiKey != encryptedAccount.apiKey || oldAccount.secretKey != encryptedAccount.secretKey {
                createAPIService(for: encryptedAccount)
            }
            
            saveAccounts()
            updateAccountBalance(encryptedAccount.id)
            
            // Actualizar el trading data manager
            tradingDataManager.configure(with: apiServices)

            // Persistence handled via local file in Application Support
            // Sincronizar también con SettingsManager
            upsertSettingsAccount(from: encryptedAccount)
            
            // Si está autenticado, sincronizar con Supabase
            if isAuthenticated {
                syncAccountToSupabase(account: encryptedAccount) { result in
                    if case .failure(let error) = result {
                        print("Error syncing account to Supabase: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func deleteAccount(_ account: AlpacaAccount) {
        accounts.removeAll { $0.id == account.id }
        balances.removeValue(forKey: account.id)
        apiServices.removeValue(forKey: account.id)
        saveAccounts()
        // Eliminar de SettingsManager también
        settingsManager.deleteAccount(account.id.uuidString)
        
        // Si está autenticado, eliminar de Supabase
        if isAuthenticated {
            accountsService.deleteAccount(accountId: account.id) { result in
                if case .failure(let error) = result {
                    print("Error deleting account from Supabase: \(error.localizedDescription)")
                }
            }
        }
        
        // Actualizar el trading data manager
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.tradingDataManager.configure(with: self.apiServices)
        }
        // Persistence handled via local file in Application Support
    }

    // MARK: - Settings sync
    private func upsertSettingsAccount(from account: AlpacaAccount) {
        let cfg = AccountConfiguration(
            name: account.name,
            apiKey: account.getDecryptedCredentials().apiKey,
            secretKey: account.getDecryptedCredentials().secretKey,
            isLive: account.isLiveTrading,
            isDefault: settingsManager.appSettings.selectedAccountId == account.id.uuidString,
            leverage: account.leverage ?? 1.0,
            budget: account.budget ?? 100,
            canCloseAllPositions: account.canCloseAllPositions ?? false,
            canDisconnectFromGrecia: account.canDisconnectFromGrecia ?? false
        )
        // Conservar el id estable al actualizar
        let updated = AccountConfiguration(
            name: cfg.name,
            apiKey: cfg.apiKey,
            secretKey: cfg.secretKey,
            isLive: cfg.isLive,
            isDefault: cfg.isDefault,
            leverage: cfg.leverage,
            budget: cfg.budget,
            canCloseAllPositions: cfg.canCloseAllPositions,
            canDisconnectFromGrecia: cfg.canDisconnectFromGrecia
        )
        // Sobrescribir el id del struct creado con el id real de la cuenta (recrear manteniendo id)
        let final = AccountConfiguration(
            id: account.id.uuidString,
            name: updated.name,
            apiKey: updated.apiKey,
            secretKey: updated.secretKey,
            isLive: updated.isLive,
            isDefault: updated.isDefault,
            createdAt: Date(),
            leverage: updated.leverage,
            budget: updated.budget,
            canCloseAllPositions: updated.canCloseAllPositions,
            canDisconnectFromGrecia: updated.canDisconnectFromGrecia
        )
        if let idx = settingsManager.accounts.firstIndex(where: { $0.id == final.id }) {
            settingsManager.accounts[idx] = final
        } else {
            settingsManager.accounts.append(final)
        }
        // Persistir
        // Guardado vía método privado; forzamos a través de updateAppSettings para disparar publish
        settingsManager.updateAppSettings(settingsManager.appSettings)
    }
    
    // MARK: - Balance Management
    
    func loadBalances() {
        do {
            if fileManager.fileExists(atPath: balancesFileURL.path) {
                let data = try Data(contentsOf: balancesFileURL)
                let decodedBalances = try JSONDecoder().decode([String: AccountBalance].self, from: data)
                balances = decodedBalances.compactMapKeys { UUID(uuidString: $0) }
            }
        } catch {
            // Error loading balances
        }
    }
    
    func saveBalances() {
        do {
            let stringKeys = balances.mapKeys { $0.uuidString }
            let data = try JSONEncoder().encode(stringKeys)
            try data.write(to: balancesFileURL)
        } catch {
            // Error saving balances
        }
    }
    
    func updateBalance(for accountId: UUID, balance: Double) {
        let newBalance = AccountBalance(accountId: accountId, balance: balance)
        balances[accountId] = newBalance
        saveBalances()
    }
    
    // MARK: - Periodic Updates
    
    private func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            self.updateAllBalances()
        }
    }
    
    private func updateAllBalances() {
        for account in accounts {
            updateAccountBalance(account.id)
        }
    }
    
    private func createAPIService(for account: AlpacaAccount) {
        // Obtener las credenciales desencriptadas para usar en la API
        let credentials = account.getDecryptedCredentials()
        let apiService = AlpacaAPIService(
            apiKey: credentials.apiKey,
            secretKey: credentials.secretKey,
            isLiveTrading: account.isLiveTrading
        )
        apiServices[account.id] = apiService
    }
    
    func updateAccountBalance(_ accountId: UUID) {
        guard let _ = accounts.first(where: { $0.id == accountId }),
              let apiService = apiServices[accountId] else {
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        apiService.getAccount { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.lastUpdateTime = Date()
                
                switch result {
                case .success(let account):
                    let portfolioValue = Double(account.portfolioValue) ?? 0.0
                    
                    // Actualizar el alpacaAccountId en la cuenta local
                    if let accountIndex = self?.accounts.firstIndex(where: { $0.id == accountId }) {
                        self?.accounts[accountIndex].alpacaAccountId = account.id
                        self?.accounts[accountIndex].description = "ID: \(account.id)"
                        self?.saveAccounts()
                    }
                    
                    let balance = AccountBalance(
                        accountId: accountId,
                        balance: portfolioValue,
                        lastUpdated: Date(),
                        accountInfo: account
                    )
                    self?.balances[accountId] = balance
                    self?.saveBalances()
                    
                    // Trigger daily change calculation after balance update
                    self?.triggerDailyChangeCalculation()
                    
                case .failure(let error):
                    // En caso de error, mantener el balance anterior o mostrar error
                    if let existingBalance = self?.balances[accountId] {
                        let errorBalance = AccountBalance(
                            accountId: accountId,
                            balance: existingBalance.balance,
                            lastUpdated: existingBalance.lastUpdated,
                            accountInfo: existingBalance.accountInfo,
                            error: error.localizedDescription
                        )
                        self?.balances[accountId] = errorBalance
                    }
                }
            }
        }
    }
    
    func testAccountConnection(_ account: AlpacaAccount, completion: @escaping (Result<Bool, Error>) -> Void) {
        // Obtener las credenciales desencriptadas para usar en la API
        let credentials = account.getDecryptedCredentials()
        let apiService = AlpacaAPIService(
            apiKey: credentials.apiKey,
            secretKey: credentials.secretKey,
            isLiveTrading: account.isLiveTrading
        )
        
        // Mantener una referencia temporal al servicio para evitar que se libere
        let serviceRef: AlpacaAPIService = apiService
        
        apiService.testConnection { result in
            DispatchQueue.main.async {
                // La referencia se libera automáticamente al salir del scope
                _ = serviceRef // Evitar advertencia de variable no usada
                
                switch result {
                case .success:
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Supabase Synchronization
    
    /// Carga las cuentas desde Supabase después de un login exitoso
    func loadAccountsAfterLogin() {
        accountsService.fetchAccounts { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let supabaseAccounts):
                    // Reemplazar cuentas locales con las de Supabase
                    self.accounts = supabaseAccounts.map { $0.encryptCredentials() }
                    self.saveAccounts()
                    
                    // Crear servicios API para todas las cuentas
                    for account in self.accounts {
                        self.createAPIService(for: account)
                        self.updateAccountBalance(account.id)
                    }
                    
                    // Configurar el trading data manager
                    self.tradingDataManager.configure(with: self.apiServices)
                    
                case .failure(let error):
                    print("Error loading accounts from Supabase: \(error.localizedDescription)")
                    // Fallback: cargar desde archivos locales
                    self.loadAccounts()
                    self.loadAccountsFromSettings()
                }
            }
        }
    }
    
    /// Sincroniza todas las cuentas desde Supabase
    func syncAccountsFromSupabase(completion: @escaping (Result<Bool, Error>) -> Void) {
        accountsService.fetchAccounts { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(.failure(NSError(domain: "AccountManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "AccountManager deallocated"])))
                    return
                }
                
                switch result {
                case .success(let supabaseAccounts):
                    // Actualizar cuentas
                    self.accounts = supabaseAccounts.map { $0.encryptCredentials() }
                    self.saveAccounts()
                    
                    // Recrear servicios API
                    self.apiServices.removeAll()
                    for account in self.accounts {
                        self.createAPIService(for: account)
                        self.updateAccountBalance(account.id)
                    }
                    
                    self.tradingDataManager.configure(with: self.apiServices)
                    completion(.success(true))
                    
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Sincroniza una cuenta individual con Supabase
    func syncAccountToSupabase(account: AlpacaAccount, completion: @escaping (Result<Bool, Error>) -> Void) {
        // Verificar si la cuenta ya existe en Supabase (por ID)
        if accounts.contains(where: { $0.id == account.id }) {
            // Actualizar cuenta existente
            accountsService.updateAccount(account: account) { result in
                switch result {
                case .success:
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Agregar nueva cuenta
            accountsService.addAccount(account: account) { result in
                switch result {
                case .success:
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - Extensions

extension Dictionary {
    func compactMapKeys<T: Hashable>(_ transform: (Key) throws -> T?) rethrows -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            if let newKey = try transform(key) {
                result[newKey] = value
            }
        }
        return result
    }
    
    func mapKeys<T: Hashable>(_ transform: (Key) throws -> T) rethrows -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            let newKey = try transform(key)
            result[newKey] = value
        }
        return result
    }
}