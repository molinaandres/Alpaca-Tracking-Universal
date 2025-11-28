import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var accountManager = AccountManager()
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var showingAddAccount = false
    @State private var showingEditAccount = false
    @State private var accountToEdit: AlpacaAccount?
    @State private var showingDeleteConfirmation = false
    @State private var accountToDelete: AlpacaAccount?
    @State private var selectedTab = 0
    @State private var showingSettings = false
    // Force reload tokens for tabs
    @State private var performanceReloadToken = UUID()
    @State private var comparisonReloadToken = UUID()
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Grecia Tracker")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Manage your trading accounts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if selectedTab == 0 {
                        Button(action: {
                            showingAddAccount = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                Text("Add Account")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                
                // Tab selector
                HStack(spacing: 0) {
                    TabButton(
                        title: "Accounts",
                        icon: "person.2.fill",
                        isSelected: selectedTab == 0,
                        action: { 
                            selectedTab = 0 
                        }
                    )
                    
                    TabButton(
                        title: "Performance",
                        icon: "chart.xyaxis.line",
                        isSelected: selectedTab == 1,
                        action: { 
                            selectedTab = 1 
                        }
                    )
                    
                    TabButton(
                        title: "Comparison",
                        icon: "chart.line.uptrend.xyaxis",
                        isSelected: selectedTab == 2,
                        action: { 
                            selectedTab = 2 
                        }
                    )
                    
                    TabButton(
                        title: "Positions",
                        icon: "chart.line.uptrend.xyaxis",
                        isSelected: selectedTab == 3,
                        action: { 
                            selectedTab = 3 
                        }
                    )
                    
                }
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Content
                if selectedTab == 0 {
                    AccountsTabView(
                        accountManager: accountManager,
                        showingAddAccount: $showingAddAccount,
                        showingEditAccount: $showingEditAccount,
                        accountToEdit: $accountToEdit,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
                        accountToDelete: $accountToDelete,
                        onSelectAccount: { account in
                            settingsManager.updateSelectedAccount(account.id.uuidString)
                            selectedTab = 1
                        }
                    )
                    .onAppear {
                        // Preload daily changes for all accounts regardless of scroll visibility
                        // This will now wait for balances to be available before calculating
                        accountManager.preloadDailyChanges()
                    }
                } else if selectedTab == 1 {
                    // Pestaña de Performance
                    PerformanceView(
                        accountManager: accountManager,
                        onNavigateToComparison: {
                            selectedTab = 2
                        }
                    )
                        .id(performanceReloadToken)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                        }
                } else if selectedTab == 2 {
                    // Pestaña de Comparación con Índices
                    IndexComparisonView(
                        accountManager: accountManager,
                        onNavigateToPerformance: {
                            selectedTab = 1
                        }
                    )
                        .id(comparisonReloadToken)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                        }
                } else if selectedTab == 3 {
                    // Pestaña de Posiciones
                    PositionsView(accountManager: accountManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                    .padding(.horizontal, 15)
                    .padding(.bottom, 10)
                }
            )
        }
        .sheet(isPresented: $showingAddAccount) {
            MacOSAddAccountView(accountManager: accountManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingEditAccount) {
            if let account = accountToEdit {
                MacOSEditAccountView(accountManager: accountManager, account: account)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            // Force recreate target view when tab becomes active
            if newValue == 1 { performanceReloadToken = UUID() }
            if newValue == 2 { comparisonReloadToken = UUID() }
        }
        .onChange(of: showingEditAccount) { _, isShowing in
            if !isShowing {
                accountToEdit = nil
            }
        }
        .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let account = accountToDelete {
                    accountManager.deleteAccount(account)
                }
            }
        } message: {
            if let account = accountToDelete {
                Text("Are you sure you want to delete the account '\(account.name)'? This action cannot be undone.")
            }
        }
        .onAppear {
            accountManager.loadAccounts()
        }
    }
}

// MARK: - Helper Functions

private func getConnectionErrorMessage(_ error: Error) -> String {
    if let alpacaError = error as? AlpacaAPIService.AlpacaAPIError {
        switch alpacaError {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No se recibieron datos"
        case .unauthorized:
            return "Credenciales incorrectas"
        case .forbidden:
            return "Acceso denegado - Verifica permisos de cuenta"
        case .notFound:
            return "Endpoint no encontrado"
        case .serverError:
            return "Error del servidor"
        case .networkError:
            return "Connection error"
        case .decodingError:
            return "Error al procesar datos"
        case .invalidResponse:
            return "Invalid response"
        }
    }
    return error.localizedDescription
}

struct AccountBalanceCard: View {
    let account: AlpacaAccount
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ObservedObject var accountManager: AccountManager
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var balance: Double = 0.0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var dailyChangePercentage: Double? = nil
    @State private var recalcWorkItem: DispatchWorkItem?
    
    // Identificador único para debugging
    private let cardId = UUID().uuidString.prefix(8)
    
    private var accountDisplayName: String {
        if account.name == "Total Accounts" {
            return account.name + " (\(accountManager.realAccounts.count))"
        }
        return account.name
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header con nombre y tipo de cuenta
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(accountDisplayName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Indicador de tipo de cuenta
                        if account.name == "Total Accounts" {
                            Text("SUM")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        } else {
                            Text(account.isLiveTrading ? "LIVE" : "PAPER")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(account.isLiveTrading ? Color.red : Color.blue)
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                Menu {
                    if account.name == "Total Accounts" {
                        Button("Hide") {
                            // Desmarcar el checkbox de configuración
                            settingsManager.appSettings.showTotalAccounts = false
                            settingsManager.updateAppSettings(settingsManager.appSettings)
                        }
                    } else {
                        Button("Edit Account") {
                            onEdit()
                        }
                        Button("Delete Account", role: .destructive) {
                            onDelete()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Divider()
            
            // Información de balance
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading balance...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if let error = errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    } else {
                        HStack(alignment: .bottom, spacing: 8) {
                            Text("$\(balance, specifier: "%.2f")")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            if let dailyChange = dailyChangePercentage {
                                HStack(spacing: 4) {
                                    Image(systemName: dailyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                    
                                    Text("\(dailyChange >= 0 ? "+" : "")\(dailyChange, specifier: "%.2f")%")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill((dailyChange >= 0 ? Color.green : Color.red).opacity(0.1))
                                )
                                .onAppear {
                                }
                            } else {
                                Text("No data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .onAppear {
                                    }
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Last update")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(Date().formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            loadBalance()
            calculateDailyChange()
        }
        .onChange(of: accountManager.allBalances[account.id]?.balance) { _, newBalance in
            if let newBalance = newBalance {
                balance = newBalance
                isLoading = false
                errorMessage = accountManager.allBalances[account.id]?.error
            }
        }
        .onChange(of: accountManager.allBalances[account.id]) { _, newAccountBalance in
            if let newAccountBalance = newAccountBalance {
                balance = newAccountBalance.balance
                isLoading = false
                errorMessage = newAccountBalance.error
            } else {
                isLoading = true
                errorMessage = nil
            }
        }
        .onChange(of: accountManager.dailyChangePercentages) { _, _ in
            // Recalculate daily change for Total Accounts when individual account changes are updated
            if account.name == "Total Accounts" {
                // Cancel any pending work and schedule new calculation
                recalcWorkItem?.cancel()
                let work = DispatchWorkItem { 
                    calculateDailyChange()
                }
                recalcWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            }
        }
        .onChange(of: accountManager.balances) { _, _ in
            // When individual account balances update, refresh Total Accounts chip
            if account.name == "Total Accounts" {
                // Cancel any pending work and schedule new calculation
                recalcWorkItem?.cancel()
                let work = DispatchWorkItem { 
                    calculateDailyChange()
                }
                recalcWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            }
        }
    }
    
    private func loadBalance() {
        // El balance se carga automáticamente desde AccountManager
        // Solo actualizamos el estado local basado en el balance del AccountManager
        if let accountBalance = accountManager.allBalances[account.id] {
            balance = accountBalance.balance
            isLoading = false
            errorMessage = accountBalance.error
            
            // Calcular el cambio diario cuando el balance se actualiza
            if !isLoading {
                calculateDailyChange()
            }
        } else {
            isLoading = true
            errorMessage = nil
        }
    }
    
    private func calculateDailyChange() {
        if account.name == "Total Accounts" {
            // Total Accounts: calcular después de 2 segundos
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let isReady = self.accountManager.areAllDailyChangesReady
                let dailyChange = self.accountManager.totalAccountsDailyChangeNew
                
                if isReady, let change = dailyChange {
                    self.dailyChangePercentage = change
                } else {
                    self.dailyChangePercentage = dailyChange ?? 0.0
                }
            }
            return
        }
        
        // Cuentas individuales: calcular inmediatamente
        guard let apiService = accountManager.apiServices[account.id] else {
            return
        }
        
        apiService.getPortfolioHistory(period: .oneMonth, timeframe: .oneDay) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let history):
                    let currentEquity = self.balance
                    if let equities = history.equity, let last = equities.last, last > 0 {
                        let changePct = ((currentEquity - last) / last) * 100.0
                        self.dailyChangePercentage = changePct
                    } else {
                        self.dailyChangePercentage = 0.0
                    }
                    
                case .failure(_):
                    self.dailyChangePercentage = 0.0
                }
            }
        }
    }
    

}



struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct IndexCard: View {
    let index: Index
    @State private var currentValue: Double = 0.0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var dailyChangePercentage: Double? = nil
    @StateObject private var indexDataManager = IndexDataManager()
    
    // Identificador único para debugging
    private let cardId = UUID().uuidString.prefix(8)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header con nombre y símbolo del índice
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(index.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Indicador de tipo de índice
                        Text("INDEX")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                    
                    Text(index.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Icono de índice
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Información de valor actual
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Value")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading value...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if let error = errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    } else {
                        HStack(alignment: .bottom, spacing: 8) {
                            Text("\(currentValue, specifier: "%.2f")")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            if let dailyChange = dailyChangePercentage {
                                HStack(spacing: 4) {
                                    Image(systemName: dailyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                    
                                    Text("\(dailyChange >= 0 ? "+" : "")\(dailyChange, specifier: "%.2f")%")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill((dailyChange >= 0 ? Color.green : Color.red).opacity(0.1))
                                )
                            } else {
                                Text("No data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Last update")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(Date().formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            loadIndexData()
        }
    }
    
    private func loadIndexData() {
        // Obtener datos del índice para los últimos 30 días
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) ?? endDate
        
        indexDataManager.fetchIndexHistory(
            index: index,
            startDate: startDate,
            endDate: endDate
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let history):
                    if let lastDataPoint = history.dataPoints.last {
                        self.currentValue = lastDataPoint.value
                        self.isLoading = false
                        self.errorMessage = nil
                        
                        // Calcular cambio diario
                        self.calculateDailyChange(history: history)
                    } else {
                        self.isLoading = false
                        self.errorMessage = "No data available"
                    }
                case .failure(let error):
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func calculateDailyChange(history: IndexHistory) {
        guard history.dataPoints.count >= 2 else {
            self.dailyChangePercentage = 0.0
            return
        }
        
        let lastDataPoint = history.dataPoints[history.dataPoints.count - 1]
        let previousDataPoint = history.dataPoints[history.dataPoints.count - 2]
        
        let change = lastDataPoint.value - previousDataPoint.value
        let changePercentage = (change / previousDataPoint.value) * 100
        
        self.dailyChangePercentage = changePercentage
    }
}

struct AccountsTabView: View {
    @ObservedObject var accountManager: AccountManager
    @Binding var showingAddAccount: Bool
    @Binding var showingEditAccount: Bool
    @Binding var accountToEdit: AlpacaAccount?
    @Binding var showingDeleteConfirmation: Bool
    @Binding var accountToDelete: AlpacaAccount?
    var onSelectAccount: (AlpacaAccount) -> Void
    
    var body: some View {
        if accountManager.accounts.isEmpty {
            EmptyAccountsView(showingAddAccount: $showingAddAccount)
        } else {
            AccountsGridView(
                accountManager: accountManager,
                showingAddAccount: $showingAddAccount,
                showingEditAccount: $showingEditAccount,
                accountToEdit: $accountToEdit,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                accountToDelete: $accountToDelete,
                onSelectAccount: onSelectAccount
            )
        }
    }
}

struct EmptyAccountsView: View {
    @Binding var showingAddAccount: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
                .opacity(0.6)
            
            VStack(spacing: 12) {
                Text("No accounts configured")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Add your first Alpaca account to start tracking your balances")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            
            Button(action: {
                showingAddAccount = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add First Account")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct AccountsGridView: View {
    @ObservedObject var accountManager: AccountManager
    @Binding var showingAddAccount: Bool
    @Binding var showingEditAccount: Bool
    @Binding var accountToEdit: AlpacaAccount?
    @Binding var showingDeleteConfirmation: Bool
    @Binding var accountToDelete: AlpacaAccount?
    var onSelectAccount: (AlpacaAccount) -> Void
    private let settingsManager = SettingsManager.shared
    @State private var orderedAccounts: [AlpacaAccount] = []
    @State private var isReordering: Bool = false
    @State private var draggingAccount: AlpacaAccount?
    
    var body: some View {
        VStack(spacing: 0) {
            // Cuentas en grid adaptativo
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 400, maximum: 600), spacing: 16)
                ], spacing: 16) {
                    ForEach(orderedAccounts) { account in
                        AccountBalanceCard(
                            account: account,
                            onEdit: {
                                if account.name != "Total Accounts" {
                                    accountToEdit = account
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        showingEditAccount = true
                                    }
                                }
                            },
                            onDelete: {
                                if account.name != "Total Accounts" {
                                    accountToDelete = account
                                    showingDeleteConfirmation = true
                                }
                            },
                            accountManager: accountManager
                        )
                        .contentShape(Rectangle())
                        .overlay(
                            Group {
                                if isReordering, draggingAccount?.id == account.id {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.accentColor, lineWidth: 2)
                                }
                            }
                        )
                        .onTapGesture { onSelectAccount(account) }
                        .onLongPressGesture(minimumDuration: 1.0) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                isReordering = true
                            }
                        }
                        .onDrag { draggingAccount = account; return NSItemProvider(object: NSString(string: account.id.uuidString)) }
                        .onDrop(of: [UTType.text], delegate: MacAccountReorderDropDelegate(item: account, items: $orderedAccounts, current: $draggingAccount))
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)
            
            // Empujar índices al fondo
            Spacer(minLength: 0)
            
            // Separador horizontal
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
                .padding(.horizontal, 20)
            
            // Índices en grid adaptativo
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 400, maximum: 600), spacing: 16)
                ], spacing: 16) {
                    ForEach(Index.allIndices) { index in
                        IndexCard(index: index)
                    }
                }
                .padding(20)
            }
            .frame(height: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            orderedAccounts = settingsManager.ordered(accountManager.allAccounts)
        }
        .onReceive(accountManager.$accounts) { _ in
            if !isReordering { orderedAccounts = settingsManager.ordered(accountManager.allAccounts) }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if isReordering {
                    Button("Done") {
                        withAnimation(.spring()) {
                            isReordering = false
                            draggingAccount = nil
                        }
                        let ids = orderedAccounts.map { $0.id.uuidString }
                        settingsManager.updateAccountsOrder(ids)
                    }
                }
            }
        }
    }
}

private struct MacAccountReorderDropDelegate: DropDelegate {
    let item: AlpacaAccount
    @Binding var items: [AlpacaAccount]
    @Binding var current: AlpacaAccount?

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        guard let current = current, current.id != item.id,
              let from = items.firstIndex(where: { $0.id == current.id }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            let removed = items.remove(at: from)
            items.insert(removed, at: to)
        }
        let ids = items.map { $0.id.uuidString }
        SettingsManager.shared.updateAccountsOrder(ids)
    }

    func performDrop(info: DropInfo) -> Bool {
        let ids = items.map { $0.id.uuidString }
        SettingsManager.shared.updateAccountsOrder(ids)
        current = nil
        return true
    }
}

struct MacOSAddAccountView: View {
    @ObservedObject var accountManager: AccountManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var apiKey = ""
    @State private var secretKey = ""
    @State private var isLiveTrading = false
    @State private var firstTradeDate = Date()
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?
    
    // Nuevos campos de configuración
    @State private var leverage: Double = 1.0
    @State private var budget: Int = 100
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Account")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("✕") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.title3)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Información de la Cuenta
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Account Information")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Account name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Enter account name", text: $name)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Alpaca Account ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(description.isEmpty ? "Will be obtained automatically" : description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("First Trade")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            DatePicker("Select first trade date", selection: $firstTradeDate, displayedComponents: .date)
                                .datePickerStyle(CompactDatePickerStyle())
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Configuración de Trading (oculta temporalmente)
                    if false {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Trading Configuration")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Leverage")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Slider(value: $leverage, in: 1.0...2.0, step: 0.1)
                                    Text("\(leverage, specifier: "%.1f")x")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 50)
                                }
                                Text("Range: 1.00x - 2.00x")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Budget Allocation")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Slider(value: Binding(
                                        get: { Double(budget) },
                                        set: { budget = Int($0) }
                                    ), in: 0...100, step: 10)
                                    Text("\(budget)%")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 40)
                                }
                                Text("Range: 0% - 100% (in 10% steps)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                    
                    // Credenciales de Alpaca
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Alpaca Credentials")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Enter your API Key", text: $apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Secret Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Enter your Secret Key", text: $secretKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        HStack {
                            Toggle("Live Trading", isOn: $isLiveTrading)
                            Spacer()
                        }
                        .padding(.top, 8)
                        
                        Text("Disable to use paper trading environment")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        // Botón de prueba de conexión
                        HStack {
                            Button("Test Connection") {
                                testConnection()
                            }
                            .buttonStyle(.bordered)
                            .disabled(apiKey.isEmpty || secretKey.isEmpty || isTestingConnection)
                            
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 8)
                        
                        if let result = connectionTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("✅") ? .green : .red)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    saveAccount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || apiKey.isEmpty || secretKey.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func testConnection() {
        guard !apiKey.isEmpty && !secretKey.isEmpty else { return }
        
        isTestingConnection = true
        connectionTestResult = nil
        
        let testAccount = AlpacaAccount(
            name: "Test",
            description: nil,
            apiKey: apiKey,
            secretKey: secretKey,
            isLiveTrading: isLiveTrading,
            firstTradeDate: nil,
            leverage: leverage,
            budget: budget,
            canCloseAllPositions: false,
            canDisconnectFromGrecia: false
        )
        
        accountManager.testAccountConnection(testAccount) { result in
            DispatchQueue.main.async {
                isTestingConnection = false
                switch result {
                case .success:
                    connectionTestResult = "✅ Connection successful"
                case .failure(let error):
                    let errorMessage = getConnectionErrorMessage(error)
                    connectionTestResult = "❌ Error: \(errorMessage)"
                }
            }
        }
    }
    
    private func saveAccount() {
        let newAccount = AlpacaAccount(
            name: name,
            description: nil,
            apiKey: apiKey,
            secretKey: secretKey,
            isLiveTrading: isLiveTrading,
            firstTradeDate: firstTradeDate,
            leverage: leverage,
            budget: budget,
            canCloseAllPositions: false, // Solo disponible después de crear la cuenta
            canDisconnectFromGrecia: false // Solo disponible después de crear la cuenta
        )
        
        accountManager.addAccount(newAccount)
        dismiss()
    }
}

struct MacOSEditAccountView: View {
    @ObservedObject var accountManager: AccountManager
    let account: AlpacaAccount
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var description: String
    @State private var apiKey: String
    @State private var secretKey: String
    @State private var isLiveTrading: Bool
    @State private var firstTradeDate: Date
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?
    
    // Nuevos campos de configuración
    @State private var leverage: Double
    @State private var budget: Int
    
    // Estados para los botones de acción
    @State private var showingCloseAllConfirmation = false
    @State private var showingDisconnectConfirmation = false
    
    init(accountManager: AccountManager, account: AlpacaAccount) {
        self.accountManager = accountManager
        self.account = account
        self._name = State(initialValue: account.name)
        self._description = State(initialValue: account.description ?? "")
        
        // Desencriptar las credenciales para mostrarlas en el formulario
        let credentials = account.getDecryptedCredentials()
        self._apiKey = State(initialValue: credentials.apiKey)
        self._secretKey = State(initialValue: credentials.secretKey)
        
        self._isLiveTrading = State(initialValue: account.isLiveTrading)
        self._firstTradeDate = State(initialValue: account.firstTradeDate ?? Date())
        self._leverage = State(initialValue: account.leverage ?? 1.0)
        self._budget = State(initialValue: account.budget ?? 100)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Account")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("✕") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.title3)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Información de la Cuenta
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Account Information")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Account name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Enter account name", text: $name)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Alpaca Account ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(account.description ?? "Not available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("First Trade")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            DatePicker("Select first trade date", selection: $firstTradeDate, displayedComponents: .date)
                                .datePickerStyle(CompactDatePickerStyle())
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Configuración de Trading (oculta temporalmente)
                    if false {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Trading Configuration")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Leverage")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Slider(value: $leverage, in: 1.0...2.0, step: 0.1)
                                    Text("\(leverage, specifier: "%.1f")x")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 50)
                                }
                                Text("Range: 1.00x - 2.00x")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Budget Allocation")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Slider(value: Binding(
                                        get: { Double(budget) },
                                        set: { budget = Int($0) }
                                    ), in: 0...100, step: 10)
                                    Text("\(budget)%")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 40)
                                }
                                Text("Range: 0% - 100% (in 10% steps)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                    
                    // Credenciales de Alpaca
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Alpaca Credentials")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Enter your API Key", text: $apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Secret Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Enter your Secret Key", text: $secretKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        HStack {
                            Toggle("Live Trading", isOn: $isLiveTrading)
                            Spacer()
                        }
                        .padding(.top, 8)
                        
                        Text("Disable to use paper trading environment")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        // Botón de prueba de conexión
                        HStack {
                            Button("Test Connection") {
                                testConnection()
                            }
                            .buttonStyle(.bordered)
                            .disabled(apiKey.isEmpty || secretKey.isEmpty || isTestingConnection)
                            
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 8)
                        
                        if let result = connectionTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("✅") ? .green : .red)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // Botones de acción (ocultos temporalmente)
                    if false {
                        HStack(spacing: 16) {
                            Spacer()
                            Button("Close All Positions") {
                                showingCloseAllConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                            Button("Disconnect From Grecia") {
                                showingDisconnectConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.orange)
                            Spacer()
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save Changes") {
                    saveAccount()
                    // Forzar refresco inmediato
                    DispatchQueue.main.async {
                        accountManager.objectWillChange.send()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || apiKey.isEmpty || secretKey.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Close All Positions", isPresented: $showingCloseAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Close All", role: .destructive) {
                // TODO: Implementar lógica para cerrar todas las posiciones
                print("Close all positions action triggered")
            }
        } message: {
            Text("Are you sure you want to close all positions? This action cannot be undone.")
        }
        .alert("Disconnect From Grecia", isPresented: $showingDisconnectConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                // TODO: Implementar lógica para desconectar de Grecia
                print("Disconnect from Grecia action triggered")
            }
        } message: {
            Text("Are you sure you want to disconnect this account from Grecia? This action cannot be undone.")
        }
    }
    
    private func testConnection() {
        guard !apiKey.isEmpty && !secretKey.isEmpty else { return }
        
        isTestingConnection = true
        connectionTestResult = nil
        
        let testAccount = AlpacaAccount(
            name: "Test",
            description: nil,
            apiKey: apiKey,
            secretKey: secretKey,
            isLiveTrading: isLiveTrading,
            firstTradeDate: nil,
            leverage: leverage,
            budget: budget,
            canCloseAllPositions: false,
            canDisconnectFromGrecia: false
        )
        
        accountManager.testAccountConnection(testAccount) { result in
            DispatchQueue.main.async {
                isTestingConnection = false
                switch result {
                case .success:
                    connectionTestResult = "✅ Connection successful"
                case .failure(let error):
                    let errorMessage = getConnectionErrorMessage(error)
                    connectionTestResult = "❌ Error: \(errorMessage)"
                }
            }
        }
    }
    
    private func saveAccount() {
        let updatedAccount = AlpacaAccount(
            id: account.id,
            name: name,
            description: account.description,
            alpacaAccountId: account.alpacaAccountId,
            apiKey: apiKey,
            secretKey: secretKey,
            isLiveTrading: isLiveTrading,
            firstTradeDate: firstTradeDate,
            leverage: leverage,
            budget: budget,
            canCloseAllPositions: account.canCloseAllPositions ?? false,
            canDisconnectFromGrecia: account.canDisconnectFromGrecia ?? false
        )
        
        accountManager.updateAccount(updatedAccount)
        dismiss()
    }
}

#Preview {
    ContentView()
}