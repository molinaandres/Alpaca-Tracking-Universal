import SwiftUI
import Charts

struct TWRChartPoint: Identifiable, Decodable {
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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f.date(from: date) ?? Date()
    }
}

struct IndexComparisonView: View {
    @ObservedObject var accountManager: AccountManager
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var indexDataManager = IndexDataManager()
    @State private var selectedAccount: UUID?
    @State private var portfolioHistory: [PortfolioHistoryDataPoint] = []
    @State private var indexHistories: [IndexHistory] = []
    @State private var selectedIndices: Set<String> = ["sp500"]
    @State private var comparisons: [IndexComparison] = []
    @State private var isLoading = false
    @State private var isTWRLoading = false
    @State private var errorMessage: String?
    @State private var selectedPeriod: PortfolioHistoryPeriod = .oneMonth
    @State private var selectedTimeframe: PortfolioHistoryTimeframe = .oneDay
    @State private var customStartDate: Date = Date()
    @State private var customEndDate: Date = Date()
    @State private var lastUpdateDate: Date? = nil
    @State private var twrData: [NormalizedDataPoint] = [] // Always-used TWR series for portfolio
    @State private var isSeriesReady: Bool = false
    
    // Callback para navegar a Performance
    var onNavigateToPerformance: (() -> Void)? = nil
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if accountManager.accounts.isEmpty {
                    emptyStateView
                } else {
                    HStack(spacing: 0) {
                        // Sidebar con cuentas
                        accountsSidebar
                        
                        Divider()
                        
                        // Vista principal de comparación
                        if selectedAccount != nil {
                            comparisonMainView
                        } else {
                            selectAccountView
                        }
                    }
                }
            }
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
            // Initialize custom dates when switching to custom period
            if newPeriod == .custom {
                guard let selectedAccount = selectedAccount,
                      let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else {
                    return
                }
                
                let calendar = Calendar.current
                let today = Date()
                
                // Set end date to today
                customEndDate = today
                
                // Set start date to 30 days ago, but not before firstTradeDate
                let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today
                let firstTradeDate = account.firstTradeDate ?? Date.distantPast
                
                // Use the later of: 30 days ago or firstTradeDate
                customStartDate = max(thirtyDaysAgo, firstTradeDate)
            }
            
            // Validate and adjust timeframe when period changes
            validateTimeframeSelection()
            
            // Solo cargar datos automáticamente si no es período personalizado
            if newPeriod != .custom {
                loadComparisonData()
            }
        }
        .onChange(of: selectedTimeframe) { _, newTimeframe in
            // Reload data when timeframe changes
            if selectedAccount != nil {
                loadComparisonData()
            }
        }
    }
    
    
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
    
    private var accountsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sección de cuentas
            VStack(alignment: .leading, spacing: 0) {
                Text("Accounts")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                
                List(SettingsManager.shared.ordered(accountManager.allAccounts), id: \.id) { account in
                    AccountRow(
                        account: account,
                        isSelected: selectedAccount == account.id,
                        accountManager: accountManager,
                        onSelect: { selectedAccount = account.id }
                    )
                }
                .listStyle(SidebarListStyle())
                .background(Color(NSColor.controlBackgroundColor))
            }
            
            // Separador
            Divider()
            
            // Sección de índices
            VStack(alignment: .leading, spacing: 0) {
                Text("Indexes")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                
            // Selector de índices
            IndexSelector(
                selectedIndices: $selectedIndices,
                availableIndices: Index.allIndices
            )
            .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 60) // Aumentar padding inferior para evitar superposición con botón de configuración
            }
        }
        .frame(width: 220)
    }
    
    private var selectAccountView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("Select an account")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Choose an account from the list to compare with indices")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var comparisonMainView: some View {
        VStack(spacing: 0) {
            // Controles
            controlsView
            
            Divider()
            
            // Contenido principal
            if isLoading || !isSeriesReady {
                loadingView
            } else if let errorMessage = errorMessage {
                errorView(errorMessage)
            } else if comparisons.isEmpty && twrData.isEmpty {
                noDataView
            } else {
                comparisonContentView
            }
        }
    }
    
    private var controlsView: some View {
        VStack(spacing: 16) {
            // Nombre de la cuenta seleccionada
            if let selectedAccount = selectedAccount,
               let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(account.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(account.isLiveTrading ? "Live Trading" : "Paper Trading")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        if let lastUpdate = lastUpdateDate {
                            Text("Last update:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(lastUpdate, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Botón de navegación a Performance
                        Button(action: {
                            onNavigateToPerformance?()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.caption)
                                Text("Performance")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Selectores de período y fechas personalizadas en una sola línea
            HStack {
                // Selector de período
                VStack(alignment: .leading, spacing: 8) {
                    Text("Period")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 0) {
                        let filteredPeriods = PortfolioHistoryPeriod.allCases.filter { $0 != .oneDay }
                        ForEach(Array(filteredPeriods.enumerated()), id: \.element) { index, period in
                            Button(action: {
                                selectedPeriod = period
                            }) {
                                Text(period.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(selectedPeriod == period ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(minWidth: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selectedPeriod == period ? Color.accentColor : Color.clear)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if index < filteredPeriods.count - 1 {
                                Divider()
                                    .frame(height: 20)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                
                // Selector de fechas personalizadas (solo visible cuando se selecciona "Personalizado")
                if selectedPeriod == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rango de fechas")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        InlineDateRangePicker(
                            startDate: $customStartDate,
                            endDate: $customEndDate,
                            firstTradeDate: accountManager.allAccounts.first(where: { $0.id == selectedAccount })?.firstTradeDate,
                            onConfirm: {
                                loadComparisonData()
                            }
                        )
                    }
                }
                
                Spacer()
                
                // Selector de granularidad (alineado a la derecha)
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Granularity")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 0) {
                        ForEach(Array(PortfolioHistoryTimeframe.allCases.enumerated()), id: \.element) { index, timeframe in
                            let isValid = selectedPeriod.validTimeframes.contains(timeframe)
                            let isSelected = selectedTimeframe == timeframe
                            
                            Button(action: { 
                                if isValid {
                                    selectedTimeframe = timeframe
                                }
                            }) {
                                Text(timeframe.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(
                                        isValid 
                                            ? (isSelected ? .white : .primary)
                                            : .secondary.opacity(0.5)
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(minWidth: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                isValid 
                                                    ? (isSelected ? Color.accentColor : Color.clear)
                                                    : Color.gray.opacity(0.1)
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(!isValid)
                            
                            if index < PortfolioHistoryTimeframe.allCases.count - 1 {
                                Divider()
                                    .frame(height: 20)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView("Loading index data...")
                .scaleEffect(1.2)
            
            Text("Getting historical data for selected indices")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Error loading data")
                .font(.headline)
                .foregroundColor(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No comparison data")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Comparison data will appear here when available")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var comparisonContentView: some View {
        ScrollView {
            VStack(spacing: 4) {
                // Resumen unificado de comparaciones
                comparisonSummaryView
                
                // Gráfico de comparación
                comparisonChartView
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom)
        }
    }
    
    private var comparisonSummaryView: some View {
        IndexComparisonSummary(comparisons: comparisons)
    }
    
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
                .onAppear {
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }
    
    
    private func loadComparisonData() {
        print("🔍 [Comparison] loadComparisonData called")
        
        // Prevent multiple simultaneous calls
        guard !isTWRLoading else {
            print("🔍 [Comparison] TWR already loading, skipping")
            return
        }
        
        isSeriesReady = false
        guard let selectedAccount = selectedAccount,
              let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else {
            print("❌ [Comparison] No account selected")
            return
        }
        
        print("🔍 [Comparison] Selected account: \(account.name)")
        
        // Set loading flags immediately to prevent duplicate calls
        isTWRLoading = true
        isLoading = true
        errorMessage = nil
        
        // Small async to align with UI thread without throttling by time
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.performActualLoad(for: account)
        }
    }
    
    private func performActualLoad(for account: AlpacaAccount) {
        // Always compute TWR curve for portfolio
        if account.name == "Total Accounts" {
            loadTotalAccountsComparisonData()
            return
        } else {
            // Individual accounts via embedded runner, identical to Performance macOS
            let dateRange = selectedPeriod.customDateRange(for: account)
            let startDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
            let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
            
            performTWRCalculation(for: account, startDate: startDate, endDate: endDate)
        }
    }
    
    private func performTWRCalculation(for account: AlpacaAccount, startDate: Date, endDate: Date) {
        print("🔍 [Comparison] performTWRCalculation called for \(account.name)")
        let creds = account.getDecryptedCredentials()
        
        do {
            
            let data = try TWREmbeddedRunner.run(
                apiKey: creds.apiKey,
                secretKey: creds.secretKey,
                startDate: startDate,
                endDate: endDate,
                timeframe: selectedTimeframe,
                extendedHours: true
            )
            
            
            
            
            // Try manual decoding instead of JSONDecoder
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NSError(domain: "TWRDecoding", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse JSON as array"])
            }
            
            
            
            let mapped: [NormalizedDataPoint] = jsonArray.compactMap { dict in
                guard let dateStr = dict["date"] as? String,
                      let cumulativeTWR = dict["cumulative_twr"] as? Double else {
                    print("❌ [Comparison] Missing required fields in element: \(dict)")
                    return nil
                }
                
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.timeZone = TimeZone(identifier: "America/New_York")
                let ts = f.date(from: dateStr) ?? Date()
                
                // Use percentage scale like Performance (cumulative_twr already in pct there)
                return NormalizedDataPoint(timestamp: ts, value: cumulativeTWR * 100.0)
            }.sorted { $0.timestamp < $1.timestamp }
            
            print("🔍 [Comparison] Mapped to \(mapped.count) NormalizedDataPoint objects")
            print("🔍 [Comparison] First point: \(mapped.first?.timestamp ?? Date()) value: \(mapped.first?.value ?? 0)")
            print("🔍 [Comparison] Last point: \(mapped.last?.timestamp ?? Date()) value: \(mapped.last?.value ?? 0)")
            
            // Also capture last equity and last date from raw JSON to compute today's point
            let f2 = DateFormatter(); f2.dateFormat = "yyyy-MM-dd"; f2.timeZone = TimeZone(identifier: "America/New_York")
            var lastEquity: Double = 0.0
            var lastDateTs: Date = mapped.last?.timestamp ?? endDate
            if let lastDict = jsonArray.last {
                if let eq = lastDict["equity"] as? Double { lastEquity = eq }
                if let ds = lastDict["date"] as? String, let ts = f2.date(from: ds) { lastDateTs = ts }
            }
            
            // Append/update today's point for individual accounts, using current balance and activities since last historical date
            var finalSeries = mapped
            if let lastPoint = mapped.last {
                let lastCumulativePct = lastPoint.value
                // NY calendar for day bucketing
                var nyCal = Calendar.current; nyCal.timeZone = TimeZone(identifier: "America/New_York")!
                let todayStart = nyCal.startOfDay(for: Date())
                let lastDayStart = nyCal.startOfDay(for: lastDateTs)
                
                // Only consider add/update if today >= lastDay
                if todayStart >= lastDayStart {
                    let creds2 = account.getDecryptedCredentials()
                    let api = AlpacaAPIService(apiKey: creds2.apiKey, secretKey: creds2.secretKey, isLiveTrading: account.isLiveTrading)
                    // Fetch cash flow activities in (lastDay, today]
                    let activitiesStart = lastDayStart
                    let activitiesEnd = todayStart
                    var netBetween: Double = 0.0
                    let dfNY = DateFormatter(); dfNY.dateFormat = "yyyy-MM-dd"; dfNY.timeZone = TimeZone(identifier: "America/New_York")
                    let lastNum = Int(dfNY.string(from: activitiesStart).replacingOccurrences(of: "-", with: "")) ?? 0
                    let todayNum = Int(dfNY.string(from: activitiesEnd).replacingOccurrences(of: "-", with: "")) ?? 0
                    let semaphore = DispatchSemaphore(value: 0)
                    api.getCashFlowActivities(startDate: activitiesStart, endDate: activitiesEnd) { result in
                        switch result {
                        case .success(let acts):
                            for a in acts {
                                guard let ds = a.date else { continue }
                                let n = Int(ds.replacingOccurrences(of: "-", with: "")) ?? 0
                                if n > lastNum && n <= todayNum {
                                    let amt = Double(a.netAmount ?? "0") ?? 0.0
                                    let net = (a.activityType == "CSD") ? amt : (a.activityType == "CSW" ? -amt : 0.0)
                                    netBetween += net
                                }
                            }
                        case .failure:
                            break
                        }
                        semaphore.signal()
                    }
                    // Wait synchronously to keep logic simple inside this callback context
                    _ = semaphore.wait(timeout: .now() + 10)
                    
                    // Determine current balance
                    let currentBalance = self.accountManager.balances[account.id]?.balance ?? lastEquity
                    let adjusted = currentBalance - netBetween
                    let baseEquity = lastEquity > 0 ? lastEquity : currentBalance
                    let daily = baseEquity == 0 ? 0.0 : (adjusted / baseEquity) - 1.0
                    let newCumulativePct = (1.0 + lastCumulativePct/100.0) * (1.0 + daily) * 100.0 - 100.0
                    let todayPoint = NormalizedDataPoint(timestamp: todayStart, value: newCumulativePct)
                    
                    if let idx = finalSeries.firstIndex(where: { nyCal.isDate($0.timestamp, inSameDayAs: todayStart) }) {
                        finalSeries[idx] = todayPoint
                        print("📅 [Comparison macOS] Updated existing today point at index \(idx)")
                    } else if todayStart > lastDayStart {
                        finalSeries.append(todayPoint)
                        print("📅 [Comparison macOS] Added new today point")
                    }
                    finalSeries.sort { $0.timestamp < $1.timestamp }
                }
            }
            
            // Clamp portfolio series to the originally requested date range (NY day granularity)
            var nyCalClamp = Calendar.current; nyCalClamp.timeZone = TimeZone(identifier: "America/New_York")!
            let startDay = nyCalClamp.startOfDay(for: startDate)
            let endDay = nyCalClamp.startOfDay(for: endDate)
            let clampedSeries = finalSeries.filter { dp in
                let d = nyCalClamp.startOfDay(for: dp.timestamp)
                return d >= startDay && d <= endDay
            }

            // Rebase to 0.00% at the first visible day (multiplicative normalization)
            let normalizedSeries: [NormalizedDataPoint] = {
                guard let base = clampedSeries.first?.value else { return clampedSeries }
                let baseProp = 1.0 + base / 100.0
                return clampedSeries.map { dp in
                    let prop = 1.0 + dp.value / 100.0
                    let rebased = (prop / baseProp - 1.0) * 100.0
                    return NormalizedDataPoint(timestamp: dp.timestamp, value: rebased)
                }
            }()

            self.twrData = normalizedSeries
            self.lastUpdateDate = Date()
            self.isTWRLoading = false
            // Use original date range to avoid +1 day offset when TWR extends to today
            self.loadIndexDataUsingTwrRange(startDate: startDate, endDate: endDate)
            print("✅ [Comparison] TWR calculation completed successfully")
        } catch {
            print("❌ [Comparison] TWR calculation failed: \(error.localizedDescription)")
            self.isLoading = false
            self.isTWRLoading = false
            self.errorMessage = error.localizedDescription
        }
    }
    
    private func loadTotalAccountsComparisonData() {
        
        // For Total Accounts, we need to aggregate data from all real accounts
        let dateRange = selectedPeriod.customDateRange(for: accountManager.allAccounts.first { $0.name == "Total Accounts" } ?? AlpacaAccount(id: UUID(), name: "Total Accounts", description: "", alpacaAccountId: nil, apiKey: "", secretKey: "", isLiveTrading: false, isEncrypted: false, firstTradeDate: nil))
        let startDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
        let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
        
        
        
        accountManager.getTotalAccountsTWR(
            startDate: startDate,
            endDate: endDate,
            timeframe: selectedTimeframe
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                self.isTWRLoading = false
                
                switch result {
                case .success(let points):
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York")
                    let mapped: [NormalizedDataPoint] = points.map { p in
                        NormalizedDataPoint(timestamp: f.date(from: p.date) ?? Date(), value: p.cumulative_twr * 100.0)
                    }.sorted { $0.timestamp < $1.timestamp }
                    
                    self.twrData = mapped
                    self.errorMessage = nil
                    // Use original date range to avoid +1 day offset when TWR extends to today
                    self.loadIndexDataUsingTwrRange(startDate: startDate, endDate: endDate)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.twrData = []
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
                        self.calculateComparisons(indexHistories: indexHistories)
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
                    self.calculateComparisons(indexHistories: indexHistories)
                    self.lastUpdateDate = Date()
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func loadIndexDataUsingTwrRange(startDate: Date?, endDate: Date?) {
        print("🔍 [Comparison] loadIndexDataUsingTwrRange called")
        let indices = Index.allIndices.filter { selectedIndices.contains($0.id) }
        guard let s = startDate, let e = endDate else {
            print("❌ [Comparison] No valid date range for index data")
            self.isLoading = false; return
        }
        
        print("🔍 [Comparison] Loading index data for range: \(s) to \(e)")
        print("🔍 [Comparison] Selected indices: \(indices.map { $0.name })")
        
        indexDataManager.fetchMultipleIndexHistories(
            indices: indices,
            startDate: s,
            endDate: e
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let indexHistories):
                    print("🔍 [Comparison] Index data success: \(indexHistories.count) histories")
                    self.indexHistories = indexHistories
                    self.calculateComparisons(indexHistories: indexHistories)
                    self.lastUpdateDate = Date()
                    self.isSeriesReady = true
                    print("✅ [Comparison] Index data loading completed successfully")
                case .failure(let error):
                    print("❌ [Comparison] Index data loading failed: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    self.isSeriesReady = true
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
                    self.calculateComparisons(indexHistories: indexHistories)
                    self.lastUpdateDate = Date()
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func calculateComparisons(indexHistories: [IndexHistory]) {
        var newComparisons: [IndexComparison] = []
        
        let isTotalAccounts: Bool = {
            if let selectedAccount = selectedAccount,
               let acc = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                return acc.name == "Total Accounts"
            }
            return false
        }()
        
        // Use TWR series (percentage) if available; otherwise fall back to processed portfolioHistory
        let portfolioSeries: [PortfolioHistoryDataPoint] = {
            if !twrData.isEmpty {
                return twrData.map { point in
                    PortfolioHistoryDataPoint(
                        timestamp: point.timestamp,
                        equity: point.value,
                        profitLoss: 0,
                        profitLossPct: point.value,
                        baseValue: point.value
                    )
                }
            } else {
                return portfolioHistory
            }
        }()
        
        for indexHistory in indexHistories {
            if let comparison = indexDataManager.calculateComparison(
                portfolioHistory: portfolioSeries,
                indexHistory: indexHistory,
                isTotalAccounts: isTotalAccounts
            ) {
                newComparisons.append(comparison)
            }
        }
        
        comparisons = newComparisons
    }
    
    private func validateTimeframeSelection() {
        let validTimeframes = selectedPeriod.validTimeframes
        if !validTimeframes.contains(selectedTimeframe) {
            // If current timeframe is not valid for the selected period, 
            // select the first valid timeframe
            selectedTimeframe = validTimeframes.first ?? .oneDay
        }
    }
    
    private func validateCustomDatesForCurrentAccount() {
        guard let selectedAccount = selectedAccount,
              let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else {
            return
        }
        
        let firstTradeDate = account.firstTradeDate ?? Date.distantPast
        
        // Validate start date - ensure it's not before firstTradeDate
        if customStartDate < firstTradeDate {
            let calendar = Calendar.current
            let today = Date()
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today
            
            // Use the later of: 30 days ago or firstTradeDate
            customStartDate = max(thirtyDaysAgo, firstTradeDate)
        }
        
        // Validate end date - ensure it's not before start date
        if customEndDate < customStartDate {
            customEndDate = Date()
        }
    }
    
    
}

// MARK: - Supporting Views


struct ComparisonChartView: View {
    let portfolioData: [NormalizedDataPoint] // Changed from portfolioHistory
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
    
    // Datos normalizados del portfolio (porcentajes incrementales desde 0%)
    private var normalizedPortfolioData: [NormalizedDataPoint] {
        // Siempre usar porcentajes (TWR/porcentaje de retorno), no equity
        // Para Total Accounts ya usamos profitLossPct del histórico agregado
        // Para cuentas individuales, usar profitLossPct del histórico de Alpaca
        return portfolioData // Now refers to the passed-in portfolioData
            .filter { $0.value.isFinite } // Filter by value, not profitLossPct
            .map { NormalizedDataPoint(timestamp: normalizeDateToDay($0.timestamp), value: $0.value) } // Use value directly
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
        let portfolioValues = normalizedPortfolioData.map { $0.value }
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
                .frame(height: 300)
                .frame(maxWidth: .infinity)
            } else {
                // Gráfico interactivo principal
                ZStack {
                    interactiveChart
                    tooltipView
                    dateRangeOverlay
                }
                .frame(height: 350)
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
            .padding(.top, 1)
            .padding(.bottom, 2)
        }
    }
    
    private func indexColor(for index: Index) -> Color {
        switch index.id {
        case "sp500":
            return .red
        case "nasdaq":
            return .yellow
        case "msci_world":
            return .purple
        default:
            return .gray
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
            .onHover { isHovering in
                if isHovering {
                    // Hover started
                } else {
                    selectedTimestamp = nil
                    self.isHovering = false
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    handleHoverInteraction(at: location, in: geometry)
                case .ended:
                    selectedTimestamp = nil
                    isHovering = false
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
        allTimestamps.append(contentsOf: normalizedPortfolioData.map { $0.timestamp })
        
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
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
            .position(
                x: min(max(hoverLocation.x, 150), 800),
                y: hoverLocation.y - 80
            )
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedTimestamp)
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.regularMaterial.opacity(0.8))
                        )
                        .padding(.trailing, 8)
                        .padding(.bottom, 20) // Moved up from 8 to 20 to fit within chart area
                }
            }
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


// Estructuras de datos para normalización
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

#Preview {
    IndexComparisonView(accountManager: AccountManager())
}
