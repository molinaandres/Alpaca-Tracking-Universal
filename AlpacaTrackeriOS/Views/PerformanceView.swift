import SwiftUI
import Charts
import Combine

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

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
    var cumulative_twr: Double
    var timestamp: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f.date(from: date) ?? Date()
    }
}

struct PerformanceView: View {
    @ObservedObject var accountManager: AccountManager
    @StateObject private var settingsManager = SettingsManager.shared
    let onNavigateToComparison: (() -> Void)?
    @State private var selectedAccount: UUID?
    @State private var portfolioHistory: [PortfolioHistoryDataPoint] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDataPoint: PortfolioHistoryDataPoint?
    @State private var isHovering = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var selectedPeriod: PortfolioHistoryPeriod = .oneMonth
    @State private var selectedTimeframe: PortfolioHistoryTimeframe = .oneDay
    @State private var customStartDate: Date = Date()
    @State private var customEndDate: Date = Date()
    @State private var totalAccountsStartBalance: Double = 0.0
    @State private var showingAccountPicker = false
    @State private var showTWR: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if accountManager.allAccounts.isEmpty {
                    // Estado vacío
                    VStack(spacing: 16) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No accounts configured")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Add an Alpaca account to view performance")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Header compacto
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
                                                Text("\(EuropeanNumberFormatter.shared.format(dailyChange, fractionDigits: 2))%")
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
                                    // Disable 1Day when the selected account is Total Accounts
                                    let isTotalAccounts = {
                                        if let selectedAccount = selectedAccount,
                                           let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                                            return account.name == "Total Accounts"
                                        }
                                        return false
                                    }()
                                    let isDisabled = isTotalAccounts && period == .oneDay
                                    Button(action: { 
                                        selectedPeriod = period
                                        // Special handling for oneDay period
                                        if period == .oneDay {
                                            selectedTimeframe = .oneHour
                                        }
                                    }) {
                                        Label(period.displayName, systemImage: selectedPeriod == period ? "checkmark" : "")
                                    }
                                    .disabled(isDisabled)
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
                            
                            // Selector de fechas personalizadas compacto
                            if selectedPeriod == .custom {
                                InlineDateRangePicker(
                                    startDate: $customStartDate,
                                    endDate: $customEndDate,
                                    firstTradeDate: accountManager.allAccounts.first(where: { $0.id == selectedAccount })?.firstTradeDate,
                                    onConfirm: {
                                        loadPortfolioHistory()
                                    }
                                )
                            }
                            
                            Spacer()
                            
                            // TWR Toggle with label on the left (macOS-style)
                            HStack(spacing: 6) {
                                Text("TWR")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Toggle("", isOn: $showTWR)
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                                    .scaleEffect(0.8)
                            }
                            .onChange(of: showTWR) { _, newValue in
                                if let selectedAccount = selectedAccount,
                                   let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                                    SettingsManager.shared.setShowTWR(newValue, for: account.id.uuidString)
                                }
                            }
                            
                            // Timeframe Selector
                            Menu {
                                ForEach(PortfolioHistoryTimeframe.allCases, id: \.self) { timeframe in
                                    // Disable 1Day timeframe when period is 1Day
                                    let isValid = selectedPeriod.validTimeframes.contains(timeframe) && !(selectedPeriod == .oneDay && timeframe == .oneDay)
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
                    }
                    .padding(.horizontal, 16)
                    .background(ColorCompatibility.systemBackground())
                    
                    Divider()
                    
                    // Contenido principal con ScrollView
                    ScrollView {
                        if let selectedAccount = selectedAccount,
                           let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                            PerformanceDetailView(
                                account: account,
                                accountManager: accountManager,
                                onLoadPortfolioHistory: loadPortfolioHistory,
                                onNavigateToComparison: onNavigateToComparison,
                                portfolioHistory: $portfolioHistory,
                                isLoading: $isLoading,
                                errorMessage: $errorMessage,
                                selectedDataPoint: $selectedDataPoint,
                                isHovering: $isHovering,
                                hoverLocation: $hoverLocation,
                                selectedPeriod: $selectedPeriod,
                                selectedTimeframe: $selectedTimeframe,
                                customStartDate: $customStartDate,
                                customEndDate: $customEndDate,
                                isTimeframeValid: isTimeframeValid,
                                selectedAccount: selectedAccount,
                                totalAccountsStartBalance: $totalAccountsStartBalance,
                                showTWR: $showTWR
                            )
                            .frame(minHeight: 600) // Asegurar altura mínima para scrolling
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "person.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                
                                Text("Select an account")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("Choose an account to view its performance")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 400)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ColorCompatibility.appBackground())
        }
        .sheet(isPresented: $showingAccountPicker) {
            AccountPickerView(
                accounts: SettingsManager.shared.ordered(accountManager.allAccounts),
                selectedAccount: $selectedAccount,
                accountManager: accountManager
            )
        }
        .onAppear {
            // Cargar configuraciones guardadas
            loadSavedSettings()
            
            if selectedAccount == nil && !accountManager.allAccounts.isEmpty {
                selectedAccount = SettingsManager.shared.ordered(accountManager.allAccounts).first?.id
            }
            // Validate initial timeframe selection
            validateTimeframeSelection()
            // Enforce minimum period for Total Accounts
            enforceMinimumPeriodForTotalAccounts()
            
            // Load initial data
            if selectedAccount != nil {
                loadPortfolioHistory()
            }
        }
        .onChange(of: selectedAccount) { _, _ in
            // Restore per-account TWR toggle state on account switch
            if let selectedAccount = selectedAccount,
               let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                showTWR = SettingsManager.shared.showTWR(for: account.id.uuidString)
            } else {
                showTWR = false
            }
            // Validate custom dates when account changes
            if selectedPeriod == .custom {
                validateCustomDatesForCurrentAccount()
            }
            
            // Load data when account changes
            if selectedAccount != nil {
                // Ensure valid period for Total Accounts
                enforceMinimumPeriodForTotalAccounts()
                loadPortfolioHistory()
                // TWR se recargará desde PerformanceDetailView al reconstruirse la vista
            }
        }
        .onChange(of: selectedPeriod) { _, newPeriod in
            // Guardar configuración
            if let portfolioPeriod = PortfolioPeriod(rawValue: newPeriod.rawValue) {
                settingsManager.updateDefaultPeriod(portfolioPeriod)
            }
            
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
            // Reload data when period changes
            if selectedAccount != nil {
                loadPortfolioHistory()
            }
        }
        .onChange(of: selectedTimeframe) { _, newTimeframe in
            // Guardar configuración
            if let timeframe = Timeframe(rawValue: newTimeframe.rawValue) {
                settingsManager.updateDefaultTimeframe(timeframe)
            }
            
            // Reload data when timeframe changes
            if selectedAccount != nil {
                loadPortfolioHistory()
            }
        }
        .onChange(of: selectedAccount) { _, newAccountId in
            // Guardar cuenta seleccionada
            if let newAccountId = newAccountId {
                settingsManager.updateSelectedAccount(newAccountId.uuidString)
            }
        }
    }
    
    /// Si la cuenta seleccionada es Total Accounts y el periodo es 1 Day, forzar 1 Week
    private func enforceMinimumPeriodForTotalAccounts() {
        guard let selectedAccount = selectedAccount,
              let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else { return }
        if account.name == "Total Accounts" && selectedPeriod == .oneDay {
            selectedPeriod = .oneWeek
        }
    }
    
    private func loadSavedSettings() {
        // Cargar período por defecto
        if let savedPeriod = PortfolioHistoryPeriod(rawValue: settingsManager.appSettings.defaultPeriod.rawValue) {
            selectedPeriod = savedPeriod
        }
        
        // Cargar timeframe por defecto
        if let savedTimeframe = PortfolioHistoryTimeframe(rawValue: settingsManager.appSettings.defaultTimeframe.rawValue) {
            selectedTimeframe = savedTimeframe
        }
        // prevEquity retained via lastHistEquity reference; no separate unused var needed
        // Cargar cuenta seleccionada
        if let selectedAccountId = settingsManager.appSettings.selectedAccountId,
           let accountId = UUID(uuidString: selectedAccountId) {
            selectedAccount = accountId
        }
    }
    
    private func loadPortfolioHistory() {
        guard let selectedAccount = selectedAccount,
              let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Handle Total Accounts case
        if account.name == "Total Accounts" {
            loadTotalAccountsPortfolioHistory()
            return
        }
        
        let credentials = account.getDecryptedCredentials()
        
        let apiService = AlpacaAPIService(
            apiKey: credentials.apiKey,
            secretKey: credentials.secretKey,
            isLiveTrading: account.isLiveTrading
        )
        
        // All periods now use custom date ranges with firstTradeDate validation
        // Calcular rango exacto según periodo, igual que macOS
        let dateRange = selectedPeriod.customDateRange(for: account)
        let startDate = selectedPeriod == .custom ? Calendar.current.startOfDay(for: customStartDate) : Calendar.current.startOfDay(for: dateRange.startDate)
        let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
        
        // Use custom date range for all periods
        apiService.getPortfolioHistoryWithCustomDateRange(
            startDate: startDate,
            endDate: endDate,
            timeframe: selectedTimeframe
        ) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let history):
                    let processedData = Self.processPortfolioHistory(history, currentAccount: account, accountManager: accountManager, selectedPeriod: selectedPeriod, customStartDate: startDate, customEndDate: endDate, selectedTimeframe: selectedTimeframe)
                    portfolioHistory = processedData
                    errorMessage = nil
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    portfolioHistory = []
                }
            }
        }
    }
    
    private func loadTotalAccountsPortfolioHistory() {
        // For Total Accounts, we need to aggregate data from all real accounts
        // Use the new method to get performance history for Total Accounts
        let dateRange = selectedPeriod.customDateRange(for: accountManager.allAccounts.first { $0.name == "Total Accounts" } ?? AlpacaAccount(id: UUID(), name: "Total Accounts", description: "", alpacaAccountId: nil, apiKey: "", secretKey: "", isLiveTrading: false, isEncrypted: false, firstTradeDate: nil))
        // Clamp start to earliest firstTradeDate among real accounts
        let earliestFirstTrade = accountManager.realAccounts.compactMap { $0.firstTradeDate }.min() ?? dateRange.startDate
        let baseStartDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
        let startDate = max(baseStartDate, earliestFirstTrade)
        let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
        
        // Load both portfolio history and start balance
        let group = DispatchGroup()
        
        // Load portfolio history
        group.enter()
        accountManager.getTotalAccountsPerformanceHistory(
            startDate: startDate,
            endDate: endDate,
            timeframe: selectedTimeframe
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let history):
                    // Clamp to earliest firstTradeDate among real accounts
                    let earliestFirstTrade = accountManager.realAccounts.compactMap { $0.firstTradeDate }.min()
                    let clamped: [PortfolioHistoryDataPoint]
                    if let earliest = earliestFirstTrade {
                        let startOfDay = Calendar.current.startOfDay(for: earliest)
                        clamped = history.filter { $0.timestamp >= startOfDay }
                    } else {
                        clamped = history
                    }
                    // For Total Accounts, trim to first equity>0 with change between t and t+1
                    if let earliest = earliestFirstTrade, let firstIdx = clamped.firstNonZeroChangeIndex(startDate: Calendar.current.startOfDay(for: earliest)) {
                        self.portfolioHistory = Array(clamped.suffix(from: firstIdx))
                    } else if let firstIdx = clamped.firstNonZeroChangeIndex() {
                        self.portfolioHistory = Array(clamped.suffix(from: firstIdx))
                    } else {
                        self.portfolioHistory = []
                    }
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.portfolioHistory = []
                }
                group.leave()
            }
        }
        
        // Load start balance
        group.enter()
        accountManager.getTotalAccountsStartBalance(
            startDate: startDate,
            endDate: endDate,
            timeframe: selectedTimeframe
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let startBalance):
                    self.totalAccountsStartBalance = startBalance
                case .failure(_):
                    self.totalAccountsStartBalance = 0.0
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.isLoading = false
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
    
    private func isTimeframeValid(_ timeframe: PortfolioHistoryTimeframe) -> Bool {
        return selectedPeriod.validTimeframes.contains(timeframe)
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
    
    static func processPortfolioHistory(_ history: PortfolioHistory, currentAccount: AlpacaAccount, accountManager: AccountManager, selectedPeriod: PortfolioHistoryPeriod, customStartDate: Date, customEndDate: Date, selectedTimeframe: PortfolioHistoryTimeframe) -> [PortfolioHistoryDataPoint] {
        
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
            let adjustedTimestamp = selectedTimeframe.adjustAlpacaDate(originalTimestamp)
            
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
        
        // All periods now use custom date ranges, so filter data by date range
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: customStartDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate)) ?? customEndDate
        
        dataPoints = dataPoints.filter { dataPoint in
            let dataPointDate = dataPoint.timestamp
            return dataPointDate >= startOfDay && dataPointDate < endOfDay
        }
        
        // Add current point with real portfolio value only if today is included in the date range
        let shouldAddCurrentPoint: Bool
        let today = Date()
        let startOfToday = calendar.startOfDay(for: today)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? today
        
        shouldAddCurrentPoint = customStartDate <= endOfToday && customEndDate >= startOfToday
        
        if shouldAddCurrentPoint, let currentBalance = accountManager.balances[currentAccount.id] {
            let today = Date()
            let currentEquity = currentBalance.balance
            let calendar = Calendar.current
            
            // Verificar si ya existe un punto para hoy en los datos de la API
            let existingPointIndex = dataPoints.firstIndex { dataPoint in
                calendar.isDate(dataPoint.timestamp, inSameDayAs: today)
            }
            
            if let existingIndex = existingPointIndex {
                // Si ya existe un punto para hoy, sobrescribir con el valor actual
                
                let lastHistoricalPoint = existingIndex > 0 ? dataPoints[existingIndex - 1] : dataPoints[existingIndex]
                let change = currentEquity - lastHistoricalPoint.equity
                let changePct = (change / lastHistoricalPoint.equity) * 100
                
                dataPoints[existingIndex] = PortfolioHistoryDataPoint(
                    timestamp: dataPoints[existingIndex].timestamp, // Mantener el timestamp original
                    equity: currentEquity,
                    profitLoss: change,
                    profitLossPct: changePct,
                    baseValue: lastHistoricalPoint.baseValue
                )
            } else {
                // Si no existe un punto para hoy, añadir uno nuevo
                
                if let lastHistoricalPoint = dataPoints.last {
                    let change = currentEquity - lastHistoricalPoint.equity
                    let changePct = (change / lastHistoricalPoint.equity) * 100
                    
                    let currentDataPoint = PortfolioHistoryDataPoint(
                        timestamp: today,
                        equity: currentEquity,
                        profitLoss: change,
                        profitLossPct: changePct,
                        baseValue: lastHistoricalPoint.baseValue
                    )
                    dataPoints.append(currentDataPoint)
                }
            }
        }
        
        return dataPoints.sorted { $0.timestamp < $1.timestamp }
    }
}


struct PerformanceDetailView: View {
    let account: AlpacaAccount
    @ObservedObject var accountManager: AccountManager
    let onLoadPortfolioHistory: () -> Void
    let onNavigateToComparison: (() -> Void)?
    @Binding var portfolioHistory: [PortfolioHistoryDataPoint]
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    @Binding var selectedDataPoint: PortfolioHistoryDataPoint?
    @Binding var isHovering: Bool
    @Binding var hoverLocation: CGPoint
    @Binding var selectedPeriod: PortfolioHistoryPeriod
    @Binding var selectedTimeframe: PortfolioHistoryTimeframe
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    let isTimeframeValid: (PortfolioHistoryTimeframe) -> Bool
    let selectedAccount: UUID?
    @Binding var totalAccountsStartBalance: Double
    @Binding var showTWR: Bool
    
    @State private var chartWidth: CGFloat = 0
    // TWR Total Accounts (iOS)
    @State private var twrPoints: [TWRChartPoint] = []
    @State private var isTwrLoading: Bool = false
    @State private var twrError: String?
    
    // TWR Individual Accounts (iOS)
    @State private var individualTwrPoints: [TWRChartPoint] = []
    @State private var isIndividualTwrLoading: Bool = false
    @State private var individualTwrError: String?
    @State private var selectedTwrPoint: TWRChartPoint?
    @State private var twrHoverLocation: CGPoint = .zero
    // Gate rendering until the TWR/equity series is fully ready (today point + clamp + rebase)
    @State private var isSeriesReady: Bool = false
    
    private func loadTWR() {
        guard showTWR else { return }
        // Gate rendering until the series is finalized
        isSeriesReady = false
        if account.name == "Total Accounts" {
            loadTWRForTotalAccounts()
        } else {
            loadTWRForIndividualAccount()
        }
    }

    private func loadTWRForTotalAccounts() {
        guard showTWR else {
            twrPoints = []
            twrError = nil
            return
        }
        
        guard account.name == "Total Accounts" else {
            twrPoints = []
            twrError = nil
            return
        }
        
        let dateRange = selectedPeriod.customDateRange(for: account)
        let startDate = selectedPeriod == .custom ? Calendar.current.startOfDay(for: customStartDate) : Calendar.current.startOfDay(for: dateRange.startDate)
        let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
        
        isTwrLoading = true
        twrError = nil
        // Starting iOS TWR Total
        
        accountManager.getTotalAccountsTWR(
            startDate: startDate,
            endDate: endDate,
            timeframe: selectedTimeframe
        ) { result in
            DispatchQueue.main.async {
                self.isTwrLoading = false
                switch result {
                case .success(let points):
                    // Map TWRPoint to TWRChartPoint format (same as macOS)
                    let mapped = points.map { p in
                        TWRChartPoint(
                            id: UUID(),
                            date: p.date,
                            equity: p.equity,
                            pnl: p.pnl,
                            pnl_pct: p.pnl_pct,
                            deposits: p.deposits,
                            withdrawals: p.withdrawals,
                            net_cash_flow: p.net_cash_flow,
                            daily_return: p.daily_return * 100.0,
                            cumulative_twr: p.cumulative_twr * 100.0
                        )
                    }
                    self.twrPoints = mapped.sorted { $0.timestamp < $1.timestamp }
                    // iOS TWR Total success
                    self.twrError = nil
                    // Series ready for rendering (no extra clamp/rebase needed here)
                    self.isSeriesReady = true
                case .failure(let error):
                    self.twrError = error.localizedDescription
                    // iOS TWR Total error
                    self.twrPoints = []
                    // Even on error, unblock UI to show error view
                    self.isSeriesReady = true
                }
            }
        }
    }
    
    private func loadTWRForIndividualAccount() {
        guard showTWR else {
            individualTwrPoints = []
            individualTwrError = nil
            return
        }
        
        guard account.name != "Total Accounts" else {
            individualTwrPoints = []
            individualTwrError = nil
            return
        }
        
        let dateRange = selectedPeriod.customDateRange(for: account)
        let baseStartDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
        let startDate: Date
        if account.name == "Total Accounts" {
            let earliestFirstTrade = accountManager.realAccounts.compactMap { $0.firstTradeDate }.min() ?? baseStartDate
            startDate = max(baseStartDate, earliestFirstTrade)
        } else {
            startDate = baseStartDate
        }
        let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate
        
        isIndividualTwrLoading = true
        individualTwrError = nil
        
        // Usar el mismo método que Total Accounts para cuentas individuales
        let credentials = account.getDecryptedCredentials()
        let apiService = AlpacaAPIService(
            apiKey: credentials.apiKey,
            secretKey: credentials.secretKey,
            isLiveTrading: account.isLiveTrading
        )
        
        // Obtener portfolio history y actividades en paralelo
        let group = DispatchGroup()
        var portfolioHistory: [PortfolioHistoryDataPoint] = []
        var activities: [AccountActivity] = []
        var errors: [Error] = []
        
        // Portfolio history
        group.enter()
        apiService.getPortfolioHistoryWithCustomDateRange(
            startDate: startDate,
            endDate: endDate,
            timeframe: selectedTimeframe
        ) { result in
            switch result {
            case .success(let history):
                portfolioHistory = PerformanceView.processPortfolioHistory(
                    history,
                    currentAccount: account,
                    accountManager: accountManager,
                    selectedPeriod: selectedPeriod,
                    customStartDate: startDate,
                    customEndDate: endDate,
                    selectedTimeframe: selectedTimeframe
                )
            case .failure(let error):
                errors.append(error)
            }
            group.leave()
        }
        
        // Cash flow activities
        group.enter()
        apiService.getCashFlowActivities(
            startDate: startDate,
            endDate: endDate
        ) { result in
            switch result {
            case .success(let activitiesResult):
                activities = activitiesResult
            case .failure(let error):
                errors.append(error)
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            if !errors.isEmpty {
                self.individualTwrError = errors.first?.localizedDescription ?? "Unknown error"
                self.individualTwrPoints = []
                self.isIndividualTwrLoading = false
                return
            }
            
            // Implementar TWR inline (igual que AccountManager)
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "America/New_York")
            
            // Crear lista de actividades con fecha normalizada y valor neto
            var allFlows: [(dateNum: Int, net: Double, type: String)] = []
            var flowsByDate: [String: Double] = [:]
            for activity in activities {
                guard let ds = activity.date else { continue }
                let amount = Double(activity.netAmount ?? "0") ?? 0.0
                let flow = (activity.activityType == "CSD") ? amount : -amount
                flowsByDate[ds, default: 0.0] += flow
                if let dn = Int(ds.replacingOccurrences(of: "-", with: "")) {
                    allFlows.append((dateNum: dn, net: flow, type: activity.activityType))
                }
            }
            
            // Procesar portfolio history
            var result: [TWRChartPoint] = []
            var cumulative: Double = 1.0
            var prevEquity: Double = 0.0
            
            let sortedHistory = portfolioHistory.sorted { $0.timestamp < $1.timestamp }
            
            for (idx, point) in sortedHistory.enumerated() {
                let dateStr = df.string(from: point.timestamp)
                // Cash flows for interval (prevDay, currDay]
                var netFlow: Double = 0.0
                if idx > 0 {
                    let prevDateStr = df.string(from: sortedHistory[idx - 1].timestamp)
                    let prevNum = Int(prevDateStr.replacingOccurrences(of: "-", with: "")) ?? 0
                    let currNum = Int(dateStr.replacingOccurrences(of: "-", with: "")) ?? 0
                    netFlow = allFlows.filter { $0.dateNum > prevNum && $0.dateNum <= currNum }.reduce(0.0) { $0 + $1.net }
                }
                let deposits = max(0.0, netFlow)
                let withdrawals = max(0.0, -netFlow)
                
                let dailyReturn: Double
                if idx == 0 || prevEquity == 0 {
                    dailyReturn = 0.0
                    if point.equity > 0 { cumulative = 1.0 }
                } else {
                    let adjustedEquity = point.equity - netFlow
                    dailyReturn = prevEquity == 0 ? 0.0 : (adjustedEquity / prevEquity) - 1.0
                    cumulative *= (1.0 + dailyReturn)
                }
                
                let twrPoint = TWRChartPoint(
                    id: UUID(),
                    date: dateStr,
                    equity: point.equity,
                    pnl: point.profitLoss,
                    pnl_pct: point.profitLossPct,
                    deposits: deposits,
                    withdrawals: withdrawals,
                    net_cash_flow: netFlow,
                    daily_return: dailyReturn * 100.0,
                    cumulative_twr: (cumulative - 1.0) * 100.0 // Convertir a porcentaje
                )
                
                result.append(twrPoint)
                prevEquity = point.equity
            }
            
            self.individualTwrPoints = result.sorted { $0.timestamp < $1.timestamp }

            // Añadir/actualizar punto de hoy para alinear final de gráfico con equity
            self.appendOrUpdateTodayTwrPointIndividual(sortedHistory: sortedHistory, allFlows: allFlows)
            // Clamp rango visible a equity y rebase acumulado desde el inicio visible
            self.clampIndividualTwrToEquityRange()
            self.rebaseIndividualTwrFromVisibleStart()
            self.isIndividualTwrLoading = false
            self.isSeriesReady = true
        }
    }

    // MARK: - iOS TWR Helpers (Individual)

    private func clampIndividualTwrToEquityRange() {
        guard let firstEquity = portfolioHistory.first?.timestamp,
              let lastEquity = portfolioHistory.last?.timestamp else { return }
        
        let cal = Calendar.current
        let start = cal.startOfDay(for: firstEquity)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastEquity)) ?? lastEquity
        individualTwrPoints = individualTwrPoints.filter { p in
            p.timestamp >= start && p.timestamp < end
        }
    }

    private func rebaseIndividualTwrFromVisibleStart() {
        guard !individualTwrPoints.isEmpty else { return }
        var cumulative: Double = 1.0
        for i in 0..<individualTwrPoints.count {
            var p = individualTwrPoints[i]
            if i == 0 {
                p.cumulative_twr = 0.0
                cumulative = 1.0
            } else {
                let dailyProp = (p.daily_return / 100.0)
                cumulative *= (1.0 + dailyProp)
                p.cumulative_twr = (cumulative - 1.0) * 100.0
            }
            individualTwrPoints[i] = p
        }
    }

    private func appendOrUpdateTodayTwrPointIndividual(sortedHistory: [PortfolioHistoryDataPoint], allFlows: [(dateNum: Int, net: Double, type: String)]) {
        guard let lastPoint = individualTwrPoints.last else { 
            print("📅 [iOS Perf] No last TWR point found, skipping today point")
            return 
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(identifier: "America/New_York")
        
        // Usar timezone de Alpaca para determinar "hoy"
        var nyCal = Calendar.current
        nyCal.timeZone = TimeZone(identifier: "America/New_York")!
        let today = Date()
        let todayStart = nyCal.startOfDay(for: today)
        
        print("📅 [iOS Perf] Attempting to add today point. Last TWR point: \(lastPoint.date)")
        
        // Si ya hay punto de hoy, actualizarlo; si no, añadirlo
        let lastHistEquity = sortedHistory.last?.equity ?? 0.0
        let lastHistDateStr = df.string(from: sortedHistory.last?.timestamp ?? todayStart)
        let lastHistNum = Int(lastHistDateStr.replacingOccurrences(of: "-", with: "")) ?? 0
        let todayNum = Int(df.string(from: todayStart).replacingOccurrences(of: "-", with: "")) ?? 0
        
        print("📅 [iOS Perf] Last hist date: \(lastHistDateStr) (\(lastHistNum)), Today: \(df.string(from: todayStart)) (\(todayNum))")
        
        // Flujos entre último día histórico y hoy (prevDay, today]
        let netBetween = allFlows.filter { $0.dateNum > lastHistNum && $0.dateNum <= todayNum }.reduce(0.0) { $0 + $1.net }
        let currentBalance = accountManager.balances[account.id]?.balance ?? lastHistEquity
        let adjusted = currentBalance - netBetween
        
        
        // Para el punto de hoy, calcular el daily return basado en el último punto TWR, no en equity histórico
        let lastTwrEquity = lastPoint.equity
        let daily = lastTwrEquity == 0 ? 0.0 : (adjusted / lastTwrEquity) - 1.0
        
        print("📅 [iOS Perf] lastTwrEquity: \(lastTwrEquity), adjusted: \(adjusted), daily: \(daily)")
        
        let lastCumulativeProp = (lastPoint.cumulative_twr / 100.0)
        let newCumulativeProp = lastCumulativeProp * (1.0 + daily)
        
        print("📅 [iOS Perf] netBetween: \(netBetween), currentBalance: \(currentBalance), daily: \(daily), newCumulative: \(newCumulativeProp)")
        
        let newPoint = TWRChartPoint(
            id: UUID(),
            date: df.string(from: todayStart),
            equity: currentBalance,
            pnl: 0.0,
            pnl_pct: 0.0,
            deposits: max(0.0, netBetween),
            withdrawals: max(0.0, -netBetween),
            net_cash_flow: netBetween,
            daily_return: daily * 100.0,
            cumulative_twr: newCumulativeProp * 100.0
        )
        
        // Solo añadir punto de hoy si hoy es posterior al último punto histórico
        if todayStart > nyCal.startOfDay(for: lastPoint.timestamp) {
            // Hoy es posterior al último punto histórico, añadir punto de hoy
            individualTwrPoints.append(newPoint)
            print("📅 [iOS Perf] Added new today point (today > last point). Total points: \(individualTwrPoints.count)")
        } else if let idx = individualTwrPoints.firstIndex(where: { nyCal.isDate($0.timestamp, inSameDayAs: todayStart) }) {
            // Hoy es el mismo día que el último punto, actualizar solo si hay cambios significativos
            let existingPoint = individualTwrPoints[idx]
            let equityChange = abs(newPoint.equity - existingPoint.equity)
            let twrChange = abs(newPoint.cumulative_twr - existingPoint.cumulative_twr)
            
            if equityChange > 0.01 || twrChange > 0.001 { // Cambios significativos
                individualTwrPoints[idx] = newPoint
                print("📅 [iOS Perf] Updated existing today point at index \(idx) (significant changes: equity=\(equityChange), twr=\(twrChange))")
            } else {
                print("📅 [iOS Perf] No significant changes, keeping existing point (equity=\(equityChange), twr=\(twrChange))")
            }
        } else {
            print("📅 [iOS Perf] Today (\(df.string(from: todayStart))) is before last point (\(lastPoint.date)), skipping")
        }
    }
    
    private func getLabelStrideCount() -> Int {
        // Estrategia más agresiva para reducir etiquetas superpuestas
        let totalDataPoints = portfolioHistory.count
        
        // Si el ancho es menor a 400 puntos (orientación vertical) o hay muchos puntos de datos
        if chartWidth < 400 || totalDataPoints > 30 {
            // Para orientación vertical o muchos datos, usar un stride mucho mayor
            // Esto mostrará aproximadamente 3-4 etiquetas máximo
            return max(10, totalDataPoints / 3)
        } else {
            return 3
        }
    }
    
    private func getXAxisValues() -> [Date] {
        // Crear un array de fechas específicas para mostrar en el eje X
        guard !portfolioHistory.isEmpty else { return [] }
        
        let totalDataPoints = portfolioHistory.count
        let maxLabels = chartWidth < 400 ? 4 : 6 // Máximo 4 etiquetas en vertical, 6 en horizontal
        
        if totalDataPoints <= maxLabels {
            return portfolioHistory.map { $0.timestamp }
        }
        
        // Seleccionar fechas distribuidas uniformemente
        let step = totalDataPoints / maxLabels
        var selectedDates: [Date] = []
        
        for i in stride(from: 0, to: totalDataPoints, by: step) {
            selectedDates.append(portfolioHistory[i].timestamp)
        }
        
        // Asegurar que incluimos la última fecha
        if let lastDate = portfolioHistory.last?.timestamp,
           !selectedDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: lastDate) }) {
            selectedDates.append(lastDate)
        }
        
        return selectedDates
    }
    
    private func formatTimestampForTooltip(_ timestamp: Date) -> String {
        // Determinar si mostrar la hora basado en el período seleccionado
        switch selectedPeriod {
        case .oneDay:
            // Para 1 día, mostrar fecha y hora real de la API sin transformaciones
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .none
            
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            
            let dateString = dateFormatter.string(from: timestamp)
            let timeString = timeFormatter.string(from: timestamp)
            
            return "\(dateString) - \(timeString)"
        case .oneWeek, .oneMonth, .threeMonths, .oneYear, .all, .custom:
            // Para períodos largos, mostrar solo la fecha sin hora
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            return dateFormatter.string(from: timestamp)
        }
    }
    
    private func formatDateRange() -> String {
        guard let firstDate = portfolioHistory.first?.timestamp,
              let lastDate = portfolioHistory.last?.timestamp else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        
        let startString = formatter.string(from: firstDate)
        let endString = formatter.string(from: lastDate)
        
        return "\(startString) - \(endString)"
    }
    
    private func calculateCorrectChange(for dataPoint: PortfolioHistoryDataPoint) -> (amount: Double, percentage: Double) {
        // Si es el último punto (día de hoy), calcular usando equity actual vs penúltimo día de trading
        if let lastPoint = portfolioHistory.last, dataPoint.id == lastPoint.id {
            if let selectedAccount = selectedAccount,
               let currentBalance = accountManager.balances[selectedAccount] {
                let currentEquity = currentBalance.balance
                
                // Usar el penúltimo punto como referencia histórica (último día de trading real)
                let lastTradingDayEquity: Double
                if portfolioHistory.count >= 2 {
                    lastTradingDayEquity = portfolioHistory[portfolioHistory.count - 2].equity
                } else {
                    lastTradingDayEquity = lastPoint.equity
                }
                
                // Calcular cambio desde el último día de trading hasta ahora
                let change = currentEquity - lastTradingDayEquity
                let changePercentage = lastTradingDayEquity > 0 ? (change / lastTradingDayEquity) * 100 : 0
                
                return (change, changePercentage)
            }
        }
        
        // Para otros puntos, usar los valores calculados normalmente
        return (dataPoint.profitLoss, dataPoint.profitLossPct * 100)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Estados de carga y error
            if isLoading || (showTWR && !isSeriesReady) {
                VStack(spacing: 16) {
                    ProgressView("Loading...")
                        .scaleEffect(1.1)
                    
                    Text("Loading performance data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                    
                    Text("Error")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if portfolioHistory.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    
                    Text("No Data")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Performance data will appear here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                // Contenido principal con métricas y gráfico
                VStack(spacing: 16) {
                    // Tarjetas de métricas principales
                    VStack(spacing: 12) {
                        if let firstData = portfolioHistory.first,
                           let lastData = portfolioHistory.last {
                            
                            // Check if this is Total Accounts
                            let isTotalAccounts = account.name == "Total Accounts"
                            
                            if isTotalAccounts {
                                // Variables for Total Accounts cards
                                // For start value, use the calculated start balance from historical data
                                let start_total_accounts: Double = totalAccountsStartBalance
                                
                                // For current value, use the sum of real account balances
                                let current_total_accounts: Double = accountManager.realAccounts.compactMap { account in accountManager.balances[account.id]?.balance }.reduce(0, +)
                                let change_total_accounts: Double = current_total_accounts - start_total_accounts
                                
                                // Get profit/loss percentage from the last point of portfolio history
                                let profitLossPct = portfolioHistory.last?.profitLossPct ?? 0.0
                                
                                // New cards for Total Accounts
                                HStack(spacing: 12) {
                                    // With TWR ON, Balance equals first equity + net cash flows within visible range
                                    let startBalanceAdjusted_visible: Double = {
                                        if showTWR, let first = portfolioHistory.first?.timestamp, let last = portfolioHistory.last?.timestamp, let firstEquity = portfolioHistory.first?.equity {
                                            let visibleFlows = twrPoints.filter { $0.timestamp > first && $0.timestamp <= last }
                                            let totalNetCashFlow = visibleFlows.reduce(0.0) { $0 + $1.net_cash_flow }
                                            return firstEquity + totalNetCashFlow
                                        }
                                        return (showTWR ? start_total_accounts : (portfolioHistory.first?.equity ?? start_total_accounts))
                                    }()
                                    PerformanceMetricCard(
                                        title: showTWR ? "Balance" : "Start Value",
                                        value: startBalanceAdjusted_visible,
                                        isPositive: nil,
                                        icon: "arrow.up.circle"
                                    )
                                    
                                    PerformanceMetricCard(
                                        title: showTWR ? "Current Value" : "Current",
                                        value: showTWR ? (portfolioHistory.last?.equity ?? current_total_accounts) : current_total_accounts,
                                        isPositive: nil,
                                        icon: "dollarsign.circle"
                                    )
                                }
                                
                                HStack(spacing: 12) {
                                    if showTWR {
                                        // Net Change = Current - Balance, both scoped to visible equity range
                                        if let first = portfolioHistory.first?.timestamp, let last = portfolioHistory.last?.timestamp, let firstEquity = portfolioHistory.first?.equity, let lastEquity = portfolioHistory.last?.equity {
                                            let visibleFlows = twrPoints.filter { $0.timestamp > first && $0.timestamp <= last }
                                            let totalNetCashFlow = visibleFlows.reduce(0.0) { $0 + $1.net_cash_flow }
                                            let base = firstEquity + totalNetCashFlow
                                            let netChangeAmount = lastEquity - base
                                        PerformanceMetricCard(
                                            title: "Net Change",
                                            value: netChangeAmount,
                                            isPositive: netChangeAmount >= 0,
                                            percentage: nil,
                                            icon: netChangeAmount >= 0 ? "arrow.up.right.circle" : "arrow.down.right.circle"
                                        )
                                        }
                                    } else {
                                        PerformanceMetricCard(
                                            title: "Change",
                                            value: current_total_accounts - (portfolioHistory.first?.equity ?? start_total_accounts),
                                            isPositive: (current_total_accounts - (portfolioHistory.first?.equity ?? start_total_accounts)) >= 0,
                                            percentage: {
                                                let base = portfolioHistory.first?.equity ?? start_total_accounts
                                                let delta = current_total_accounts - base
                                                return base > 0 ? (delta / base) * 100 : (current_total_accounts > 0 ? 100.0 : 0.0)
                                            }(),
                                            icon: "arrow.up.right.circle"
                                        )
                                    }
                                    
                                    // Show Return % only when TWR is OFF
                                    if !showTWR {
                                        PerformanceMetricCard(
                                            title: "Return %",
                                            value: profitLossPct,
                                            isPositive: profitLossPct >= 0,
                                            percentage: nil,
                                            icon: "chart.line.uptrend.xyaxis",
                                            isPercentage: true
                                        )
                                    }
                                    
                                    if showTWR, let twrPct = twrPoints.last?.cumulative_twr {
                                        PerformanceMetricCard(
                                            title: "TWR Return %",
                                            value: twrPct,
                                            isPositive: twrPct >= 0,
                                            percentage: nil,
                                            icon: "chart.line.uptrend.xyaxis",
                                            isPercentage: true
                                        )
                                    }
                                }
                            } else {
                                // Valor inicial y final (en TWR el inicial se muestra como Balance = start + net cash flows)
                                HStack(spacing: 12) {
                                    let startTitle = showTWR ? "Balance" : "Start Value"
                                    let startValue = showTWR ? (firstData.equity + individualTwrPoints.reduce(0.0) { $0 + $1.net_cash_flow }) : firstData.equity
                                    PerformanceMetricCard(
                                        title: startTitle,
                                        value: startValue,
                                        isPositive: nil,
                                        icon: "arrow.up.circle"
                                    )
                                    
                                    PerformanceMetricCard(
                                        title: "Current Value",
                                        value: lastData.equity,
                                        isPositive: nil,
                                        icon: "dollarsign.circle"
                                    )
                                }
                                
                                if showTWR {
                                    HStack(spacing: 12) {
                                    let startBalanceAdjusted = firstData.equity + individualTwrPoints.reduce(0.0) { $0 + $1.net_cash_flow }
                                    let netChangeAmount = lastData.equity - startBalanceAdjusted
                                    PerformanceMetricCard(
                                        title: "Net Change",
                                        value: netChangeAmount,
                                        isPositive: netChangeAmount >= 0,
                                        percentage: nil,
                                        icon: netChangeAmount >= 0 ? "arrow.up.right.circle" : "arrow.down.right.circle"
                                    )
                                    if let twrPct = individualTwrPoints.last?.cumulative_twr {
                                        PerformanceMetricCard(
                                            title: "TWR Return %",
                                            value: twrPct,
                                            isPositive: twrPct >= 0,
                                            percentage: nil,
                                            icon: "chart.line.uptrend.xyaxis",
                                            isPercentage: true
                                        )
                                    }
                                    }
                                    
                                    // Show Return % only when TWR is OFF
                                    if !showTWR {
                                        let equityReturnPct = firstData.equity > 0 ? ((lastData.equity - firstData.equity) / firstData.equity) * 100 : 0
                                        PerformanceMetricCard(
                                            title: "Return %",
                                            value: equityReturnPct,
                                            isPositive: equityReturnPct >= 0,
                                            percentage: nil,
                                            icon: "chart.line.uptrend.xyaxis",
                                            isPercentage: true
                                        )
                                    }
                                } else {
                                    // Cambio total equity-based
                                    let startValue = firstData.equity
                                    let totalChange = lastData.equity - startValue
                                    let totalChangePct = (totalChange / startValue) * 100
                                    let isPositive = totalChange >= 0
                                    HStack(spacing: 12) {
                                        PerformanceMetricCard(
                                            title: "Total Change",
                                            value: totalChange,
                                            isPositive: isPositive,
                                            percentage: nil,
                                            icon: isPositive ? "arrow.up.right.circle" : "arrow.down.right.circle"
                                        )
                                        
                                        // Always show Return % for equity chart
                                        PerformanceMetricCard(
                                            title: "Return %",
                                            value: totalChangePct,
                                            isPositive: totalChangePct >= 0,
                                            percentage: nil,
                                            icon: "chart.line.uptrend.xyaxis",
                                            isPercentage: true
                                        )
                                    }
                                }
                            }
                        }
                    }
                    
                    // Gráfico compacto
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Performance Chart")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            // Indicador de tendencia (usa TWR cuando está activo)
                            HStack(spacing: 4) {
                                let isUp: Bool = {
                                    if showTWR {
                                        if account.name == "Total Accounts" {
                                            return (twrPoints.last?.cumulative_twr ?? 0) >= 0
                                        } else {
                                            return (individualTwrPoints.last?.cumulative_twr ?? 0) >= 0
                                        }
                                    } else {
                                        return (portfolioHistory.last?.profitLossPct ?? 0) >= 0
                                    }
                                }()
                                Circle()
                                    .fill(isUp ? .green : .red)
                                    .frame(width: 6, height: 6)
                                
                                Text(isUp ? "Positive" : "Negative")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(isUp ? .green : .red)
                            }
                        }
                        
                        // Gráfico optimizado para móvil
                        if showTWR {
                            if account.name == "Total Accounts" {
                                if isTwrLoading {
                                    ProgressView("Loading TWR...")
                                        .frame(height: 200)
                                } else if !self.twrPoints.isEmpty {
                                    twrCompactChart
                                } else {
                                    Text("No TWR data available")
                                        .foregroundColor(.secondary)
                                        .frame(height: 200)
                                }
                            } else {
                                if isIndividualTwrLoading {
                                    ProgressView("Loading TWR...")
                                        .frame(height: 200)
                                } else if !self.individualTwrPoints.isEmpty {
                                    twrChartView
                                } else {
                                    ProgressView("Loading TWR...")
                                        .frame(height: 200)
                                        .onAppear {
                                            if !isIndividualTwrLoading {
                                                isIndividualTwrLoading = true
                                                loadTWRForIndividualAccount()
                                            }
                                        }
                                }
                            }
                        } else {
                            compactChartView
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ColorCompatibility.controlBackground())
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100) // Espacio para el TabView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(_onChangeHooks)
    }
    
    // Gráfico compacto optimizado para móvil
    private var compactChartView: some View {
        // For Total Accounts, use equity sum (same as individual accounts)
        // For individual accounts, use equity (balance)
        let isTotalAccounts = account.name == "Total Accounts"
        
        let chartData: [Double]
        let chartLabel: String
        
        if isTotalAccounts {
            // Use equity sum for Total Accounts (same as individual accounts)
            chartData = portfolioHistory.map { $0.equity }
            chartLabel = "Equity"
        } else {
            // Use equity data for individual accounts
            chartData = portfolioHistory.map { $0.equity }
            chartLabel = "Equity"
        }
        
        let minValue = chartData.min() ?? 0
        let maxValue = chartData.max() ?? 0
        let padding = (maxValue - minValue) * 0.1
        let baselineValue = minValue - padding
        
        return ZStack {
            Chart(portfolioHistory) { dataPoint in
                // Línea principal del gráfico
                LineMark(
                    x: .value("Date", dataPoint.timestamp),
                    y: .value(chartLabel, dataPoint.equity)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
                
                // Área del gráfico con gradiente sutil
                AreaMark(
                    x: .value("Date", dataPoint.timestamp),
                    yStart: .value("Base", baselineValue),
                    yEnd: .value(chartLabel, dataPoint.equity)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.3),
                            Color.blue.opacity(0.1),
                            Color.blue.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                // Punto blanco indicando la posición seleccionada (igual que en Comparisión)
                if isHovering, let selectedPoint = selectedDataPoint {
                    PointMark(
                        x: .value("Date", selectedPoint.timestamp),
                        y: .value(chartLabel, selectedPoint.equity)
                    )
                    .foregroundStyle(.white)
                    .symbolSize(40)
                    .symbol(.circle)
                    .opacity(0.9)
                }
            }
            .frame(height: 200) // Altura fija para móvil
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            chartWidth = geometry.size.width
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            chartWidth = newWidth
                        }
                }
            )
            .chartYScale(domain: (minValue - padding)...(maxValue + padding))
            .chartXAxis {
                AxisMarks(values: getXAxisValues()) { value in
                    AxisValueLabel(format: .dateTime.month().day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text("$\(EuropeanNumberFormatter.shared.format(doubleValue, fractionDigits: 0))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
                                    // Coordenada X dentro del área de plot
                                    let xInPlot = value.location.x - plotFrame.origin.x
                                    guard xInPlot >= 0, xInPlot <= plotFrame.size.width else { return }
                                    // Mapear X a fecha usando el proxy (selección precisa)
                                    if let date: Date = proxy.value(atX: xInPlot) {
                                        // Encontrar el punto más cercano por timestamp
                                        if let nearestIndex = portfolioHistory.enumerated().min(by: { a, b in
                                            abs(a.element.timestamp.timeIntervalSince(date)) < abs(b.element.timestamp.timeIntervalSince(date))
                                        })?.offset {
                                            let data = portfolioHistory[nearestIndex]
                                            selectedDataPoint = data
                                            // Posición del tooltip, limitada al área del gráfico
                                            let clampedX = min(max(value.location.x, plotFrame.minX), plotFrame.maxX)
                                            hoverLocation = CGPoint(
                                                x: clampedX,
                                                y: max(value.location.y, 5)
                                            )
                                            isHovering = true
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isHovering = false
                                        selectedDataPoint = nil
                                    }
                                }
                        )
                }
            }
            
            // Tooltip overlay
            if isHovering, let selectedPoint = selectedDataPoint {
                TooltipView(
                    isVisible: isHovering,
                    position: hoverLocation,
                    maxWidth: 250
                ) {
                    let _ = account.name == "Total Accounts"
                    let (changeAmount, changePercentage) = calculateCorrectChange(for: selectedPoint)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(formatTimestampForTooltip(selectedPoint.timestamp))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("$\(String(format: "%.2f", selectedPoint.equity))")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        HStack {
                            Text("Change:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("$\(String(format: "%.2f", changeAmount))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(changeAmount >= 0 ? .green : .red)
                            
                            Text("(\(String(format: "%.2f", changePercentage))%)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(changeAmount >= 0 ? .green : .red)
                        }
                    }
                }
            }
            
            // Date range overlay positioned absolutely within the chart
            if !portfolioHistory.isEmpty {
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
    }
    
    // TWR chart for Total Accounts (iOS) with same styling as macOS TWR
    private var twrCompactChart: some View {
        // twrPoints.cumulative_twr ya está en porcentaje
        let values = self.twrPoints.map { $0.cumulative_twr }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let padding = (maxValue - minValue) * 0.1
        let baselineValue = minValue - padding
        return ZStack {
            Chart(self.twrPoints) { p in
                AreaMark(
                    x: .value("Date", p.timestamp),
                    yStart: .value("Base", baselineValue),
                    yEnd: .value("TWR %", p.cumulative_twr)
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
                    x: .value("Date", p.timestamp),
                    y: .value("TWR %", p.cumulative_twr)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)

                // White highlight on selected point
                PointMark(
                    x: .value("Date", p.timestamp),
                    y: .value("TWR %", p.cumulative_twr)
                )
                .foregroundStyle(.white)
                .symbol(.circle)
                .symbolSize(selectedTwrPoint?.id == p.id ? 40 : 0)
                .opacity(selectedTwrPoint?.id == p.id ? 0.9 : 0)
            }
            .frame(height: 200)
            .chartYScale(domain: (minValue - padding)...(maxValue + padding))
            .chartXAxis {
                AxisMarks(values: getXAxisValues()) { value in
                    AxisValueLabel(format: .dateTime.month().day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(String(format: "%.2f", v))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
                                        if let idx = twrPoints.enumerated().min(by: { a, b in
                                            abs(a.element.timestamp.timeIntervalSince(date)) < abs(b.element.timestamp.timeIntervalSince(date))
                                        })?.offset {
                                            selectedTwrPoint = twrPoints[idx]
                                            let clampedX = min(max(value.location.x, plotFrame.minX), plotFrame.maxX)
                                            twrHoverLocation = CGPoint(x: clampedX, y: max(value.location.y, 5))
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedTwrPoint = nil
                                    }
                                }
                        )
                }
            }
            if let p = selectedTwrPoint {
                TooltipView(
                    isVisible: true,
                    position: twrHoverLocation,
                    maxWidth: 240
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(formatTimestampForTooltip(p.timestamp))
                            .font(.caption)
                            .fontWeight(.semibold)
                        HStack(spacing: 6) {
                            Text("Daily:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.2f", p.daily_return))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(p.daily_return >= 0 ? .green : .red)
                        }
                        HStack(spacing: 6) {
                            Text("Cumulative:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.2f", p.cumulative_twr))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(p.cumulative_twr >= 0 ? .green : .red)
                        }
                    }
                }
            }
        }
        // Triggers se gestionan de forma centralizada en _onChangeHooks
    }
    
    private var twrChartView: some View {
        let values = individualTwrPoints.map { $0.cumulative_twr }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let padding = (maxValue - minValue) * 0.1
        let baselineValue = minValue - padding
        
        return ZStack {
            Chart(individualTwrPoints) { p in
                AreaMark(
                    x: .value("Date", p.timestamp),
                    yStart: .value("Base", baselineValue),
                    yEnd: .value("TWR %", p.cumulative_twr)
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
                    x: .value("Date", p.timestamp),
                    y: .value("TWR %", p.cumulative_twr)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
                
                // White highlight on selected point
                PointMark(
                    x: .value("Date", p.timestamp),
                    y: .value("TWR %", p.cumulative_twr)
                )
                .foregroundStyle(.white)
                .symbol(.circle)
                .symbolSize(selectedTwrPoint?.id == p.id ? 40 : 0)
                .opacity(selectedTwrPoint?.id == p.id ? 0.9 : 0)
            }
            .frame(height: 200)
            .chartYScale(domain: (minValue - padding)...(maxValue + padding))
            .chartXAxis {
                AxisMarks(values: getXAxisValues()) { value in
                    AxisValueLabel(format: .dateTime.month().day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(String(format: "%.2f", v))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
                                        if let idx = individualTwrPoints.enumerated().min(by: { a, b in
                                            abs(a.element.timestamp.timeIntervalSince(date)) < abs(b.element.timestamp.timeIntervalSince(date))
                                        })?.offset {
                                            selectedTwrPoint = individualTwrPoints[idx]
                                            let clampedX = min(max(value.location.x, plotFrame.minX), plotFrame.maxX)
                                            twrHoverLocation = CGPoint(x: clampedX, y: max(value.location.y, 5))
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedTwrPoint = nil
                                    }
                                }
                        )
                }
            }
            if let p = selectedTwrPoint {
                TooltipView(
                    isVisible: true,
                    position: twrHoverLocation,
                    maxWidth: 240
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(formatTimestampForTooltip(p.timestamp))
                            .font(.caption)
                            .fontWeight(.semibold)
                        HStack(spacing: 6) {
                            Text("Daily:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.2f", p.daily_return))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(p.daily_return >= 0 ? .green : .red)
                        }
                        HStack(spacing: 6) {
                            Text("Cumulative:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.2f", p.cumulative_twr))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(p.cumulative_twr >= 0 ? .green : .red)
                        }
                    }
                }
            }
        }
    }

    // Centralized change hooks to mirror macOS behavior
    @ViewBuilder
    private var _onChangeHooks: some View {
        EmptyView()
            .onAppear {
                if showTWR { loadTWR() }
            }
            .onChange(of: showTWR) { _, isOn in
                if isOn {
                    isSeriesReady = false
                    loadTWR()
                } else {
                    twrPoints = []
                    individualTwrPoints = []
                    twrError = nil
                    individualTwrError = nil
                    isTwrLoading = false
                    isIndividualTwrLoading = false
                    // Equity path does not use TWR gating
                    isSeriesReady = true
                }
            }
            .onChange(of: selectedPeriod) { _, _ in
                if showTWR { loadTWR() }
            }
            .onChange(of: selectedTimeframe) { _, _ in
                if showTWR { loadTWR() }
            }
            .onChange(of: customStartDate) { _, _ in
                if showTWR && selectedPeriod == .custom { loadTWR() }
            }
            .onChange(of: customEndDate) { _, _ in
                if showTWR && selectedPeriod == .custom { loadTWR() }
            }
            .onChange(of: selectedAccount) { _, _ in
                if showTWR { loadTWR() }
            }
    }
    
    // MARK: - Helper Functions
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatValue(_ value: Double, isTotalAccounts: Bool) -> String {
        if isTotalAccounts {
            return "\(String(format: "%.2f", value))%"
        } else {
            return "$\(EuropeanNumberFormatter.shared.format(value))"
        }
    }
}

struct PerformanceMetricCard: View {
    let title: String
    let value: Double
    let isPositive: Bool?
    let percentage: Double?
    let icon: String
    let isPercentage: Bool
    
    init(title: String, value: Double, isPositive: Bool?, percentage: Double? = nil, icon: String = "circle", isPercentage: Bool = false) {
        self.title = title
        self.value = value
        self.isPositive = isPositive
        self.percentage = percentage
        self.icon = icon
        self.isPercentage = isPercentage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header con icono y título
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accentColor)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(accentColor.opacity(0.1))
                    )
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Valor principal
            HStack(alignment: .bottom, spacing: 4) {
                if isPercentage {
                    Text("\(EuropeanNumberFormatter.shared.format(value, fractionDigits: 2))%")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(valueColor)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 2) {
                        Text("$")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(valueColor)
                        
                        Text(EuropeanNumberFormatter.shared.format(value))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                
                if let percentage = percentage, !isPercentage {
                    Text("(\(EuropeanNumberFormatter.shared.format(percentage, fractionDigits: 1))%)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(valueColor.opacity(0.8))
                }
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: shadowColor, radius: 2, x: 0, y: 1)
        )
    }
    
    private var valueColor: Color {
        if let isPositive = isPositive {
            return isPositive ? .green : .red
        }
        return .primary
    }
    
    private var accentColor: Color {
        if let isPositive = isPositive {
            return isPositive ? .green : .red
        }
        return .blue
    }
    
    private var backgroundColor: Color {
        ColorCompatibility.controlBackground()
    }
    
    private var borderColor: Color {
        if let isPositive = isPositive {
            return isPositive ? .green.opacity(0.2) : .red.opacity(0.2)
        }
        return .clear
    }
    
    private var shadowColor: Color {
        if let isPositive = isPositive {
            return isPositive ? .green.opacity(0.08) : .red.opacity(0.08)
        }
        return .black.opacity(0.03)
    }
}


#Preview {
    PerformanceView(accountManager: AccountManager(), onNavigateToComparison: nil)
}