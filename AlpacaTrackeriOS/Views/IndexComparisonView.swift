import SwiftUI
import Charts

struct IndexComparisonView: View {
    @ObservedObject var accountManager: AccountManager
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var indexDataManager = IndexDataManager()
    @State private var selectedAccount: UUID?
    @State private var portfolioHistory: [PortfolioHistoryDataPoint] = []
    @State private var twrData: [NormalizedDataPoint] = []
    @State private var indexHistories: [IndexHistory] = []
    @State private var showingAccountPicker = false
    @State private var showingIndexSelector = false
    @State private var selectedIndices: Set<String> = ["sp500"]
    @State private var selectedPeriod: PortfolioHistoryPeriod = .oneMonth
    @State private var selectedTimeframe: PortfolioHistoryTimeframe = .oneDay
    @State private var customStartDate: Date = Date()
    @State private var customEndDate: Date = Date()
    @State private var isLoading = false
    @State private var isTWRLoading = false
    @State private var errorMessage: String?
    @State private var comparisons: [IndexComparison] = []
    @State private var lastUpdateDate: Date? = nil
    @State private var requestId: Int = 0
    @State private var isSeriesReady: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if accountManager.accounts.isEmpty {
                    emptyStateView
                } else {
                    unifiedHeaderView
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            if isLoading || !isSeriesReady {
                                loadingView
                            } else {
                            contentView
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
            .background(ColorCompatibility.appBackground())
        }
        .sheet(isPresented: $showingAccountPicker) {
            AccountPickerView(
                accounts: SettingsManager.shared.ordered(accountManager.allAccounts),
                selectedAccount: $selectedAccount,
                accountManager: accountManager
            )
        }
        .sheet(isPresented: $showingIndexSelector) {
            IndexSelectorSheet(
                selectedIndices: $selectedIndices,
                availableIndices: Index.allIndices
            )
        }
        .onAppear {
            // Load persisted selected account if available
            if let savedId = settingsManager.appSettings.selectedAccountId,
               let uuid = UUID(uuidString: savedId),
               accountManager.allAccounts.contains(where: { $0.id == uuid }) {
                selectedAccount = uuid
            } else if selectedAccount == nil && !accountManager.allAccounts.isEmpty {
                selectedAccount = SettingsManager.shared.ordered(accountManager.allAccounts).first?.id
            }
        }
        .onChange(of: selectedAccount) { _, newValue in
            // Persist selection across tabs and launches
            if let id = newValue {
                settingsManager.updateSelectedAccount(id.uuidString)
            }
            // Validate custom dates when account changes
            if selectedPeriod == .custom {
                validateCustomDatesForCurrentAccount()
            }
            loadComparisonData()
        }
        .onChange(of: selectedIndices) { _, _ in
            loadComparisonData()
        }
        .onChange(of: selectedPeriod) { _, newPeriod in
            // Initialize custom dates when switching to custom period (match macOS)
            if newPeriod == .custom {
                guard let selectedAccount = selectedAccount,
                      let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else {
                    return
                }
                let calendar = Calendar.current
                let today = Date()
                customEndDate = today
                let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today
                let firstTradeDate = account.firstTradeDate ?? Date.distantPast
                customStartDate = max(thirtyDaysAgo, firstTradeDate)
            }
            // Validate timeframe selection
            validateTimeframeSelection()
            // Clear current series to avoid showing stale data
            self.twrData = []
            self.indexHistories = []
            self.comparisons = []
            self.errorMessage = nil
            // Only auto-load if not custom
            if newPeriod != .custom {
            loadComparisonData()
            }
        }
        .onChange(of: selectedTimeframe) { _, _ in
            validateTimeframeSelection()
            if selectedAccount != nil {
                // Clear current series to force refresh
                self.twrData = []
                self.indexHistories = []
                self.comparisons = []
                self.errorMessage = nil
            loadComparisonData()
            }
        }
    }
    
    // MARK: - Views
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No accounts configured")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Add an Alpaca account to compare with indices")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var unifiedHeaderView: some View {
        VStack(spacing: 0) {
            // Header compacto con fondo negro
            VStack(spacing: 8) {
            
            // Información de cuenta compacta
            if let selectedAccount = selectedAccount,
               let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                Button(action: {
                    showingAccountPicker = true
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            // Only show Live/Paper for real accounts, not Total Accounts
                            if account.name != "Total Accounts" {
                                Text(account.isLiveTrading ? "Live" : "Paper")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Daily change chip (Total Accounts uses aggregated metric)
                        Group {
                            let isTotal = account.name == "Total Accounts"
                            let dailyChange: Double? = isTotal ? accountManager.totalAccountsDailyChangeNew : accountManager.dailyChangePercentages[account.id]
                            if let dailyChange = dailyChange {
                                HStack(spacing: 4) {
                                    Image(systemName: dailyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption2)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                    Text("\(String(format: "%.2f", dailyChange))%")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background((dailyChange >= 0 ? Color.green : Color.red).opacity(0.12))
                                .cornerRadius(4)
                            }
                        }
                        // Removed last update time to prioritize space for relevant indicators
                        
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ColorCompatibility.controlBackground())
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Filtros compactos
            HStack {
                // Period Selector
                Menu {
                    ForEach(PortfolioHistoryPeriod.allCases, id: \.self) { period in
                        Button(action: { 
                            selectedPeriod = period
                            // Special handling for oneDay period
                            if period == .oneDay {
                                selectedTimeframe = .oneHour
                            }
                        }) {
                            Label(period.displayName, systemImage: selectedPeriod == period ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label(selectedPeriod.displayName, systemImage: "calendar")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(ColorCompatibility.controlBackground())
                        .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Custom Date Range Picker
                if selectedPeriod == .custom {
                    InlineDateRangePicker(
                        startDate: $customStartDate,
                        endDate: $customEndDate,
                        firstTradeDate: accountManager.allAccounts.first(where: { $0.id == selectedAccount })?.firstTradeDate,
                        onConfirm: {
                            loadComparisonData()
                        }
                    )
                }
                
                Spacer()
                
                // Timeframe Selector
                Menu {
                    ForEach(PortfolioHistoryTimeframe.allCases, id: \.self) { timeframe in
                        let isValid = selectedPeriod.validTimeframes.contains(timeframe)
                        Button(action: { selectedTimeframe = timeframe }) {
                            Label(timeframe.displayName, systemImage: selectedTimeframe == timeframe ? "checkmark" : "")
                        }
                        .disabled(!isValid)
                    }
                } label: {
                    Label(selectedTimeframe.displayName, systemImage: "chart.bar")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(ColorCompatibility.controlBackground())
                        .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            }
            .background(Color.black)
        }
    }
    
    
    private var contentView: some View {
        VStack(spacing: 16) {
            // Index Selector Button - centered with margin from header
            Button(action: {
                showingIndexSelector = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.subheadline)
                    Text("Select Indexes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 8)
            
            // Main content
            Group {
                if isLoading {
                    loadingView
                } else if let errorMessage = errorMessage {
                    errorView(errorMessage)
                } else if comparisons.isEmpty {
                    noDataView
                } else {
                    comparisonContentView
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView("Loading comparison data...")
                .scaleEffect(1.1)
            
            Text("Getting historical data for portfolio and selected indices")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.headline)
                .foregroundColor(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("No Data")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Comparison data will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private var comparisonContentView: some View {
        VStack(spacing: 16) {
            // Resumen unificado de comparaciones
            comparisonSummaryView
            
            // Gráfico de comparación funcional
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Comparison Chart")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                comparisonChartView
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ColorCompatibility.controlBackground())
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        .padding(.horizontal, 4)
    }
    
    private var comparisonSummaryView: some View {
        IndexComparisonSummary(comparisons: comparisons)
    }
    
    // Gráfico funcional de comparación
    private var comparisonChartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedAccount = selectedAccount,
               let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                let indexHistories = selectedIndices.compactMap { indexDataManager.indexHistories[$0] }
                
                ComparisonChartView(
                    portfolioData: twrData,
                    indexHistories: indexHistories,
                    account: account
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorCompatibility.controlBackground())
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Data Loading
    
    private func loadComparisonData() {
        
        // Increment request id to drop stale async completions
        requestId += 1
        let currentRequest = requestId
        isSeriesReady = false
        guard let selectedAccount = selectedAccount,
              let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else {
            print("❌ [Comparison iOS] No account selected")
            return
        }
        
        
        isLoading = true
        isTWRLoading = true
        errorMessage = nil
        
        // Handle Total Accounts case
        if account.name == "Total Accounts" {
            
            loadTotalAccountsComparisonData(currentRequestId: currentRequest)
            return
        }
        
        
        let dateRange = selectedPeriod.customDateRange(for: account)
        let startDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
        let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
        

        let credentials = account.getDecryptedCredentials()
        let apiService = AlpacaAPIService(
            apiKey: credentials.apiKey,
            secretKey: credentials.secretKey,
            isLiveTrading: account.isLiveTrading
        )
        
        let group = DispatchGroup()
        var rawHistory: PortfolioHistory?
        var activities: [AccountActivity] = []
        var firstError: Error?

        // Fetch portfolio history
        group.enter()
        apiService.getPortfolioHistoryWithCustomDateRange(
            startDate: startDate,
            endDate: endDate,
            timeframe: selectedTimeframe
        ) { result in
            switch result {
            case .success(let history):
                rawHistory = history
            case .failure(let err):
                firstError = err
            }
            group.leave()
        }

        // Fetch cash flow activities (CSD/CSW)
        group.enter()
        apiService.getCashFlowActivities(startDate: startDate, endDate: endDate) { result in
            switch result {
            case .success(let acts):
                activities = acts
            case .failure(let err):
                // Not fatal; still attempt TWR with zero flows
                if firstError == nil { firstError = err }
            }
            group.leave()
        }

        group.notify(queue: .main) {
            // Drop if stale
            guard currentRequest == self.requestId else { return }
            self.isTWRLoading = false
            if let err = firstError, rawHistory == nil {
                print("❌ [Comparison iOS] Native TWR prerequisites failed: \(err.localizedDescription)")
                self.isLoading = false
                self.errorMessage = err.localizedDescription
                return
            }
            var mapped: [NormalizedDataPoint]
            if let history = rawHistory {
                mapped = self.computeTWRFromPortfolioHistory(history: history, activities: activities)
                // Append/update today's point (individual accounts) using current balance and flows (prevDay, today]
            if let acc = accountManager.allAccounts.first(where: { $0.id == selectedAccount }),
               acc.name != "Total Accounts" {
                mapped = self.appendOrUpdateTodayPointForIndividualComparison(mapped: mapped, history: history, activities: activities, account: acc)
            }
            } else {
                mapped = []
            }
            self.twrData = mapped
            self.lastUpdateDate = Date()
            // Load indices aligned to TWR data range - use original date range to avoid +1 day offset
            // The TWR data may extend to today, but indices should use the original requested range
            self.loadIndexDataUsingTwrRange(startDate: startDate, endDate: endDate, currentRequestId: currentRequest)
            print("✅ [Comparison iOS] Native TWR calculation completed successfully: \(mapped.count) points")
        }
    }

    // MARK: - Native TWR Calculation
    private func computeTWRFromPortfolioHistory(history: PortfolioHistory, activities: [AccountActivity]) -> [NormalizedDataPoint] {
        guard let timestamps = history.timestamp, let equities = history.equity else { return [] }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(identifier: "America/New_York")
        print("🧮 [TWR iOS] ---- Compute TWR (individual) ----")
        print("🧮 [TWR iOS] history points: \(timestamps.count), activities: \(activities.count)")
        // Map arrays to (dateStr, equity)
        var dateEquity: [(String, Double)] = []
        for i in 0..<min(timestamps.count, equities.count) {
            let ts = Date(timeIntervalSince1970: TimeInterval(timestamps[i]))
            let dstr = df.string(from: ts)
            dateEquity.append((dstr, equities[i]))
            if i == 0 || i == timestamps.count - 1 {
                print("🧮 [TWR iOS] equity raw [\(dstr)] = \(equities[i])")
            }
        }
        // Collapse duplicates per day to last value (as API is daily anyway)
        var equityByDate: [String: Double] = [:]
        var order: [String] = []
        for (ds, eq) in dateEquity {
            if equityByDate[ds] == nil { order.append(ds) }
            equityByDate[ds] = eq
        }
        if let first = order.min(), let last = order.max() {
            print("🧮 [TWR iOS] equity dates range: \(first) -> \(last) [\(order.count) days]")
        }
        // Cash flows
        var flowsByDate: [String: Double] = [:]
        var allFlows: [(dateStr: String, dateNum: Int, net: Double)] = []
        func yyyymmddInt(_ s: String) -> Int { Int(s.replacingOccurrences(of: "-", with: "")) ?? 0 }
        for a in activities {
            guard let ds = a.date else { continue }
            let amount = Double(a.netAmount ?? "0") ?? 0.0
            let net = (a.activityType == "CSD") ? amount : (a.activityType == "CSW" ? -amount : 0.0)
            if net != 0 {
                flowsByDate[ds, default: 0.0] += net
                allFlows.append((ds, yyyymmddInt(ds), net))
                print("💸 [TWR iOS] activity ds=\(ds) type=\(a.activityType) net=\(net)")
            }
        }
        if flowsByDate.isEmpty { print("💸 [TWR iOS] No cash flows in range") }
        for (ds, net) in flowsByDate.sorted(by: { $0.key < $1.key }) {
            print("💸 [TWR iOS] flowsByDate[\(ds)] = \(net)")
        }
        // Compute TWR
        let sortedKeys = order.sorted()
        var result: [NormalizedDataPoint] = []
        var prevEquity: Double = 0.0
        var twr: Double = 1.0
        var started = false
        for (idx, key) in sortedKeys.enumerated() {
            guard let equity = equityByDate[key] else { continue }
            // previous interval cash flow: strictly after prev day and up to and including current day
            let prevDate = df.date(from: key).flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) }
            let prevKey = prevDate.map { df.string(from: $0) }
            var netPrev: Double = 0.0
            if let pv = prevKey {
                let pn = yyyymmddInt(pv)
                let cn = yyyymmddInt(key)
                if pn > 0 && cn > 0 {
                    let inclusive = allFlows.filter { $0.dateNum > pn && $0.dateNum <= cn }
                    netPrev = inclusive.reduce(0.0) { $0 + $1.net }
                    if !inclusive.isEmpty {
                        let desc = inclusive.map { "\($0.dateStr):\($0.net)" }.joined(separator: ", ")
                        print("💸 [TWR iOS] flows used for return (\(pv) -> \(key) inclusive current): [\(desc)] sum=\(netPrev)")
                    }
                }
            }
            if idx == 0 || prevEquity == 0 {
                if equity > 0 { started = true; twr = 1.0 }
                print("🧮 [TWR iOS] day=\(key) INIT equity=\(equity)")
            } else if started {
                let adjusted = equity - netPrev
                let daily = (prevEquity == 0) ? 0.0 : (adjusted / prevEquity) - 1.0
                twr *= (1.0 + daily)
                print("🧮 [TWR iOS] day=\(key) prevKey=\(prevKey ?? "nil") prevEquity=\(prevEquity) equity=\(equity) netPrev=\(netPrev) adjusted=\(adjusted) daily=\(daily) twr=\(twr)")
            }
            prevEquity = equity
            if let ts = df.date(from: key) {
                result.append(NormalizedDataPoint(timestamp: ts, value: (twr - 1.0) * 100.0))
            }
        }
        if let f = result.first, let l = result.last {
            print("🧮 [TWR iOS] result points: \(result.count) range: \(df.string(from: f.timestamp)) -> \(df.string(from: l.timestamp)) last=\(l.value)%")
        }
        return result
    }

    // Append/update "today" point for individual accounts (Comparison iOS), consistent with Performance logic
    private func appendOrUpdateTodayPointForIndividualComparison(mapped: [NormalizedDataPoint], history: PortfolioHistory, activities: [AccountActivity], account: AlpacaAccount) -> [NormalizedDataPoint] {
        guard !mapped.isEmpty else { return mapped }
        var result = mapped
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(identifier: "America/New_York")
        var nyCal = Calendar.current; nyCal.timeZone = TimeZone(identifier: "America/New_York")!
        let todayStart = nyCal.startOfDay(for: Date())

        // Build helper: last historical equity date and equity
        let lastHistDateStr: String = {
            if let ts = result.last?.timestamp { return df.string(from: ts) }
            return df.string(from: todayStart)
        }()
        let lastHistNum = Int(lastHistDateStr.replacingOccurrences(of: "-", with: "")) ?? 0
        let todayNum = Int(df.string(from: todayStart).replacingOccurrences(of: "-", with: "")) ?? 0

        // Aggregate flows (prevDay, today]
        var allFlows: [(dateNum: Int, net: Double)] = []
        for a in activities {
            guard let ds = a.date else { continue }
            let n = Int(ds.replacingOccurrences(of: "-", with: "")) ?? 0
            let amt = Double(a.netAmount ?? "0") ?? 0.0
            let net = (a.activityType == "CSD") ? amt : (a.activityType == "CSW" ? -amt : 0.0)
            if net != 0 { allFlows.append((n, net)) }
        }
        let netBetween = allFlows.filter { $0.dateNum > lastHistNum && $0.dateNum <= todayNum }.reduce(0.0) { $0 + $1.net }

        // Current balance
        let currentBalance = accountManager.balances[account.id]?.balance

        // Need last TWR equity baseline: reconstruct from mapped last point vs prior
        // For Comparison we only have cumulative % in value field; we approximate daily using last equity from portfolio history
        // As a practical approach, if current balance exists use it; otherwise skip
        guard let balance = currentBalance else { return result }

        // Estimate previous equity from last NormalizedDataPoint by aligning with last portfolio equity in this date
        // Fallback: use balance if cannot infer
        let lastEquity: Double = {
            // Try to read last equity from original history arrays
            if let ts = history.timestamp, let eq = history.equity, !ts.isEmpty {
                let lastTs = Date(timeIntervalSince1970: TimeInterval(ts.last!))
                let _ = df.string(from: lastTs)
                // Find equity for that NY day by scanning backwards
                return eq.last ?? balance
            }
            return balance
        }()

        // Compute daily return using Performance approach: prev=lastEquity (from series), adjusted = balance - netBetween
        let adjusted = balance - netBetween
        let prevEquity = lastEquity
        let lastCumulativePct = result.last?.value ?? 0.0
        let daily = prevEquity == 0 ? 0.0 : (adjusted / prevEquity) - 1.0
        let newCumulativePct = (1.0 + lastCumulativePct/100.0) * (1.0 + daily) * 100.0 - 100.0

        let todayPoint = NormalizedDataPoint(timestamp: todayStart, value: newCumulativePct)

        // Replace if same-day point exists; else append
        if let idx = result.firstIndex(where: { nyCal.isDate($0.timestamp, inSameDayAs: todayStart) }) {
            result[idx] = todayPoint
        } else {
            result.append(todayPoint)
        }

        // Ensure chronological order
        result.sort { $0.timestamp < $1.timestamp }
        return result
    }
    private func computeNativeTWRPoints(history: [PortfolioHistoryDataPoint], activities: [AccountActivity]) -> [NormalizedDataPoint] {
        // Mirror Performance TWR logic for individual accounts (as in embedded runner)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(identifier: "America/New_York")

        // 1) Collapse equity per NY day (ensure one point per day)
        var equityByDate: [String: Double] = [:]
        var orderedDates: Set<String> = []
        for p in history {
            let key = df.string(from: p.timestamp)
            equityByDate[key] = p.equity
            orderedDates.insert(key)
        }

        // 2) Sum net cash flows (CSD positive, CSW negative) by date string
        var flowsByDate: [String: Double] = [:]
        // Also keep raw list to support interval fallback like the script
        var allFlows: [(dateStr: String, dateNum: Int, net: Double)] = []
        func yyyymmddInt(_ s: String) -> Int {
            return Int(s.replacingOccurrences(of: "-", with: "")) ?? 0
        }
        for a in activities {
            guard let ds = a.date else { continue }
            let amount = Double(a.netAmount ?? "0.0") ?? 0.0
            if a.activityType == "CSD" {
                flowsByDate[ds, default: 0.0] += amount
            } else if a.activityType == "CSW" {
                flowsByDate[ds, default: 0.0] -= amount
            }
            let net = (a.activityType == "CSD") ? amount : (a.activityType == "CSW" ? -amount : 0.0)
            if net != 0 { allFlows.append((ds, yyyymmddInt(ds), net)) }
        }

        // 3) Build sorted dates and compute TWR with previous-day cash flow discount
        let sortedKeys = orderedDates.sorted()
        var result: [NormalizedDataPoint] = []
        var twrFactor: Double = 1.0
        var prevEquity: Double = 0.0
        var started: Bool = false
        for (idx, key) in sortedKeys.enumerated() {
            guard let equity = equityByDate[key] else { continue }
            // previous day's net flow applied across interval (prev -> current)
            let prevDate = (df.date(from: key)).flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) }
            let prevKey = prevDate.map { df.string(from: $0) }
            var netFlowPrev = prevKey.flatMap { flowsByDate[$0] } ?? 0.0
            if netFlowPrev == 0.0, let prevKey = prevKey {
                // Fallback: sum flows strictly between prev and current date (yyyyMMdd comparison), like the script
                let prevN = yyyymmddInt(prevKey)
                let currN = yyyymmddInt(key)
                if prevN > 0 && currN > 0 {
                    let between = allFlows.filter { $0.dateNum > prevN && $0.dateNum < currN }
                    if !between.isEmpty {
                        netFlowPrev = between.reduce(0.0) { $0 + $1.net }
                    }
                }
            }

            if idx == 0 || prevEquity == 0 {
                if equity > 0 { started = true; twrFactor = 1.0 }
            } else if started {
                let adjustedCurrent = equity - netFlowPrev
                let dailyReturn = (prevEquity == 0) ? 0.0 : (adjustedCurrent / prevEquity) - 1.0
                twrFactor *= (1.0 + dailyReturn)
            }
            prevEquity = equity
            if let ts = df.date(from: key) {
                result.append(NormalizedDataPoint(timestamp: ts, value: (twrFactor - 1.0) * 100.0))
            }
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }
    
    private func loadTotalAccountsComparisonData(currentRequestId: Int) {
        
        // For Total Accounts, we need to aggregate data from all real accounts
        // Use the new method to get performance history for Total Accounts
        let dateRange = selectedPeriod.customDateRange(for: accountManager.allAccounts.first { $0.name == "Total Accounts" } ?? AlpacaAccount(id: UUID(), name: "Total Accounts", description: "", alpacaAccountId: nil, apiKey: "", secretKey: "", isLiveTrading: false, isEncrypted: false, firstTradeDate: nil))
        let startDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
        let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
        
        
        
        accountManager.getTotalAccountsTWR(
            startDate: startDate,
            endDate: endDate,
            timeframe: selectedTimeframe
        ) { result in
            
            DispatchQueue.main.async {
                // Drop if stale
                guard currentRequestId == self.requestId else { return }
                self.isLoading = false
                
                switch result {
                case .success(let twrPoints):
                
                    // Map TWR points to NormalizedDataPoint for comparison
                    let mapped = twrPoints.map { point in
                        NormalizedDataPoint(
                            timestamp: point.timestamp,
                            value: point.cumulative_twr * 100.0
                        )
                    }
                    self.twrData = mapped
                    
                    self.errorMessage = nil
                    
                    // Load index data for comparison - use original date range to avoid +1 day offset
                    if !self.selectedIndices.isEmpty {
                        print("🔍 [Comparison iOS] Loading index data for Total Accounts")
                        // Use the original date range instead of TWR data range to prevent date offset
                        let totalAccountsAccount = self.accountManager.allAccounts.first { $0.name == "Total Accounts" } ?? AlpacaAccount(id: UUID(), name: "Total Accounts", description: "", alpacaAccountId: nil, apiKey: "", secretKey: "", isLiveTrading: false, isEncrypted: false, firstTradeDate: nil)
                        let dateRange = self.selectedPeriod.customDateRange(for: totalAccountsAccount)
                        let originalStartDate = self.selectedPeriod == .custom ? self.customStartDate : dateRange.startDate
                        let originalEndDate = self.selectedPeriod == .custom ? self.customEndDate : dateRange.endDate
                        self.loadIndexDataUsingTwrRange(startDate: originalStartDate, endDate: originalEndDate, currentRequestId: currentRequestId)
                    } else {
                        
                        self.indexHistories = []
                        self.comparisons = []
                        self.lastUpdateDate = Date()
                    }
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.twrData = []
                }
            }
        }
    }
    
    private func loadIndexDataUsingTwrRange(startDate: Date?, endDate: Date?, currentRequestId: Int) {
        print("🔍 [Comparison iOS] loadIndexDataUsingTwrRange called")
        let indices = Index.allIndices.filter { selectedIndices.contains($0.id) }
        
        guard let s = startDate, let e = endDate else {
            print("❌ [Comparison iOS] No valid date range for index data")
            self.isLoading = false
            self.indexHistories = []
            self.comparisons = []
            return
        }
        
        print("🔍 [Comparison iOS] Loading index data for range: \(s) to \(e)")
        print("🔍 [Comparison iOS] Selected indices: \(indices.map { $0.name })")
        
        indexDataManager.fetchMultipleIndexHistories(
            indices: indices,
            startDate: s,
            endDate: e
        ) { result in
            DispatchQueue.main.async {
                // Drop if stale
                guard currentRequestId == self.requestId else { return }
                self.isLoading = false
                switch result {
                case .success(let indexHistories):
                    print("🔍 [Comparison iOS] Index data success: \(indexHistories.count) histories")
                    self.indexHistories = indexHistories
                    var newComparisons: [IndexComparison] = []
                    
                    let isTotalAccounts: Bool = {
                        if let selectedAccount = selectedAccount,
                           let acc = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                            return acc.name == "Total Accounts"
                        }
                        return false
                    }()
                    
                    for indexHistory in indexHistories {
                        if let comparison = indexDataManager.calculateComparison(
                            portfolioHistory: twrData.isEmpty ? portfolioHistory : twrData.map { point in
                                PortfolioHistoryDataPoint(
                                    timestamp: point.timestamp,
                                    equity: point.value,
                                    profitLoss: 0,
                                    profitLossPct: point.value,
                                    baseValue: point.value
                                )
                            },
                            indexHistory: indexHistory,
                            isTotalAccounts: isTotalAccounts
                        ) {
                            newComparisons.append(comparison)
                        }
                    }
                    
                    self.comparisons = newComparisons
                    self.lastUpdateDate = Date()
                    print("✅ [Comparison iOS] Index data loading completed successfully")
                    self.isSeriesReady = true
                case .failure(let error):
                    print("❌ [Comparison iOS] Index data loading failed: \(error.localizedDescription)")
                    self.indexHistories = []
                    self.comparisons = []
                    self.isSeriesReady = true
                }
            }
        }
    }
    
    private func loadIndexDataForTotalAccounts() {
        let indices = Index.allIndices.filter { selectedIndices.contains($0.id) }
        
        // Use the same date range as the portfolio data for Total Accounts
        guard let firstPortfolioDate = portfolioHistory.first?.timestamp,
              let lastPortfolioDate = portfolioHistory.last?.timestamp else {
            // Fallback to 30 days if no portfolio data
            let calendar = Calendar.current
            let today = Date()
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today
            
            indexDataManager.fetchMultipleIndexHistories(
                indices: indices,
                startDate: thirtyDaysAgo,
                endDate: today
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let indexHistories):
                        self.indexHistories = indexHistories
                        var newComparisons: [IndexComparison] = []
                        
                        let isTotalAccounts: Bool = {
                            if let selectedAccount = selectedAccount,
                               let acc = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                                return acc.name == "Total Accounts"
                            }
                            return false
                        }()
                        
                        for indexHistory in indexHistories {
                            if let comparison = indexDataManager.calculateComparison(
                                portfolioHistory: twrData.isEmpty ? portfolioHistory : twrData.map { point in
                                    PortfolioHistoryDataPoint(
                                        timestamp: point.timestamp,
                                        equity: point.value,
                                        profitLoss: 0,
                                        profitLossPct: 0,
                                        baseValue: point.value
                                    )
                                },
                                indexHistory: indexHistory,
                                isTotalAccounts: isTotalAccounts
                            ) {
                                newComparisons.append(comparison)
                            }
                        }
                        
                        self.comparisons = newComparisons
                        self.lastUpdateDate = Date()
                        
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
            return
        }
        
        indexDataManager.fetchMultipleIndexHistories(
            indices: indices,
            startDate: firstPortfolioDate,
            endDate: lastPortfolioDate
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let indexHistories):
                    self.indexHistories = indexHistories
                    var newComparisons: [IndexComparison] = []
                    
                    let isTotalAccounts: Bool = {
                        if let selectedAccount = selectedAccount,
                           let acc = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                            return acc.name == "Total Accounts"
                        }
                        return false
                    }()
                    
                    for indexHistory in indexHistories {
                        if let comparison = indexDataManager.calculateComparison(
                            portfolioHistory: twrData.isEmpty ? portfolioHistory : twrData.map { point in
                                PortfolioHistoryDataPoint(
                                    timestamp: point.timestamp,
                                    equity: point.value,
                                    profitLoss: 0,
                                    profitLossPct: point.value,
                                    baseValue: point.value
                                )
                            },
                            indexHistory: indexHistory,
                            isTotalAccounts: isTotalAccounts
                        ) {
                            newComparisons.append(comparison)
                        }
                    }
                    
                    self.comparisons = newComparisons
                    self.lastUpdateDate = Date()
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func handlePortfolioDataResult(result: Result<PortfolioHistory, AlpacaAPIService.AlpacaAPIError>, account: AlpacaAccount) {
        switch result {
        case .success(let history):
            // Calculate the adjusted date range for filtering
            let dateRange = selectedPeriod.customDateRange(for: account)
            let startDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
            let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
            
            // Usar exactamente la misma función que PerformanceView con fechas ajustadas
            let processedData = PerformanceView.processPortfolioHistory(history, currentAccount: account, accountManager: accountManager, selectedPeriod: selectedPeriod, customStartDate: startDate, customEndDate: endDate, selectedTimeframe: selectedTimeframe)
            self.portfolioHistory = processedData
            self.errorMessage = nil
            
            if !self.portfolioHistory.isEmpty {
                // Cargar datos de índices solo si hay índices seleccionados
                if !self.selectedIndices.isEmpty {
                    guard let selectedAccount = self.selectedAccount,
                          let account = self.accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else {
                        self.isLoading = false
                        return
                    }
                    self.loadIndexData(for: account)
                } else {
                    // Si no hay índices seleccionados, solo mostrar datos del portfolio
                    self.isLoading = false
                    self.indexHistories = []
                    self.comparisons = []
                    self.lastUpdateDate = Date()
                }
            } else {
                self.isLoading = false
                self.errorMessage = "No valid portfolio data available"
            }
            
        case .failure(let error):
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }
    
    private func loadIndexData(for account: AlpacaAccount) {
        let indices = Index.allIndices.filter { selectedIndices.contains($0.id) }
        
        // All periods now use custom date ranges with firstTradeDate validation
        let dateRange = selectedPeriod.customDateRange(for: account)
        let startDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
        let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
        
        indexDataManager.fetchMultipleIndexHistories(
            indices: indices,
            startDate: startDate,
            endDate: endDate
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let indexHistories):
                    self.indexHistories = indexHistories
                    var newComparisons: [IndexComparison] = []
                    
                    let isTotalAccounts: Bool = {
                        if let selectedAccount = selectedAccount,
                           let acc = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                            return acc.name == "Total Accounts"
                        }
                        return false
                    }()
                    
                    for indexHistory in indexHistories {
                        if let comparison = indexDataManager.calculateComparison(
                            portfolioHistory: twrData.isEmpty ? portfolioHistory : twrData.map { point in
                                PortfolioHistoryDataPoint(
                                    timestamp: point.timestamp,
                                    equity: point.value,
                                    profitLoss: 0,
                                    profitLossPct: point.value,
                                    baseValue: point.value
                                )
                            },
                            indexHistory: indexHistory,
                            isTotalAccounts: isTotalAccounts
                        ) {
                            newComparisons.append(comparison)
                        }
                    }
                    
                    self.comparisons = newComparisons
                    self.lastUpdateDate = Date()
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    
    
    private func colorForSeries(_ seriesName: String) -> Color {
        switch seriesName {
        case "Portfolio":
            return .blue
        case "S&P 500":
            return .red
        case "NASDAQ":
            return .yellow
        case "MSCI World":
            return .purple
        default:
            return .gray
        }
    }
    
    private func validateTimeframeSelection() {
        let validTimeframes = selectedPeriod.validTimeframes
        if !validTimeframes.contains(selectedTimeframe) {
            // If current timeframe is not valid for the selected period, 
            // select the first valid timeframe
            selectedTimeframe = validTimeframes.first ?? .oneDay
        }
        
        // Special case: if period is oneDay and timeframe is oneDay, change to oneHour
        if selectedPeriod == .oneDay && selectedTimeframe == .oneDay {
            selectedTimeframe = .oneHour
        }
    }

    private func validateCustomDatesForCurrentAccount() {
        guard let selectedAccount = selectedAccount,
              let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else {
            return
        }
        let firstTradeDate = account.firstTradeDate ?? Date.distantPast
        if customStartDate < firstTradeDate {
            let calendar = Calendar.current
            let today = Date()
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today
            customStartDate = max(thirtyDaysAgo, firstTradeDate)
        }
        if customEndDate < customStartDate {
            customEndDate = Date()
        }
    }
}

// MARK: - ComparisonChartView

struct ComparisonChartView: View {
    let portfolioData: [NormalizedDataPoint]
    let indexHistories: [IndexHistory]
    let account: AlpacaAccount
    
    @State private var selectedTimestamp: Date?
    @State private var isHovering = false
    @State private var hoverLocation: CGPoint = .zero
    
    // Función para normalizar fechas eliminando la hora del día
    private func normalizeDateToDay(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? date
    }
    
    // Datos del portfolio ya normalizados (TWR %), solo normalizamos fecha
    private var normalizedPortfolioData: [NormalizedDataPoint] {
        portfolioData
            .filter { $0.value.isFinite }
            .map { NormalizedDataPoint(timestamp: normalizeDateToDay($0.timestamp), value: $0.value) }
    }
    
    // Datos normalizados de índices (porcentajes incrementales desde 0%)
    // Solo incluir fechas que existen en los datos de Alpaca
    private var indexData: [IndexNormalizedData] {
        // Obtener todas las fechas disponibles en los datos de Alpaca
        let alpacaDates = Set(normalizedPortfolioData.map { $0.timestamp })
        
        return indexHistories.compactMap { indexHistory in
            // Filtrar solo las fechas que existen en Alpaca
            let filteredDataPoints = indexHistory.dataPoints.filter { dataPoint in
                let normalizedDate = normalizeDateToDay(dataPoint.timestamp)
                return alpacaDates.contains(normalizedDate)
            }
            
            // Si no hay datos después del filtrado, no incluir este índice
            guard !filteredDataPoints.isEmpty else { return nil }
            
            // Ordenar por fecha para asegurar orden correcto
            let sortedDataPoints = filteredDataPoints.sorted { $0.timestamp < $1.timestamp }
            
            // Usar el primer valor de los datos filtrados como referencia (0%)
            guard let firstValue = sortedDataPoints.first?.value, firstValue > 0 else { return nil }
            
            let normalizedPoints = sortedDataPoints.map { dataPoint in
                let percentageChange = ((dataPoint.value - firstValue) / firstValue) * 100
                return NormalizedDataPoint(
                    timestamp: normalizeDateToDay(dataPoint.timestamp),
                    value: percentageChange
                )
            }
            
            // Añadir punto del día de hoy si existe en los datos de Alpaca
            var finalPoints = normalizedPoints
            let today = normalizeDateToDay(Date())
            
            // Verificar si el día de hoy está en los datos de Alpaca y no ya en los datos del índice
            if alpacaDates.contains(today) && !finalPoints.contains(where: { normalizeDateToDay($0.timestamp) == today }) {
                // Usar el último valor normalizado como aproximación para hoy
                if let lastPoint = normalizedPoints.last {
                    let todayPoint = NormalizedDataPoint(
                        timestamp: today,
                        value: lastPoint.value // Mantener el mismo porcentaje que el último punto
                    )
                    finalPoints.append(todayPoint)
                }
            }
            
            return IndexNormalizedData(
                index: indexHistory.index,
                dataPoints: finalPoints.sorted { $0.timestamp < $1.timestamp }
            )
        }
    }
    
    // Calcular rango dinámico del eje Y basado en porcentajes normalizados
    private var yAxisRange: ClosedRange<Double> {
        let portfolioValues = portfolioData.map { $0.value }
        let indexValues = indexData.flatMap { $0.dataPoints.map { $0.value } }
        let allValues = portfolioValues + indexValues
        
        // Si no hay datos, devolver un rango por defecto para porcentajes
        guard !allValues.isEmpty else { 
            return -10...10 
        }
        
        // Verificar que los valores sean finitos
        let validValues = allValues.filter { $0.isFinite }
        guard !validValues.isEmpty else { 
            return -10...10 
        }
        
        let minValue = validValues.min() ?? 0
        let maxValue = validValues.max() ?? 0
        
        // Añadir padding del 10% o mínimo 2%
        let range = maxValue - minValue
        let padding = max(range * 0.1, 2.0)
        return (minValue - padding)...(maxValue + padding)
    }
    
    // Generar marcas del eje Y basadas en el rango dinámico (porcentajes redondeados)
    private var yAxisMarks: [Double] {
        let range = yAxisRange
        let step = max(2.0, (range.upperBound - range.lowerBound) / 8) // Máximo 8 marcas
        let roundedStep = ceil(step / 2) * 2 // Redondear a múltiplos de 2%
        
        var marks: [Double] = []
        var current = range.lowerBound
        while current <= range.upperBound {
            // Redondear cada marca a número entero
            marks.append(round(current))
            current += roundedStep
        }
        
        return marks
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Verificar si hay datos para mostrar
            if normalizedPortfolioData.isEmpty && indexData.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No data available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Select a period and at least one index to compare")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 200) // Altura fija para móvil - igual que Performance
                .frame(maxWidth: .infinity)
            } else {
                // Gráfico interactivo principal
                ZStack {
                    interactiveChart
                    tooltipView
                    dateRangeOverlay
                }
                .frame(height: 200) // Altura fija para móvil - igual que Performance
            }
            
            // Leyenda nativa elegante debajo del gráfico
            HStack(spacing: 0) {
                Spacer()
                
                HStack(spacing: 16) {
                    // Portfolio siempre visible
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(colorForSeries("Portfolio"))
                            .frame(width: 12, height: 2)
                        Text("Portfolio")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                    
                    // Solo mostrar índices que están siendo graficados
                    ForEach(indexData, id: \.index.id) { indexHistory in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(colorForSeries(indexHistory.index.name))
                                .frame(width: 12, height: 2)
                            Text(indexHistory.index.name)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
                
                Spacer()
            }
            .padding(.top, 20)
            .padding(.bottom, 2)
        }
    }
    
    private func colorForSeries(_ seriesName: String) -> Color {
        switch seriesName {
        case "Portfolio":
            return .blue
        case "S&P 500":
            return .red
        case "NASDAQ":
            return .yellow
        case "MSCI World":
            return .purple
        default:
            return .gray
        }
    }
    
    private var interactiveChart: some View {
        let minValue = yAxisRange.lowerBound
        // Usar el valor mínimo del rango como base para evitar superposición con el eje X
        let baselineValue = minValue
        
        return GeometryReader { geometry in
            Chart {
                // Portfolio con área - Usar datos normalizados
                ForEach(normalizedPortfolioData) { dataPoint in
                    AreaMark(
                        x: .value("Date", dataPoint.timestamp),
                        yStart: .value("Base", baselineValue),
                        yEnd: .value("Porcentaje", dataPoint.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.4),
                                Color.blue.opacity(0.2),
                                Color.blue.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("Date", dataPoint.timestamp),
                        y: .value("Porcentaje", dataPoint.value)
                    )
                    .foregroundStyle(by: .value("Serie", "Portfolio"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    
                    PointMark(
                        x: .value("Date", dataPoint.timestamp),
                        y: .value("Porcentaje", dataPoint.value)
                    )
                    .foregroundStyle(by: .value("Serie", "Portfolio"))
                    .symbolSize(6)
                }
                
                // Índices - Usar datos normalizados
                ForEach(indexData, id: \.index.id) { indexHistory in
                    ForEach(indexHistory.dataPoints) { dataPoint in
                        LineMark(
                            x: .value("Date", dataPoint.timestamp),
                            y: .value("Porcentaje", dataPoint.value)
                        )
                        .foregroundStyle(by: .value("Serie", indexHistory.index.name))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                        
                        PointMark(
                            x: .value("Date", dataPoint.timestamp),
                            y: .value("Porcentaje", dataPoint.value)
                        )
                        .foregroundStyle(by: .value("Serie", indexHistory.index.name))
                        .symbolSize(4)
                    }
                }
                
                // Puntos de referencia blancos para el tooltip
                if let selectedTimestamp = selectedTimestamp {
                    // Punto blanco para el portfolio
                    if let portfolioPoint = findClosestPortfolioPoint(to: selectedTimestamp) {
                        PointMark(
                            x: .value("Date", portfolioPoint.timestamp),
                            y: .value("Porcentaje", portfolioPoint.value)
                        )
                        .foregroundStyle(.white)
                        .symbolSize(40)
                        .symbol(.circle)
                        .opacity(0.9)
                    }
                    
                    // Puntos blancos para los índices
                    ForEach(indexData, id: \.index.id) { indexHistory in
                        if let indexPoint = findClosestIndexPoint(in: indexHistory, to: selectedTimestamp) {
                            PointMark(
                                x: .value("Date", indexPoint.timestamp),
                                y: .value("Porcentaje", indexPoint.value)
                            )
                            .foregroundStyle(.white)
                            .symbolSize(40)
                            .symbol(.circle)
                            .opacity(0.9)
                        }
                    }
                }
            }
            .chartYScale(domain: yAxisRange)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(.gray.opacity(0.3))
                    AxisValueLabel(format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yAxisMarks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(.gray.opacity(0.3))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text("\(String(format: "%.0f", doubleValue))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartForegroundStyleScale([
                "Portfolio": .blue,
                "S&P 500": .red,
                "NASDAQ": .yellow,
                "MSCI World": .purple
            ])
            .chartLegend(.hidden)
            .background(Color.clear)
            .contentShape(Rectangle())
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let plotAnchor = proxy.plotFrame else { return }
                                    let plotFrame = geo[plotAnchor]
                                    let xInPlot = value.location.x - plotFrame.origin.x
                                    guard xInPlot >= 0, xInPlot <= plotFrame.size.width else { return }
                                    if let date: Date = proxy.value(atX: xInPlot) {
                                        selectedTimestamp = date
                                        let clampedX = min(max(value.location.x, plotFrame.minX), plotFrame.maxX)
                                            hoverLocation = CGPoint(
                                                x: clampedX,
                                                y: max(value.location.y, 5)
                                            )
                                        isHovering = true
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isHovering = false
                                        selectedTimestamp = nil
                                    }
                                }
                        )
                }
            }
        }
    }
    
    private func handleHoverInteraction(at location: CGPoint, in geometry: GeometryProxy) {
        let chartWidth = geometry.size.width
        let chartHeight = geometry.size.height
        
        let relativeX = location.x / chartWidth
        let relativeY = location.y / chartHeight
        
        // Obtener todos los timestamps únicos de todos los datos (normalizados)
        var allTimestamps: [Date] = []
        
        // Añadir timestamps del portfolio (ya normalizados)
        allTimestamps.append(contentsOf: portfolioData.map { $0.timestamp })
        
        // Añadir timestamps de índices (ya normalizados)
        for indexHistory in indexData {
            allTimestamps.append(contentsOf: indexHistory.dataPoints.map { $0.timestamp })
        }
        
        // Crear timestamps únicos y ordenados
        let uniqueTimestamps = Array(Set(allTimestamps)).sorted()
        
        guard !uniqueTimestamps.isEmpty else { return }
        
        // Encontrar el timestamp más cercano basado en la posición X
        let adjustedRelativeX = relativeX >= 0.95 ? 1.0 : relativeX
        let timestampIndex = Int(adjustedRelativeX * Double(uniqueTimestamps.count - 1))
        let clampedIndex = max(0, min(timestampIndex, uniqueTimestamps.count - 1))
        
        let selectedTimestamp = uniqueTimestamps[clampedIndex]
        self.selectedTimestamp = selectedTimestamp
        isHovering = true
        
        // Calcular la posición X real basada en el timestamp seleccionado
        let timestampPosition = Double(clampedIndex) / Double(uniqueTimestamps.count - 1)
        let pointX = timestampPosition * chartWidth
        let pointY = relativeY * chartHeight
        hoverLocation = CGPoint(x: pointX, y: pointY)
    }
    
    @ViewBuilder
    private var tooltipView: some View {
        if let selectedTimestamp = selectedTimestamp, isHovering {
            TooltipView(
                isVisible: isHovering,
                position: hoverLocation,
                maxWidth: 250
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatTimestampForTooltip(selectedTimestamp))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // Portfolio
                    if let portfolioPoint = findClosestPortfolioPoint(to: selectedTimestamp) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colorForSeries("Portfolio"))
                                .frame(width: 8, height: 8)
                            Text("Portfolio:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.2f", portfolioPoint.value))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(colorForSeries("Portfolio"))
                        }
                    }
                    
                    // Índices
                    ForEach(indexData, id: \.index.id) { indexHistory in
                        if let indexPoint = findClosestIndexPoint(in: indexHistory, to: selectedTimestamp) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(colorForSeries(indexHistory.index.name))
                                    .frame(width: 8, height: 8)
                                Text("\(indexHistory.index.name):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(String(format: "%.2f", indexPoint.value))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorForSeries(indexHistory.index.name))
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func findClosestPortfolioPoint(to targetTimestamp: Date) -> NormalizedDataPoint? {
        guard !normalizedPortfolioData.isEmpty else { return nil }
        
        let normalizedTarget = normalizeDateToDay(targetTimestamp)
        
        return normalizedPortfolioData.min { point1, point2 in
            let timeDiff1 = abs(point1.timestamp.timeIntervalSince(normalizedTarget))
            let timeDiff2 = abs(point2.timestamp.timeIntervalSince(normalizedTarget))
            return timeDiff1 < timeDiff2
        }
    }
    
    private func findClosestIndexPoint(in indexHistory: IndexNormalizedData, to targetTimestamp: Date) -> NormalizedDataPoint? {
        guard !indexHistory.dataPoints.isEmpty else { return nil }
        
        let normalizedTarget = normalizeDateToDay(targetTimestamp)
        
        return indexHistory.dataPoints.min { point1, point2 in
            let timeDiff1 = abs(point1.timestamp.timeIntervalSince(normalizedTarget))
            let timeDiff2 = abs(point2.timestamp.timeIntervalSince(normalizedTarget))
            return timeDiff1 < timeDiff2
        }
    }
    
    private func formatTimestampForTooltip(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: timestamp)
    }
    
    @ViewBuilder
    private var dateRangeOverlay: some View {
        if !normalizedPortfolioData.isEmpty {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(formatDateRange())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.regularMaterial.opacity(0.8))
                        )
                        .padding(.trailing, 6)
                        .padding(.bottom, 20) // Moved up from 6 to 20 to fit within chart area
                }
            }
            .frame(height: 200) // Match the chart height exactly
        }
    }
    
    private func formatDateRange() -> String {
        guard let firstDate = normalizedPortfolioData.first?.timestamp,
              let lastDate = normalizedPortfolioData.last?.timestamp else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        
        let startString = formatter.string(from: firstDate)
        let endString = formatter.string(from: lastDate)
        
        return "\(startString) - \(endString)"
    }
    
}

// MARK: - Supporting Data Structures

struct NormalizedDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

struct IndexNormalizedData: Identifiable {
    let id = UUID()
    let index: Index
    let dataPoints: [NormalizedDataPoint]
}

// MARK: - Supporting Views for IndexComparisonView

struct IndexSelectorSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedIndices: Set<String>
    let availableIndices: [Index]
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Select Indexes to Compare")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(availableIndices, id: \.id) { index in
                            IndexSelectionCard(
                                index: index,
                                isSelected: selectedIndices.contains(index.id),
                                onToggle: {
                                    if selectedIndices.contains(index.id) {
                                        selectedIndices.remove(index.id)
                                    } else {
                                        selectedIndices.insert(index.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Indices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}



#Preview {
    IndexComparisonView(accountManager: AccountManager())
}