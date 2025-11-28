import SwiftUI

struct PositionsView: View {
    @ObservedObject var accountManager: AccountManager
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var selectedAccount: UUID?
    
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
                        
                        Text("Add an Alpaca account to view positions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Lista de cuentas y posiciones
                    HStack(spacing: 0) {
                        // Sidebar con cuentas
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Accounts")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(NSColor.controlBackgroundColor))
                            
                            List(SettingsManager.shared.ordered(accountManager.realAccounts), id: \.id) { account in
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
                        
                        // Vista de posiciones
                        if let selectedAccount = selectedAccount,
                           let account = accountManager.realAccounts.first(where: { $0.id == selectedAccount }) {
                            PositionsDetailView(
                                account: account,
                                tradingDataManager: accountManager.tradingDataManager
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
                                
                                Text("Choose an account from the list to view its positions")
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
            // Cargar cuenta seleccionada desde configuraciones
            if let selectedAccountId = settingsManager.appSettings.selectedAccountId,
               let accountId = UUID(uuidString: selectedAccountId) {
                // Only set as selected if it's a real account (not Total Accounts)
                if accountManager.realAccounts.contains(where: { $0.id == accountId }) {
                    selectedAccount = accountId
                } else {
                    // If the saved account is Total Accounts or doesn't exist, select first real account
                    selectedAccount = SettingsManager.shared.ordered(accountManager.realAccounts).first?.id
                }
            } else if selectedAccount == nil && !accountManager.realAccounts.isEmpty {
                selectedAccount = SettingsManager.shared.ordered(accountManager.realAccounts).first?.id
            }
        }
        .onChange(of: selectedAccount) { _, newAccountId in
            // Guardar cuenta seleccionada
            if let newAccountId = newAccountId {
                settingsManager.updateSelectedAccount(newAccountId.uuidString)
            }
        }
    }
}

struct AccountRow: View {
    let account: AlpacaAccount
    let isSelected: Bool
    let accountManager: AccountManager
    let onSelect: () -> Void
    @State private var dailyChangePercentage: Double? = nil
    @State private var isLoadingDailyChange = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .primary)
                
                // Only show Live/Paper for real accounts, not Total Accounts
                if account.name != "Total Accounts" {
                    Text(account.isLiveTrading ? "Live Trading" : "Paper Trading")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                if let balance = accountManager.allBalances[account.id] {
                    HStack {
                        Text("$\(balance.balance, specifier: "%.2f")")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(isSelected ? .white : .primary)
                        
                        Spacer()
                        
                        // Cambio diario
                        if isLoadingDailyChange {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else if let dailyChange = dailyChangePercentage {
                            HStack(spacing: 4) {
                                Image(systemName: dailyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                    .foregroundColor(dailyChange >= 0 ? .green : .red)
                                
                                Text("\(dailyChange >= 0 ? "+" : "")\(dailyChange, specifier: "%.2f")%")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(dailyChange >= 0 ? .green : .red)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.05), radius: isSelected ? 8 : 2, x: 0, y: isSelected ? 4 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if account.id == accountManager.totalAccountsId || account.name == "Total Accounts" {
                // Use aggregated daily change for Total Accounts with gating
                if accountManager.areAllDailyChangesReady, let agg = accountManager.totalAccountsDailyChangeNew {
                    self.isLoadingDailyChange = false
                    self.dailyChangePercentage = agg
                } else {
                    self.isLoadingDailyChange = true
                    self.dailyChangePercentage = nil
                }
            } else {
                loadDailyChange()
            }
        }
    }
    
    private func loadDailyChange() {
        guard let apiService = accountManager.apiServices[account.id] else { 
            return 
        }
        
        isLoadingDailyChange = true
        
        // Usar período predefinido para evitar limitaciones de rangos personalizados
        apiService.getPortfolioHistory(
            period: .oneMonth,
            timeframe: .oneDay
        ) { result in
            DispatchQueue.main.async {
                self.isLoadingDailyChange = false
                
                switch result {
                case .success(let history):
                    self.processDailyChange(history: history)
                case .failure(_):
                    self.dailyChangePercentage = 0.0
                }
            }
        }
    }
    
    private func processDailyChange(history: PortfolioHistory) {
        guard let timestamps = history.timestamp,
              let equities = history.equity,
              timestamps.count >= 1,
              equities.count >= 1 else {
            dailyChangePercentage = 0.0
            return
        }
        
        // Usar el equity actual (balance) vs último día de trading disponible
        let currentEquity = accountManager.balances[account.id]?.balance ?? 0.0
        let lastTradingDayEquity = equities[equities.count - 1] // Último día de trading (puede ser de hace varios días)
        
        // Calcular el porcentaje de cambio desde el último día de trading hasta ahora
        if lastTradingDayEquity > 0 {
            let change = currentEquity - lastTradingDayEquity
            let changePercentage = (change / lastTradingDayEquity) * 100
            dailyChangePercentage = changePercentage
        } else {
            dailyChangePercentage = 0.0
        }
    }
}

struct PositionsDetailView: View {
    let account: AlpacaAccount
    @ObservedObject var tradingDataManager: TradingDataManager
    
    private var positions: [Position] {
        tradingDataManager.getPositions(for: account.id)
    }
    
    private var totalUnrealizedPL: Double {
        tradingDataManager.getTotalUnrealizedPL(for: account.id)
    }
    
    private var totalIntradayPL: Double {
        tradingDataManager.getTotalIntradayPL(for: account.id)
    }
    
    private var totalMarketValue: Double {
        tradingDataManager.getTotalMarketValue(for: account.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header con información de cuenta
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(account.isLiveTrading ? "Live Trading" : "Paper Trading")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let lastUpdate = tradingDataManager.lastUpdateTime {
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
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Métricas principales elegantes
            positionsSummaryView
            
                    // Lista de posiciones
                    if positions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No open positions")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Positions will appear here when you have active investments")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Título de sección con contador
                    HStack {
                        let count = positions.count
                        (
                            Text("Positions") + Text(" (\(count))")
                        )
                        .font(.headline)
                        .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
                    .background(Color(NSColor.controlBackgroundColor))

                    // Header de columnas
                    HStack(spacing: 0) {
                        // Symbol column - left aligned
                        VStack(alignment: .leading) {
                            Text("Symbol")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 120, alignment: .leading)
                        
                        // Quantity/Side column - centered
                        VStack(alignment: .center) {
                            Text("Quantity/Side")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        // Current Price column - centered
                        VStack(alignment: .center) {
                            Text("Current Price")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        // P&L column - centered
                        VStack(alignment: .center) {
                            Text("P&L")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        // Intraday P&L column - centered
                        VStack(alignment: .center) {
                            Text("Intraday P&L")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        // Market Value column - centered
                        VStack(alignment: .center) {
                            Text("Market Value")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    // Lista de posiciones
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(positions, id: \.id) { position in
                                PositionRow(position: position)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var positionsSummaryView: some View {
        HStack(spacing: 20) {
            // P&L No Realizado
            PositionsMetricCard(
                title: "Unrealized P&L",
                value: totalUnrealizedPL,
                isPositive: totalUnrealizedPL >= 0,
                icon: "chart.line.uptrend.xyaxis",
                subtitle: "Unrealized Gain/Loss"
            )
            
            // P&L Intradía
            PositionsMetricCard(
                title: "Intraday P&L",
                value: totalIntradayPL,
                isPositive: totalIntradayPL >= 0,
                icon: "clock.arrow.circlepath",
                subtitle: "Today's change"
            )
            
            // Valor de Mercado
            PositionsMetricCard(
                title: "Market Value",
                value: totalMarketValue,
                isPositive: true,
                icon: "dollarsign.circle",
                subtitle: "Total value of positions"
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}


struct PositionsMetricCard: View {
    let title: String
    let value: Double
    let isPositive: Bool
    let icon: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header con icono y título
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(accentColor)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(accentColor.opacity(0.1))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Valor principal
            VStack(alignment: .leading, spacing: 4) {
                Text("$\(value, specifier: "%.2f")")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(valueColor)
                
                // Indicador de estado
                HStack(spacing: 4) {
                    Circle()
                        .fill(valueColor)
                        .frame(width: 6, height: 6)
                    
                    Text(isPositive ? "Positive" : "Negative")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(valueColor)
                }
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
                        .stroke(borderColor, lineWidth: 1.5)
                )
                .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
        )
    }
    
    private var valueColor: Color {
        isPositive ? .green : .red
    }
    
    private var accentColor: Color {
        isPositive ? .green : .red
    }
    
    private var backgroundColor: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.8)
    }
    
    private var borderColor: Color {
        isPositive ? .green.opacity(0.3) : .red.opacity(0.3)
    }
    
    private var shadowColor: Color {
        isPositive ? .green.opacity(0.15) : .red.opacity(0.15)
    }
}

struct PositionRow: View {
    let position: Position
    
    var body: some View {
        HStack(spacing: 0) {
            // Símbolo - left aligned
            VStack(alignment: .leading, spacing: 4) {
                Text(position.symbol)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(position.assetClass.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 120, alignment: .leading)
            
            // Cantidad y lado - centered
            VStack(alignment: .center, spacing: 4) {
                Text("\(position.quantity, specifier: "%.2f")")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text(position.side.uppercased())
                    .font(.caption)
                    .foregroundColor(position.side.lowercased() == "long" ? .green : .red)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            // Precio actual - centered
            VStack(alignment: .center, spacing: 4) {
                Text("$\(position.currentPriceDouble, specifier: "%.2f")")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text("Entry: $\(Double(position.avgEntryPrice) ?? 0.0, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            // P&L - centered
            VStack(alignment: .center, spacing: 4) {
                Text("$\(position.unrealizedPLDouble, specifier: "%.2f")")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(position.isProfitable ? .green : .red)
                
                Text("\(Double(position.unrealizedPlpc) ?? 0.0, specifier: "%.2f")%")
                    .font(.caption)
                    .foregroundColor(position.isProfitable ? .green : .red)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            // P&L Intradía - centered
            VStack(alignment: .center, spacing: 4) {
                Text("$\(Double(position.unrealizedIntradayPl) ?? 0.0, specifier: "%.2f")")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor((Double(position.unrealizedIntradayPl) ?? 0.0) >= 0 ? .green : .red)
                
                Text("\(Double(position.unrealizedIntradayPlpc) ?? 0.0, specifier: "%.2f")%")
                    .font(.caption)
                    .foregroundColor((Double(position.unrealizedIntradayPl) ?? 0.0) >= 0 ? .green : .red)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            // Valor de mercado - centered
            VStack(alignment: .center, spacing: 4) {
                Text("$\(position.marketValueDouble, specifier: "%.2f")")
                    .font(.title3)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

#Preview {
    PositionsView(accountManager: AccountManager())
}
