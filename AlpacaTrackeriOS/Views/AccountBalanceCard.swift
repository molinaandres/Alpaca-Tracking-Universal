import SwiftUI

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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header con nombre y tipo de cuenta
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        let totalSuffix: String = (account.name == "Total Accounts") ? " (\(accountManager.realAccounts.count))" : ""
                        Text(account.name + totalSuffix)
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
                VStack(alignment: .leading, spacing: 4) {
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
                            HStack(spacing: 2) {
                                Text("$")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Text(EuropeanNumberFormatter.shared.format(balance))
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.primary)
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                            }
                            
                            if let dailyChange = dailyChangePercentage {
                                HStack(spacing: 4) {
                                    Image(systemName: dailyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                    
                                    Text("\(dailyChange >= 0 ? "+" : "")\(EuropeanNumberFormatter.shared.format(dailyChange))%")
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
                
                // Last update time (original position)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Last update")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    if let lastUpdate = accountManager.allBalances[account.id]?.lastUpdated {
                        Text(formatLastUpdateTime(lastUpdate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(ColorCompatibility.controlBackground())
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            loadBalance()
            calculateDailyChange()
        }
    }
    
    private func loadBalance() {
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
    
    private func formatLastUpdateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}


