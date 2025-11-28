import SwiftUI

struct PositionsView: View {
    @ObservedObject var accountManager: AccountManager
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var selectedAccount: UUID?
    @State private var showingAccountPicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if accountManager.realAccounts.isEmpty {
                    emptyStateView
                } else {
                    accountSelectorView
                    positionsContentView
                }
            }
            .background(ColorCompatibility.appBackground())
        }
        .sheet(isPresented: $showingAccountPicker) {
            AccountPickerView(
                accounts: SettingsManager.shared.ordered(accountManager.realAccounts),
                selectedAccount: $selectedAccount,
                accountManager: accountManager
            )
        }
        .onAppear {
            loadSelectedAccount()
        }
        .onChange(of: selectedAccount) { _, newAccountId in
            saveSelectedAccount(newAccountId)
        }
    }
    
    private var emptyStateView: some View {
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
    }
    
    private var accountSelectorView: some View {
        VStack(spacing: 0) {
            // Header compacto con fondo negro
            VStack(spacing: 8) {
            
            // Información de cuenta compacta
            if let selectedAccount = selectedAccount,
               let account = accountManager.realAccounts.first(where: { $0.id == selectedAccount }) {
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
                        
                        if let lastUpdate = accountManager.lastUpdateTime {
                            Text(lastUpdate, format: .dateTime.hour().minute())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
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
                .padding(.horizontal, 16)
            }
            }
            .background(Color.black)
        }
    }
    
    private var positionsContentView: some View {
        Group {
            if let selectedAccount = selectedAccount,
               let account = accountManager.realAccounts.first(where: { $0.id == selectedAccount }) {
                PositionsDetailView(
                    account: account,
                    tradingDataManager: accountManager.tradingDataManager
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("Select an account")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Choose an account from the list to view its positions")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func loadSelectedAccount() {
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
    
    private func saveSelectedAccount(_ newAccountId: UUID?) {
        if let newAccountId = newAccountId {
            settingsManager.updateSelectedAccount(newAccountId.uuidString)
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
        ScrollView {
            VStack(spacing: 16) {
                // Métricas principales para móvil
                VStack(spacing: 12) {
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
                .padding(.horizontal, 16) // Agregar márgenes laterales
                
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        let count = positions.count
                        let showCount = count > 1
                        (
                            Text("Open Positions") +
                            (showCount ? Text(" (\(count))").font(.headline) : Text(""))
                        )
                        .font(.headline)
                        .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                        
                        LazyVStack(spacing: 8) {
                            ForEach(positions, id: \.id) { position in
                                PositionRow(position: position)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.bottom, 100) // Espacio para el TabView
        }
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
                HStack(spacing: 2) {
                    Text("$")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(valueColor)
                    
                    Text(EuropeanNumberFormatter.shared.format(value))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(valueColor)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                
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
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorCompatibility.controlBackground())
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1.5)
                )
                .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
        )
    }
    
    private var valueColor: Color {
        isPositive ? .green : .red
    }
    
    private var accentColor: Color {
        isPositive ? .green : .red
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
        VStack(spacing: 12) {
            // Header con símbolo y lado
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(position.symbol)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(position.assetClass.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(EuropeanNumberFormatter.shared.format(position.quantity))
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text(position.side.uppercased())
                        .font(.caption)
                        .foregroundColor(position.side.lowercased() == "long" ? .green : .red)
                }
            }
            
            // Precio y P&L
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(EuropeanNumberFormatter.shared.format(position.currentPriceDouble))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Unrealized P&L")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(EuropeanNumberFormatter.shared.format(position.unrealizedPLDouble))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(position.isProfitable ? .green : .red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Market Value")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(EuropeanNumberFormatter.shared.format(position.marketValueDouble))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            
            // P&L Intradía
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Entry Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(EuropeanNumberFormatter.shared.format(Double(position.avgEntryPrice) ?? 0.0))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Intraday P&L")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(EuropeanNumberFormatter.shared.format(Double(position.unrealizedIntradayPl) ?? 0.0))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor((Double(position.unrealizedIntradayPl) ?? 0.0) >= 0 ? .green : .red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("P&L %")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(EuropeanNumberFormatter.shared.format(Double(position.unrealizedPlpc) ?? 0.0))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(position.isProfitable ? .green : .red)
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorCompatibility.controlBackground())
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .tooltip(maxWidth: 300) {
            PositionTooltipContent(position: position)
        }
    }
}

#Preview {
    PositionsView(accountManager: AccountManager())
}
