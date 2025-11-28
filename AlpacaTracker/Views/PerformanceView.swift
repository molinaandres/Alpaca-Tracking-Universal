import SwiftUI
import Foundation
import Charts

final class TWREmbeddedRunner {
    static let script: String = """
#!/bin/bash
export TZ=America/New_York
API_KEY="${API_KEY:-}"; SECRET_KEY="${SECRET_KEY:-}"; BASE_URL="https://api.alpaca.markets"; START_DATE="${START_DATE:-}"; END_DATE="${END_DATE:-}"; TIMEFRAME="${TIMEFRAME:-1D}"; EXTENDED_HOURS="${EXTENDED_HOURS:-false}";
if [ -z "$API_KEY" ] || [ -z "$SECRET_KEY" ]; then echo '{"error":"missing_keys"}'; exit 1; fi
if ! command -v jq >/dev/null; then echo '{"error":"missing_jq"}'; exit 1; fi
if ! command -v bc >/dev/null; then echo '{"error":"missing_bc"}'; exit 1; fi
convert_ts(){ date -r "$1" +"%Y-%m-%d" 2>/dev/null || echo "N/A"; }
is_zero(){ v="$1"; [ -z "$v" ] || [ "$v" = 0 ] || [ "$v" = 0.0 ] || [ "$v" = 0.00 ]; }
calc_ret(){ pe="$1"; ce="$2"; cf="$3"; if is_zero "$pe"; then echo 0.0; return; fi; ae="$ce"; if ! is_zero "$cf"; then ae=$(echo "$ce - $cf" | bc -l 2>/dev/null || echo "$ce"); fi; echo "($ae - $pe)/$pe" | bc -l 2>/dev/null || echo 0.0; }
ph_url="$BASE_URL/v2/account/portfolio/history"; if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then ph_url="$ph_url?start=$START_DATE&end=$END_DATE&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"; else ph_url="$ph_url?period=1M&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"; fi
PH=$(curl -s "$ph_url" -H "APCA-API-KEY-ID: $API_KEY" -H "APCA-API-SECRET-KEY: $SECRET_KEY" -H "Accept: application/json"); if [ -z "$PH" ] || [ "$PH" = null ]; then echo '{"error":"no_portfolio_data"}'; exit 0; fi
ACT=""; for typ in CSD CSW; do tok=""; pc=0; while true; do pc=$((pc+1)); url="$BASE_URL/v2/account/activities/$typ?after=$START_DATE&until=$END_DATE&page_size=100&direction=asc"; [ -n "$tok" ] && url="$url&page_token=$tok"; R=$(curl -s "$url" -H "APCA-API-KEY-ID: $API_KEY" -H "APCA-API-SECRET-KEY: $SECRET_KEY" -H "Accept: application/json"); t=$(echo "$R"|jq 'type'); if [ "$t" = '"array"' ]; then A=$(echo "$R"|jq -r '.[]'); [ -n "$A" ] && ACT="$ACT"$'\n'"$A"; c=$(echo "$R"|jq 'length'); [ "$c" -lt 100 ] && break; tok=$(echo "$R"|jq -r '.[-1].id'); [ -z "$tok" ] || [ "$tok" = null ] && break; else A=$(echo "$R"|jq -r '.activities[]?'); [ -n "$A" ] && ACT="$ACT"$'\n'"$A"; tok=$(echo "$R"|jq -r '.next_page_token'); [ -z "$tok" ] || [ "$tok" = null ] && break; fi; [ "$pc" -gt 1000 ] && break; done; done
prev=""; twr=1.0; started=false
TS=($(echo "$PH"|jq -r '.timestamp[]')); EQ=($(echo "$PH"|jq -r '.equity[]')); PNL=($(echo "$PH"|jq -r '.profit_loss[]')); PPC=($(echo "$PH"|jq -r '.profit_loss_pct[]'))
echo '['; first=1; for i in "${!TS[@]}"; do ts="${TS[$i]}"; eq="${EQ[$i]}"; pnl="${PNL[$i]}"; ppc="${PPC[$i]}"; d=$(convert_ts "$ts"); depT=0; wdrT=0; depY=0; wdrY=0; if [ -n "$ACT" ]; then day=$(echo "$ACT"|jq -r --arg d "$d" 'select(.date==$d)'); [ -n "$day" ] && depT=$(echo "$day"|jq -r 'select(.activity_type=="CSD")|.net_amount'|awk '{s+=$1} END{print s+0}'); [ -n "$day" ] && wdrT=$(echo "$day"|jq -r 'select(.activity_type=="CSW")|.net_amount'|awk '{s+=$1} END{print s+0}'); fi
        if [ -n "$ACT" ] && [ "$i" -gt 0 ]; then pts="${TS[$((i-1))]}"; pd=$(convert_ts "$pts"); pn=$(date -j -f "%Y-%m-%d" "$pd" "+%Y%m%d" 2>/dev/null||echo 0); cn=$(date -j -f "%Y-%m-%d" "$d" "+%Y%m%d" 2>/dev/null||echo 0); prevA=$(echo "$ACT"|jq -r --arg pn "$pn" --arg cn "$cn" 'select(.date!=null) | select((.date|gsub("-";"")|tonumber) > ($pn|tonumber) and (.date|gsub("-";"")|tonumber) <= ($cn|tonumber))'); [ -n "$prevA" ] && depY=$(echo "$prevA"|jq -r 'select(.activity_type=="CSD")|.net_amount'|awk '{s+=$1} END{print s+0}'); [ -n "$prevA" ] && withdrawalsY=$(echo "$prevA"|jq -r 'select(.activity_type=="CSW")|.net_amount'|awk '{s+=$1} END{print s+0}'); wdrY=${withdrawalsY:-0}; fi
ncT=$(echo "$depT - $wdrT"|bc -l 2>/dev/null||echo 0); ncY=$(echo "$depY - $wdrY"|bc -l 2>/dev/null||echo 0); dr=0.0; if [ -z "$prev" ] || is_zero "$prev"; then dr=0.0; if ! is_zero "$eq"; then twr=1.0; started=true; fi; else if [ "$started" = true ]; then aeq=$(echo "$eq - $ncY"|bc -l 2>/dev/null||echo 0); # Guard: if adjusted equity <= 0, treat as no return for this interval
 if [ "$(echo "$aeq <= 0" | bc -l)" -eq 1 ]; then dr=0.0; else dr=$(calc_ret "$prev" "$eq" "$ncY"); fi; twr=$(echo "$twr*(1+$dr)"|bc -l 2>/dev/null||echo "$twr"); fi; fi; [ $first -eq 1 ] || echo ','; first=0; printf '{"date":"%s","equity":%.4f,"pnl":%.4f,"pnl_pct":%.6f,"deposits":%.4f,"withdrawals":%.4f,"net_cash_flow":%.4f,"daily_return":%.8f,"cumulative_twr":%.8f}' "$d" "$eq" "$pnl" "$ppc" "$depT" "$wdrT" "$ncT" "$(echo "$dr"|bc -l 2>/dev/null||echo 0.0)" "$(echo "($twr-1)"|bc -l 2>/dev/null||echo 0.0)"; prev="$eq"; done; echo ']'
"""

    static func run(apiKey: String, secretKey: String, startDate: Date, endDate: Date, timeframe: PortfolioHistoryTimeframe, extendedHours: Bool) throws -> Data {
        let fm = FileManager.default
        let tmp = NSTemporaryDirectory()
        let path = (tmp as NSString).appendingPathComponent("twr_embed.sh")
        if fm.fileExists(atPath: path) { try? fm.removeItem(atPath: path) }
        try Self.script.data(using: .utf8)!.write(to: URL(fileURLWithPath: path), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [path, "json"]
        var env = ProcessInfo.processInfo.environment
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York")
        env["API_KEY"] = apiKey; env["SECRET_KEY"] = secretKey; env["START_DATE"] = f.string(from: startDate); env["END_DATE"] = f.string(from: endDate); env["TIMEFRAME"] = (timeframe == .oneMinute) ? "1Min" : "1D"; env["EXTENDED_HOURS"] = extendedHours ? "true" : "false"; p.environment = env
        let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err; try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "error"; throw NSError(domain: "TWR", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: e]) }
        return out.fileHandleForReading.readDataToEndOfFile()
    }
}

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
    @State private var showTWR: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if accountManager.accounts.isEmpty {
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
                    // Lista de cuentas y rendimiento
                    HStack(spacing: 0) {
                        // Sidebar con cuentas
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
                            // Leave bottom space for the gear button overlay in main ContentView
                            .padding(.bottom, 56)
                        }
                        .frame(width: min(220, geometry.size.width * 0.25))
                        
                        Divider()
                        
                        // Vista de rendimiento
                        if let selectedAccount = selectedAccount,
                           let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                            PerformanceDetailView(
                                account: account,
                                accountManager: accountManager,
                                onLoadPortfolioHistory: loadPortfolioHistory,
                                onNavigateToComparison: onNavigateToComparison,
                                showTWR: $showTWR,
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
                                totalAccountsStartBalance: $totalAccountsStartBalance
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                
                                Text("Select an account")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("Choose an account from the list to view its performance")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // Restore per-account TWR toggle state
            if let selectedAccount = selectedAccount,
               let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                showTWR = SettingsManager.shared.showTWR(for: account.id.uuidString)
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
        let dateRange = selectedPeriod.customDateRange(for: account)
        let startDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
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
        // Additionally disable 1Day timeframe when period is 1Day
        if selectedPeriod == .oneDay && timeframe == .oneDay { return false }
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
            _ = calendar.startOfDay(for: today)
            
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
    @Binding var showTWR: Bool
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
    @State private var twrPoints: [TWRChartPoint] = []
    @State private var isTwrLoading: Bool = false
    @State private var twrError: String?
    @State private var selectedTwrPoint: TWRChartPoint?
    
    // Defer rendering charts and metrics until series is fully ready (today point + clamp + rebase)
    @State private var isSeriesReady: Bool = false

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
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header con información de la cuenta
                VStack(spacing: 16) {
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
                        
                        // Toggle TWR
                        Toggle(isOn: $showTWR) {
                            Text("TWR")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .toggleStyle(SwitchToggleStyle())
                        .frame(width: 90)
                        .onChange(of: showTWR) { _, newValue in
                            if newValue {
                                isSeriesReady = false
                                loadTWR()
                            } else {
                                twrPoints = []
                                twrError = nil
                                isTwrLoading = false
                                isSeriesReady = true
                            }
                            // Persist per-account toggle state
                            if let selectedAccount = selectedAccount,
                               let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) {
                                SettingsManager.shared.setShowTWR(newValue, for: account.id.uuidString)
                            }
                        }
                        
                        VStack(alignment: .trailing) {
                            if let lastUpdate = accountManager.lastUpdateTime {
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
                            
                            // Botón de comparación rápida
                            Button(action: {
                                onNavigateToComparison?()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.caption)
                                    Text("Comparar")
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
                    
                    // Selectores de período, fechas personalizadas y granularidad en una sola línea
                    HStack {
                        // Selector de período
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Period")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 0) {
                                ForEach(Array(PortfolioHistoryPeriod.allCases.enumerated()), id: \.element) { index, period in
                                    // Disable 1Day when the selected account is Total Accounts
                                    let isTotalAccounts = account.name == "Total Accounts"
                                    let isDisabled = isTotalAccounts && period == .oneDay
                                    Button(action: {
                        selectedPeriod = period
                        // Seleccionar la granularidad de menor resolución (mayor detalle) por defecto
                        if let lastTimeframe = period.validTimeframes.last {
                            selectedTimeframe = lastTimeframe
                        }
                    }) {
                                        Text(period.displayName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(selectedPeriod == period ? .white : .primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .frame(minWidth: periodWidth(period), maxWidth: periodWidth(period))
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(selectedPeriod == period ? Color.accentColor : Color.clear)
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(isDisabled)
                                    
                                    if index < PortfolioHistoryPeriod.allCases.count - 1 {
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
                                        onLoadPortfolioHistory()
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
                                    let isValid = isTimeframeValid(timeframe)
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
                
                Divider()
                
                // Contenido principal
        if isLoading || (showTWR && !isSeriesReady) {
                    VStack(spacing: 16) {
                        ProgressView("Loading performance data...")
                            .scaleEffect(1.2)
                        
                        Text(showTWR ? "Calculando TWR (paginando actividades CSD/CSW)" : "Obteniendo historial del portafolio")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = showTWR ? twrError : errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        
                        Text("Error loading data")
                            .font(.headline)
                .foregroundColor(.red)
                        
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if (!showTWR && portfolioHistory.isEmpty) || (showTWR && twrPoints.isEmpty) {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No performance data")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Performance data will appear here when available")
                            .font(.subheadline)
                .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 20) {
                performanceSummaryView(selectedAccount: selectedAccount, totalAccountsStartBalance: totalAccountsStartBalance)
                if showTWR {
                    twrChartView
                } else {
                    equityChartView
                }
            }
            .padding()
        }
    }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(_onChangeHooks) // Ensure TWR recalculates when period/timeframe/dates/account change
        }
    }

    private func loadTWR() {
        guard showTWR else { return }
        isSeriesReady = false
        guard let selectedAccount = selectedAccount,
              let account = accountManager.allAccounts.first(where: { $0.id == selectedAccount }) else {
            print("❌ TWR: No account selected")
            return
        }

        isTwrLoading = true
        twrError = nil

        // Obtener credenciales
        let creds = account.getDecryptedCredentials()
        // Rango de fechas
        let dateRange = selectedPeriod.customDateRange(for: account)
        let startDate = selectedPeriod == .custom ? customStartDate : dateRange.startDate
        let endDate = selectedPeriod == .custom ? customEndDate : dateRange.endDate

        // Logs reduced: metrics will be printed after series is assembled

        if account.name == "Total Accounts" {
            accountManager.getTotalAccountsTWR(startDate: startDate, endDate: endDate, timeframe: selectedTimeframe) { result in
                switch result {
                case .success(let points):
                    // Map proportion [0.0..] to percentage for UI (×100)
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
                    // Align range and rebase before rendering
                    self.clampTwrToEquityRange()
                    self.rebaseTwrFromVisibleStart()
                    self.isTwrLoading = false
                    self.isSeriesReady = true
                case .failure(let err):
                    self.twrError = err.localizedDescription
                    self.twrPoints = []
                    self.isTwrLoading = false
                    self.isSeriesReady = true
                }
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try TWREmbeddedRunner.run(
                    apiKey: creds.apiKey,
                    secretKey: creds.secretKey,
                    startDate: startDate,
                    endDate: endDate,
                    timeframe: selectedTimeframe,
                    extendedHours: true
                )
                // Raw output preview suppressed
                // Detect error envelope from script
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = obj["error"] as? String {
                    DispatchQueue.main.async {
                        self.twrError = "TWR script error: \(err)"
                        self.twrPoints = []
                        self.isTwrLoading = false
                    }
                    return
                }
                var mapped: [TWRChartPoint] = []
                do {
                    let decoded = try JSONDecoder().decode([TWRChartPoint].self, from: data)
                    mapped = decoded.map { p in
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
                } catch {
                    // Fallback: permissive parse to avoid hard decode failures
                    if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        mapped = arr.compactMap { dict in
                            guard let date = dict["date"] as? String else { return nil }
                            let equity = (dict["equity"] as? Double) ?? Double(dict["equity"] as? String ?? "") ?? 0
                            let pnl = (dict["pnl"] as? Double) ?? Double(dict["pnl"] as? String ?? "") ?? 0
                            let pnl_pct = (dict["pnl_pct"] as? Double) ?? Double(dict["pnl_pct"] as? String ?? "") ?? 0
                            let deposits = (dict["deposits"] as? Double) ?? Double(dict["deposits"] as? String ?? "") ?? 0
                            let withdrawals = (dict["withdrawals"] as? Double) ?? Double(dict["withdrawals"] as? String ?? "") ?? 0
                            let net_cash_flow = (dict["net_cash_flow"] as? Double) ?? Double(dict["net_cash_flow"] as? String ?? "") ?? 0
                            let daily_return = ((dict["daily_return"] as? Double) ?? Double(dict["daily_return"] as? String ?? "") ?? 0) * 100.0
                            let cumulative_twr = ((dict["cumulative_twr"] as? Double) ?? Double(dict["cumulative_twr"] as? String ?? "") ?? 0) * 100.0
                            return TWRChartPoint(id: UUID(), date: date, equity: equity, pnl: pnl, pnl_pct: pnl_pct, deposits: deposits, withdrawals: withdrawals, net_cash_flow: net_cash_flow, daily_return: daily_return, cumulative_twr: cumulative_twr)
                        }
                    } else {
                        throw error
                    }
                }
                DispatchQueue.main.async {
                    self.twrPoints = mapped.sorted { $0.timestamp < $1.timestamp }
                    self.isTwrLoading = false
                    print("📊 [macOS Perf] TWR loaded: count=\(self.twrPoints.count) first=\(self.twrPoints.first?.timestamp.debugDescription ?? "nil") last=\(self.twrPoints.last?.timestamp.debugDescription ?? "nil")")
                    // Detailed series log before finalization
                    self.logTwrSeriesDetails(tag: "after-load")
                    // Defer clamping/rebase and readiness to append-today completion to avoid double render
                    self.appendTodayTwrPointIfNeeded(account: account, creds: creds, startDate: startDate, endDate: endDate)
                }
            } catch {
                DispatchQueue.main.async {
                    self.twrError = error.localizedDescription
                    self.twrPoints = []
                    self.isTwrLoading = false
                }
            }
        }
        }
    }

    private func appendTodayTwrPointIfNeeded(account: AlpacaAccount, creds: (apiKey: String, secretKey: String), startDate: Date, endDate: Date) {
        // Only for ranges that include today and if we have a last historical point
        guard let last = twrPoints.last else { return }
        let cal = Calendar.current
        let today = Date()
        guard startDate <= today && endDate >= cal.startOfDay(for: today) else { return }
        if cal.isDate(last.timestamp, inSameDayAs: today) { return } // already has today
        guard let balance = accountManager.balances[account.id]?.balance else { return }
        // Fetch cash flows from (lastDay, today]
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(identifier: "America/New_York")
        let api = AlpacaAPIService(apiKey: creds.apiKey, secretKey: creds.secretKey, isLiveTrading: account.isLiveTrading)
        api.getCashFlowActivities(startDate: last.timestamp, endDate: today) { result in
            DispatchQueue.main.async {
                let lastDayNum = Int(df.string(from: last.timestamp).replacingOccurrences(of: "-", with: "")) ?? 0
                let todayNum = Int(df.string(from: today).replacingOccurrences(of: "-", with: "")) ?? 0
                var netBetween = 0.0
                var debugActs: [(String, String, Double)] = [] // (date, type, amount)
                if case .success(let acts) = result {
                    for a in acts {
                        guard let ds = a.date else { continue }
                        let n = Int(ds.replacingOccurrences(of: "-", with: "")) ?? 0
                        if n > lastDayNum && n <= todayNum {
                            let amt = Double(a.netAmount ?? "0") ?? 0.0
                            let signed = (a.activityType == "CSD") ? amt : (a.activityType == "CSW" ? -amt : 0.0)
                            netBetween += signed
                            debugActs.append((ds, a.activityType, signed))
                        }
                    }
                }
                // Compute daily return using adjusted equity
                let prevEquity = last.equity
                let adjusted = balance - netBetween
                let daily = prevEquity == 0 ? 0.0 : (adjusted / prevEquity) - 1.0
                let cumulativeProp = (last.cumulative_twr / 100.0) * (1.0 + daily)
                let newPoint = TWRChartPoint(
                    id: UUID(),
                    date: df.string(from: today),
                    equity: balance,
                    pnl: 0.0,
                    pnl_pct: 0.0,
                    deposits: max(0.0, netBetween),
                    withdrawals: max(0.0, -netBetween),
                    net_cash_flow: netBetween,
                    daily_return: daily * 100.0,
                    cumulative_twr: cumulativeProp * 100.0
                )
                // Append or update today's point with most recent data
                if let lastTs = self.twrPoints.last?.timestamp, today > lastTs {
                    let calendar = Calendar.current
                    let todayPointIndex = self.twrPoints.firstIndex { point in
                        calendar.isDate(point.timestamp, inSameDayAs: today)
                    }
                    
                    if let existingIndex = todayPointIndex {
                        // Update existing today's point with fresh data
                        self.twrPoints[existingIndex] = newPoint
                        print("📅 [macOS Perf] Updated today's TWR point with fresh data: \(today)")
                    } else {
                        // Add new today's point
                        self.twrPoints.append(newPoint)
                        print("📅 [macOS Perf] Added today's TWR point: \(today)")
                    }
                    
                    // Finalize series before first render: clamp + rebase + metrics then mark ready
                    self.clampTwrToEquityRange()
                    self.rebaseTwrFromVisibleStart()
                    self.logTwrSeriesDetails(tag: "final-series")
                    self.logTwrVsEquityMetrics()
                    self.isSeriesReady = true
                }
            }
        }
    }

    private func clampTwrToEquityRange() {
        guard let firstEquity = portfolioHistory.first?.timestamp,
              let lastEquity = portfolioHistory.last?.timestamp else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: firstEquity)
        // include last equity day fully
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastEquity)) ?? lastEquity
        twrPoints = twrPoints.filter { p in
            p.timestamp >= start && p.timestamp < end
        }
        
    }

    private func rebaseTwrFromVisibleStart() {
        guard !twrPoints.isEmpty else { return }
        var cumulative: Double = 1.0
        for i in 0..<twrPoints.count {
            var p = twrPoints[i]
            if i == 0 {
                // first visible point: set cumulative to 0%
                p.cumulative_twr = 0.0
                cumulative = 1.0
            } else {
                let dailyProp = (p.daily_return / 100.0)
                cumulative *= (1.0 + dailyProp)
                p.cumulative_twr = (cumulative - 1.0) * 100.0
            }
            twrPoints[i] = p
        }
        
    }

    // Detailed per-point diagnostics to trace cash flow discounting and returns
    private func logTwrSeriesDetails(tag: String) { }

    private func logTwrVsEquityMetrics() { }

    // Cargar TWR cuando cambie el toggle o el rango/periodo
    @ViewBuilder
    private var _onChangeHooks: some View {
        EmptyView()
            .onAppear {
                if showTWR { loadTWR() }
            }
            .onChange(of: showTWR) { _, newValue in
                if newValue { loadTWR() }
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
    
    @ViewBuilder
    private func performanceSummaryView(selectedAccount: UUID?, totalAccountsStartBalance: Double) -> some View {
        let isTotalAccounts = account.name == "Total Accounts"
        
        // Variables for Total Accounts cards
        // Raw aggregated start balance
        let start_total_accounts_raw: Double = isTotalAccounts ? totalAccountsStartBalance : 0.0
        
        // For current value, use the sum of real account balances
        let current_total_accounts: Double = isTotalAccounts ? accountManager.realAccounts.compactMap { account in accountManager.balances[account.id]?.balance }.reduce(0, +) : 0.0
        
        // Align Start Value with first chart equity when TWR is OFF so it matches the tooltip
        let start_total_accounts_display: Double = {
            if !showTWR, let firstEquity = portfolioHistory.first?.equity { return firstEquity }
            return start_total_accounts_raw
        }()
        let change_total_accounts: Double = current_total_accounts - start_total_accounts_display
        
        
        HStack(spacing: 16) {
        if isTotalAccounts {
            // Get weighted return from the last point of portfolio history
            let profitLossPct = portfolioHistory.last?.profitLossPct ?? 0.0
            
            // New cards for Total Accounts
            // With TWR ON, Balance should equal first equity + net cash flows within the visible range
            let startBalanceAdjusted_visible: Double = {
                if showTWR, let firstData = portfolioHistory.first, let lastData = portfolioHistory.last {
                    let startTs = firstData.timestamp
                    let endTs = lastData.timestamp
                    let visibleFlows = twrPoints.filter { $0.timestamp > startTs && $0.timestamp <= endTs }
                    let totalNetCashFlow = visibleFlows.reduce(0.0) { $0 + $1.net_cash_flow }
                    return firstData.equity + totalNetCashFlow
                }
                return start_total_accounts_display
            }()
            PerformanceMetricCard(
                title: showTWR ? "Balance" : "Start Value",
                value: startBalanceAdjusted_visible,
                isPositive: nil
            )
            
            PerformanceMetricCard(
                title: showTWR ? "Current Value" : "Current",
                value: {
                    if showTWR, let lastData = portfolioHistory.last { return lastData.equity }
                    return current_total_accounts
                }(),
                isPositive: nil
            )
            
            // When TWR is ON, show cash-flow discounted change using cumulative TWR.
            // Align the base with the equity chart start to avoid mismatches with start_total_accounts.
            if showTWR { // Compute Net Change = Current - Balance (both aligned to visible equity range)
                if let firstData = portfolioHistory.first, let lastData = portfolioHistory.last {
                    let startTs = firstData.timestamp
                    let endTs = lastData.timestamp
                    let visibleFlows = twrPoints.filter { $0.timestamp > startTs && $0.timestamp <= endTs }
                    let totalNetCashFlow = visibleFlows.reduce(0.0) { $0 + $1.net_cash_flow }
                    let startBalanceAdjusted = firstData.equity + totalNetCashFlow
                    let currentValue = lastData.equity
                    let netChangeAmount = currentValue - startBalanceAdjusted
                    PerformanceMetricCard(
                        title: "Net Change",
                        value: netChangeAmount,
                        isPositive: netChangeAmount >= 0,
                        percentage: nil
                    )
                }
            } else {
                PerformanceMetricCard(
                    title: "Change",
                    value: change_total_accounts,
                    isPositive: change_total_accounts >= 0,
                    percentage: start_total_accounts_display > 0 ? (change_total_accounts / start_total_accounts_display) * 100 : (current_total_accounts > 0 ? 100.0 : 0.0)
                )
            }
            
            // Show Return % only when TWR is OFF
            if !showTWR {
                PerformanceMetricCard(
                    title: "Return %",
                    value: profitLossPct,
                    isPositive: profitLossPct >= 0,
                    percentage: nil,
                    isPercentage: true
                )
            }
            
            if showTWR, let twrPct = twrPoints.last?.cumulative_twr { // Use cash-flow discounted cumulative TWR
                PerformanceMetricCard(
                    title: "TWR Return %",
                    value: twrPct,
                    isPositive: twrPct >= 0,
                    percentage: nil,
                    isPercentage: true
                )
            }
            } else {
                // For individual accounts
                if showTWR, let firstData = portfolioHistory.first {
                    let totalNetCashFlow = twrPoints.reduce(0.0) { $0 + $1.net_cash_flow }
                    let startBalanceAdjusted = firstData.equity + totalNetCashFlow
                    PerformanceMetricCard(
                        title: "Balance",
                        value: startBalanceAdjusted,
                        isPositive: nil
                    )
                    if let lastData = portfolioHistory.last {
                        PerformanceMetricCard(
                            title: "Current Value",
                            value: lastData.equity,
                            isPositive: nil
                        )
                    }
                    if let lastData = portfolioHistory.last {
                        let netChangeAmount = lastData.equity - startBalanceAdjusted
                        PerformanceMetricCard(
                            title: "Net Change",
                            value: netChangeAmount,
                            isPositive: netChangeAmount >= 0,
                            percentage: nil
                        )
                    }
                    if let twrPct = twrPoints.last?.cumulative_twr {
                        PerformanceMetricCard(
                            title: "TWR Return %",
                            value: twrPct,
                            isPositive: twrPct >= 0,
                            percentage: nil,
                            isPercentage: true
                        )
                    }
                    
                    // Show Return % only when TWR is OFF
                    if !showTWR, let firstData = portfolioHistory.first,
                       let lastData = portfolioHistory.last {
                        let equityReturnPct = firstData.equity > 0 ? ((lastData.equity - firstData.equity) / firstData.equity) * 100 : 0
                        PerformanceMetricCard(
                            title: "Return %",
                            value: equityReturnPct,
                            isPositive: equityReturnPct >= 0,
                            percentage: nil,
                            isPercentage: true
                        )
                    }
                } else {
                    // Equity-based cards when TWR is OFF
                    if let firstData = portfolioHistory.first {
                        PerformanceMetricCard(
                            title: "Start Value",
                            value: firstData.equity,
                            isPositive: nil
                        )
                    }
                    if let lastData = portfolioHistory.last {
                        PerformanceMetricCard(
                            title: "Current Value",
                            value: lastData.equity,
                            isPositive: nil
                        )
                    }
                    if let firstData = portfolioHistory.first,
                       let lastData = portfolioHistory.last {
                        let totalChange = lastData.equity - firstData.equity
                        let totalChangePct = (totalChange / firstData.equity) * 100
                        let isPositive = totalChange >= 0
                        PerformanceMetricCard(
                            title: "Total Change",
                            value: totalChange,
                            isPositive: isPositive,
                            percentage: nil
                        )
                        
                        // Show Return % only when TWR is OFF
                        if !showTWR {
                            PerformanceMetricCard(
                                title: "Return %",
                                value: totalChangePct,
                                isPositive: totalChangePct >= 0,
                                percentage: nil,
                                isPercentage: true
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var equityChartView: some View {
        VStack(alignment: .leading, spacing: 16) {
            chartHeaderView
            chartContentView
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }

    private var twrChartView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Encabezado simple con estado
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill((twrPoints.last?.cumulative_twr ?? 0) >= 0 ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text((twrPoints.last?.cumulative_twr ?? 0) >= 0 ? "Alcista" : "Bajista")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor((twrPoints.last?.cumulative_twr ?? 0) >= 0 ? .green : .red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            twrInteractiveChart
            .frame(height: 350)
            .background(Color.clear)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }

    private var twrInteractiveChart: some View {
        // Calcular padding igual que equity chart (10%)
        let values = twrPoints.map { $0.cumulative_twr }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let padding = (maxValue - minValue) * 0.1
        let baselineValue = minValue - padding
        return GeometryReader { geometry in
            ZStack {
                Chart(twrPoints) { p in
                    AreaMark(
                        x: .value("Date", p.timestamp),
                        yStart: .value("Base", baselineValue),
                        yEnd: .value("TWR %", p.cumulative_twr)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [
                            Color.blue.opacity(0.4),
                            Color.blue.opacity(0.2),
                            Color.blue.opacity(0.05)
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("Date", p.timestamp),
                        y: .value("TWR %", p.cumulative_twr)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    
                    // Puntos
                    PointMark(
                        x: .value("Date", p.timestamp),
                        y: .value("TWR %", p.cumulative_twr)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(6)
                    .opacity(selectedTwrPoint?.id == p.id ? 0 : 1)
                    
                    PointMark(
                        x: .value("Date", p.timestamp),
                        y: .value("TWR %", p.cumulative_twr)
                    )
                    .foregroundStyle(.white)
                    .symbolSize(selectedTwrPoint?.id == p.id ? 40 : 0)
                    .opacity(selectedTwrPoint?.id == p.id ? 1 : 0)
                }
                .chartYScale(domain: (minValue - padding)...(maxValue + padding))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(.gray.opacity(0.3))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(String(format: "%.2f", v))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    if !hovering { selectedTwrPoint = nil }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        handleTwrHoverInteraction(at: location, in: geometry)
                    case .ended:
                        selectedTwrPoint = nil
                    }
                }

                if let p = selectedTwrPoint {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(formatTimestampForTooltip(p.timestamp))
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("\(String(format: "%.2f", p.cumulative_twr))%")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        HStack(spacing: 8) {
                            Text("Daily:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.2f", p.daily_return))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(p.daily_return >= 0 ? .green : .red)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .position(x: min(max(lastHoverPoint.x, 150), geometry.size.width - 150), y: lastHoverPoint.y - 80)
                }

                if !twrPoints.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatTwrDateRange())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(.regularMaterial.opacity(0.8)))
                                .padding(.trailing, 8)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
    }

    @State private var lastHoverPoint: CGPoint = .zero

    private func handleTwrHoverInteraction(at location: CGPoint, in geometry: GeometryProxy) {
        guard !twrPoints.isEmpty else { return }
        let chartWidth = max(1, geometry.size.width)
        var relativeX = max(0, min(1, location.x / chartWidth))
        // Asegura seleccionar el último punto cuando estás muy a la derecha
        if relativeX >= 0.95 { relativeX = 1.0 }
        let rawIndex = relativeX * Double(max(twrPoints.count - 1, 0))
        let index = Int(round(rawIndex))
        let clamped = max(0, min(index, twrPoints.count - 1))
        selectedTwrPoint = twrPoints[clamped]
        lastHoverPoint = CGPoint(x: min(max(location.x, 0), chartWidth), y: location.y)
    }

    private func formatTwrDateRange() -> String {
        guard let first = twrPoints.first?.timestamp, let last = twrPoints.last?.timestamp else { return "" }
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none
        return "\(f.string(from: first)) - \(f.string(from: last))"
    }
    
    private var chartHeaderView: some View {
        HStack {
            Spacer()
            
            // Indicador de estado
            HStack(spacing: 8) {
                Circle()
                    .fill(portfolioHistory.last?.profitLossPct ?? 0 >= 0 ? .green : .red)
                    .frame(width: 8, height: 8)
                
                Text(portfolioHistory.last?.profitLossPct ?? 0 >= 0 ? "Alcista" : "Bajista")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(portfolioHistory.last?.profitLossPct ?? 0 >= 0 ? .green : .red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var chartContentView: some View {
        ZStack {
            interactiveChart
            tooltipView
        }
    }
    
    private var interactiveChart: some View {
        // For Total Accounts, use equity sum (same as individual accounts)
        // For individual accounts, use equity (balance)
        let isTotalAccounts = account.name == "Total Accounts"
        let usePercentage = showTWR && !isTotalAccounts  // Only use percentage for TWR, not for Total Accounts
        
        let chartData: [Double]
        let chartLabel: String
        let filteredPortfolioHistory: [PortfolioHistoryDataPoint]
        
        if usePercentage {
            // Use percentage series only when TWR is enabled (not for Total Accounts)
            filteredPortfolioHistory = portfolioHistory
            chartData = filteredPortfolioHistory.map { $0.profitLossPct }
            chartLabel = "Return %"
        } else {
            // For individual accounts and Total Accounts equity view
            filteredPortfolioHistory = portfolioHistory.filter { $0.equity > 0 }
            chartData = filteredPortfolioHistory.map { $0.equity }
            chartLabel = "Equity"
        }
        
        let minValue = chartData.min() ?? 0
        let maxValue = chartData.max() ?? 0
        let padding = (maxValue - minValue) * 0.1 // 10% de padding
        let baselineValue = minValue - padding // Valor base para el área
        
        return GeometryReader { geometry in
            ZStack {
                Chart(filteredPortfolioHistory) { dataPoint in
                    // Área del gráfico con gradiente (con línea base personalizada)
                    AreaMark(
                        x: .value("Date", dataPoint.timestamp),
                        yStart: .value("Base", baselineValue),
                        yEnd: .value(chartLabel, usePercentage ? dataPoint.profitLossPct : dataPoint.equity)
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
                    
                    // Línea principal del gráfico (con interpolación suavizada)
                    LineMark(
                        x: .value("Date", dataPoint.timestamp),
                        y: .value(chartLabel, usePercentage ? dataPoint.profitLossPct : dataPoint.equity)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                    
                    // Puntos de datos normales
                    PointMark(
                        x: .value("Date", dataPoint.timestamp),
                        y: .value(chartLabel, usePercentage ? dataPoint.profitLossPct : dataPoint.equity)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(6)
                    .opacity(selectedDataPoint?.id == dataPoint.id ? 0 : 1)
                    
                    // Puntos de datos interactivos (seleccionados)
                    PointMark(
                        x: .value("Date", dataPoint.timestamp),
                        y: .value(chartLabel, usePercentage ? dataPoint.profitLossPct : dataPoint.equity)
                    )
                    .foregroundStyle(.white)
                    .symbolSize(selectedDataPoint?.id == dataPoint.id ? 40 : 0)
                    .opacity(selectedDataPoint?.id == dataPoint.id ? 1 : 0)
                }
                .frame(height: 350)
                .chartYScale(domain: (minValue - padding)...(maxValue + padding))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(.gray.opacity(0.3))
                        AxisValueLabel(format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(.gray.opacity(0.3))
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                if usePercentage {
                                    Text("\(String(format: "%.2f", doubleValue))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("$\(String(format: "%.0f", doubleValue))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .background(Color.clear)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    if isHovering {
                        // Hover started
                    } else {
                        selectedDataPoint = nil
                        self.isHovering = false
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        handleHoverInteraction(at: location, in: geometry)
                    case .ended:
                        selectedDataPoint = nil
                        isHovering = false
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
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.regularMaterial.opacity(0.8))
                                )
                                .padding(.trailing, 8)
                                .padding(.bottom, 20) // Moved up from 8 to 20 to match comparison chart
                        }
                    }
                    .frame(height: 350) // Match the chart height exactly
                }
            }
        }
    }
    
    private func handleHoverInteraction(at location: CGPoint, in geometry: GeometryProxy) {
        // Calcular el ancho del gráfico (asumiendo que el gráfico ocupa la mayor parte del espacio)
        let chartWidth = geometry.size.width
        let chartHeight = geometry.size.height
        
        // Calcular la posición relativa en el gráfico (0.0 a 1.0)
        let relativeX = location.x / chartWidth
        let relativeY = location.y / chartHeight
        
        // Encontrar el punto más cercano basado en la posición X
        guard !portfolioHistory.isEmpty else {
            return
        }
        
        // Asegurar que relativeX pueda alcanzar el 100% para seleccionar el último punto
        // Si estamos muy cerca del borde derecho (últimos 5% del gráfico), seleccionar el último punto
        let adjustedRelativeX = relativeX >= 0.95 ? 1.0 : relativeX
        let dataPointIndex = Int(adjustedRelativeX * Double(portfolioHistory.count - 1))
        let clampedIndex = max(0, min(dataPointIndex, portfolioHistory.count - 1))
        
        let selectedPoint = portfolioHistory[clampedIndex]
        selectedDataPoint = selectedPoint
        isHovering = true
        
        // Calcular la posición del punto en el gráfico para el tooltip
        let pointX = relativeX * chartWidth
        let pointY = relativeY * chartHeight
        hoverLocation = CGPoint(x: pointX, y: pointY)
    }
    
    @ViewBuilder
    private var tooltipView: some View {
        if let selectedPoint = selectedDataPoint, isHovering {
            let isTotalAccounts = account.name == "Total Accounts"
            VStack(alignment: .leading, spacing: 8) {
                Text(formatTimestampForTooltip(selectedPoint.timestamp))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                // When TWR is OFF, Total Accounts should behave like individual accounts (equity + change)
                if isTotalAccounts && showTWR {
                    Text("\(String(format: "%.2f", selectedPoint.profitLossPct))%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                } else {
                    Text("$\(String(format: "%.2f", selectedPoint.equity))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    HStack {
                        Text("Change:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Calcular cambio correcto para el último punto (día de hoy)
                        let (changeAmount, changePercentage) = calculateCorrectChange(for: selectedPoint)
                        
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
            .padding(12)
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
                x: min(max(hoverLocation.x, 150), 800), // Evitar que quede oculto detrás del menú izquierdo y por el margen derecho
                y: hoverLocation.y - 80 // Posicionar arriba del punto
            )
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedDataPoint?.id)
        }
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
    
    // Función para asignar el ancho exacto a cada período basado en la imagen
    private func periodWidth(_ period: PortfolioHistoryPeriod) -> CGFloat {
        switch period {
        case .oneDay:
            return 60
        case .oneWeek:
            return 70
        case .oneMonth:
            return 70
        case .threeMonths:
            return 85
        case .oneYear:
            return 65
        case .all:
            return 40
        case .custom:
            return 70
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
    
    
}

struct PerformanceMetricCard: View {
    let title: String
    let value: Double
    let isPositive: Bool?
    let percentage: Double?
    let isPercentage: Bool
    
    init(title: String, value: Double, isPositive: Bool?, percentage: Double? = nil, isPercentage: Bool = false) {
        self.title = title
        self.value = value
        self.isPositive = isPositive
        self.percentage = percentage
        self.isPercentage = isPercentage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Título con icono
            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            // Valor principal
            HStack(alignment: .bottom, spacing: 4) {
                if isPercentage {
                    Text("\(value, specifier: "%.2f")%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(valueColor)
                } else {
                    Text("$\(value, specifier: "%.2f")")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(valueColor)
                }
                
                if let percentage = percentage, !isPercentage {
                    Text("(\(percentage, specifier: "%.2f")%)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(valueColor.opacity(0.8))
                }
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
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
        Color(NSColor.controlBackgroundColor).opacity(0.6)
    }
    
    private var borderColor: Color {
        if let isPositive = isPositive {
            return isPositive ? .green.opacity(0.3) : .red.opacity(0.3)
        }
        return .clear
    }
    
    private var shadowColor: Color {
        if let isPositive = isPositive {
            return isPositive ? .green.opacity(0.1) : .red.opacity(0.1)
        }
        return .black.opacity(0.05)
    }
    
}


#Preview {
    PerformanceView(accountManager: AccountManager(), onNavigateToComparison: nil)
}