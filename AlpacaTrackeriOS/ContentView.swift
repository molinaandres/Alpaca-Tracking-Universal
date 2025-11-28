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
    // Force reload tokens for Performance and Comparison tabs
    @State private var performanceReloadToken = UUID()
    @State private var comparisonReloadToken = UUID()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Accounts Tab
            NavigationView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        // Título y botón de agregar cuenta
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                let realCount = accountManager.realAccounts.count
                                let showCount = realCount > 1
                                (
                                    Text("Accounts") +
                                    (showCount ? Text(" (\(realCount))").font(.system(size: 18)) : Text(""))
                                )
                                .font(.title2)
                                .fontWeight(.bold)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                showingAddAccount = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle")
                                        .font(.subheadline)
                                    Text("Add Account")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .background(ColorCompatibility.appBackground())
                    
                    // Content with pull-to-refresh
                    ScrollView {
                        AccountsTabView(
                            accountManager: accountManager,
                            showingAddAccount: $showingAddAccount,
                            showingEditAccount: $showingEditAccount,
                            accountToEdit: $accountToEdit,
                            showingDeleteConfirmation: $showingDeleteConfirmation,
                            accountToDelete: $accountToDelete,
                            onSelectAccount: { account in
                                // Persist selection and navigate to Performance
                                settingsManager.updateSelectedAccount(account.id.uuidString)
                                selectedTab = 1
                            }
                        )
                    }
                    .refreshable {
                        await refreshAllData()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ColorCompatibility.appBackground())
            }
            .tabItem {
                Image(systemName: "person.2.fill")
                Text("Accounts")
            }
            .tag(0)
            .onAppear {
                // Preload daily changes for all accounts regardless of scroll visibility
                // This will now wait for balances to be available before calculating
                accountManager.preloadDailyChanges()
            }
            
            // Performance Tab
            PerformanceView(
                accountManager: accountManager,
                onNavigateToComparison: {
                    // Navigation handled by TabView
                }
            )
            .id(performanceReloadToken)
            .tabItem {
                Image(systemName: "chart.xyaxis.line")
                Text("Performance")
            }
            .tag(1)
            
            // Comparison Tab
            IndexComparisonView(
                accountManager: accountManager
            )
            .id(comparisonReloadToken)
            .tabItem {
                Image(systemName: "chart.bar.xaxis")
                Text("Comparison")
            }
            .tag(2)
            
            // Positions Tab
            PositionsView(accountManager: accountManager)
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Positions")
                }
                .tag(3)
            
            // Settings Tab
            iOSSettingsView(onNavigateToAccounts: {
                selectedTab = 0
            })
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(4)
        }
        .background(ColorCompatibility.appBackground())
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 1 { performanceReloadToken = UUID() }
            if newValue == 2 { comparisonReloadToken = UUID() }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView(accountManager: accountManager)
        }
        .sheet(isPresented: $showingEditAccount) {
            if let account = accountToEdit {
                EditAccountView(accountManager: accountManager, account: account)
            }
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
    
    // MARK: - Refresh Function
    
    @MainActor
    private func refreshAllData() async {
        // Refresh all account balances
        for account in accountManager.accounts {
            accountManager.updateAccountBalance(account.id)
        }
        
        // Refresh trading data
        accountManager.tradingDataManager.updateAllTradingData()
        
        // Refresh indices data
        await refreshIndicesData()
        
        // Add a small delay to ensure the refresh animation is visible
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    @MainActor
    private func refreshIndicesData() async {
        return await withCheckedContinuation { continuation in
            let indexDataManager = IndexDataManager()
            indexDataManager.refreshAllIndices { result in
                continuation.resume()
            }
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
            AccountsGrid(
                accounts: orderedAccounts,
                accountManager: accountManager,
                onSelectAccount: onSelectAccount,
                accountToEdit: $accountToEdit,
                showingEditAccount: $showingEditAccount,
                accountToDelete: $accountToDelete,
                showingDeleteConfirmation: $showingDeleteConfirmation,
                isReordering: $isReordering,
                draggingAccount: $draggingAccount,
                orderedAccounts: $orderedAccounts
            )
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
                .padding(.horizontal, 20)
            
            IndicesGrid()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorCompatibility.appBackground())
        .onAppear {
            orderedAccounts = settingsManager.ordered(accountManager.allAccounts)
        }
        .onReceive(accountManager.$accounts) { _ in
            if !isReordering { orderedAccounts = settingsManager.ordered(accountManager.allAccounts) }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isReordering {
                    Button("Done") {
                        withAnimation(.spring()) {
                            isReordering = false
                            draggingAccount = nil
                        }
                        // Persist order
                        let ids = orderedAccounts.map { $0.id.uuidString }
                        settingsManager.updateAccountsOrder(ids)
                    }
                }
            }
        }
    }
}

private struct AccountsGrid: View {
    let accounts: [AlpacaAccount]
    @ObservedObject var accountManager: AccountManager
    let onSelectAccount: (AlpacaAccount) -> Void
    @Binding var accountToEdit: AlpacaAccount?
    @Binding var showingEditAccount: Bool
    @Binding var accountToDelete: AlpacaAccount?
    @Binding var showingDeleteConfirmation: Bool
    @Binding var isReordering: Bool
    @Binding var draggingAccount: AlpacaAccount?
    @Binding var orderedAccounts: [AlpacaAccount]

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(accounts) { account in
                    ReorderableAccountCard(
                        account: account,
                        accountManager: accountManager,
                        onSelect: { onSelectAccount($0) },
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
                        isReordering: $isReordering,
                        dragging: $draggingAccount,
                        orderedAccounts: $orderedAccounts
                    )
                }
            }
            .padding(20)
        }
    }
}

private struct IndicesGrid: View {
    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Index.allIndices) { index in
                    IndexCard(index: index)
                }
            }
            .padding(20)
        }
    }
}

private struct ReorderableAccountCard: View {
    let account: AlpacaAccount
    @ObservedObject var accountManager: AccountManager
    let onSelect: (AlpacaAccount) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Binding var isReordering: Bool
    @Binding var dragging: AlpacaAccount?
    @Binding var orderedAccounts: [AlpacaAccount]

    var body: some View {
        Button(action: { onSelect(account) }) {
            AccountBalanceCard(
                account: account,
                onEdit: onEdit,
                onDelete: onDelete,
                accountManager: accountManager
            )
            .contentShape(Rectangle())
            .overlay(
                Group {
                    if isReordering, dragging?.id == account.id {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.0)
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isReordering = true
                    }
                }
        )
        .onDrag { dragging = account; return NSItemProvider(object: NSString(string: account.id.uuidString)) }
        .onDrop(of: [UTType.text], delegate: AccountReorderDropDelegate(item: account, items: $orderedAccounts, current: $dragging))
    }
}

private struct AccountReorderDropDelegate: DropDelegate {
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
        // Persist new order immediately
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

#Preview {
    ContentView()
}