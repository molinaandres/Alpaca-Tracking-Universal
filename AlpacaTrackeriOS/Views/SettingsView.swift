import SwiftUI

struct iOSSettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var authService = SupabaseAuthService.shared
    @ObservedObject var accountManager: AccountManager
    @Environment(\.dismiss) private var dismiss
    let onNavigateToAccounts: (() -> Void)?
    
    // Variables temporales para los cambios
    @State private var tempDefaultPeriod: PortfolioPeriod
    @State private var tempDefaultTimeframe: Timeframe
    @State private var tempShowTotalAccounts: Bool
    @State private var showingChangePassword = false
    @State private var showingEditCredentials = false
    
    init(accountManager: AccountManager, onNavigateToAccounts: (() -> Void)? = nil) {
        self.accountManager = accountManager
        self.onNavigateToAccounts = onNavigateToAccounts
        let settings = SettingsManager.shared.appSettings
        _tempDefaultPeriod = State(initialValue: settings.defaultPeriod)
        _tempDefaultTimeframe = State(initialValue: settings.defaultTimeframe)
        _tempShowTotalAccounts = State(initialValue: settings.showTotalAccounts)
    }
    
    // Función para obtener los timeframes válidos para un período dado
    private func validTimeframes(for period: PortfolioPeriod) -> [Timeframe] {
        switch period {
        case .oneDay:
            return [.oneMinute, .fiveMinutes, .fifteenMinutes, .oneHour]
        case .oneWeek:
            return [.oneDay]
        case .oneMonth, .threeMonths, .oneYear, .allTime, .custom:
            return [.oneDay]
        }
    }
    
    // Función para validar si un timeframe es válido para un período
    private func isTimeframeValid(_ timeframe: Timeframe, for period: PortfolioPeriod) -> Bool {
        return validTimeframes(for: period).contains(timeframe)
    }
    
    var body: some View {
        NavigationView {
            List {
                
                // MARK: - Default Settings Section
                Section {
                    Picker("Period", selection: $tempDefaultPeriod) {
                        ForEach(PortfolioPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .onChange(of: tempDefaultPeriod) { _, newPeriod in
                        // Validar y ajustar el timeframe cuando cambia el período
                        let validTimeframes = validTimeframes(for: newPeriod)
                        if !validTimeframes.contains(tempDefaultTimeframe) {
                            tempDefaultTimeframe = validTimeframes.first ?? .oneDay
                        }
                    }
                    
                    Picker("Granularity", selection: $tempDefaultTimeframe) {
                        ForEach(validTimeframes(for: tempDefaultPeriod), id: \.self) { timeframe in
                            Text(timeframe.displayName).tag(timeframe)
                        }
                    }
                    .disabled(validTimeframes(for: tempDefaultPeriod).count <= 1)
                } header: {
                    Text("Default settings")
                }
                
                // MARK: - Account Settings Section
                Section {
                    Toggle("Show Total Accounts", isOn: $tempShowTotalAccounts)
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("Shows a virtual account that sums the balance of all real accounts.")
                }
                
                // MARK: - User Account Section
                if authService.isAuthenticated {
                    Section {
                        if let user = authService.currentUser {
                            HStack {
                                Text("Email")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(user.email)
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        Button("Change Password") {
                            showingChangePassword = true
                        }
                    } header: {
                        Text("Account")
                    }
                    
                    // API Credentials and Registration Information Sections
                    if let account = accountManager.realAccounts.first {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("API Key:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(repeating: "•", count: 20))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Text("Secret Key:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(repeating: "•", count: 20))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            
                            Button("Edit API Credentials") {
                                showingEditCredentials = true
                            }
                        } header: {
                            Text("API Credentials")
                        }
                        
                        // Registration Information Section
                        Section {
                            InfoRow(label: "Account Label", value: account.name)
                            InfoRow(label: "Live Trading", value: account.isLiveTrading ? "Yes" : "No")
                            
                            if let firstTradeDate = account.firstTradeDate {
                                InfoRow(label: "First Trade Date", value: DateFormatter.shortDate.string(from: firstTradeDate))
                            }
                            
                            if let leverage = account.leverage {
                                InfoRow(label: "Leverage", value: String(format: "%.1fx", leverage))
                            }
                            
                            if let budget = account.budget {
                                InfoRow(label: "Budget Allocation", value: "\(budget)%")
                            }
                            
                            InfoRow(label: "Can Close All Positions", value: (account.canCloseAllPositions ?? false) ? "Yes" : "No")
                            InfoRow(label: "Can Disconnect From Grecia", value: (account.canDisconnectFromGrecia ?? false) ? "Yes" : "No")
                        } header: {
                            Text("Registration Information")
                        }
                    }
                }
                
                // MARK: - Reset Section
                Section {
                    Button("Reset settings") {
                        settingsManager.resetAllSettings()
                        // Actualizar las variables temporales también
                        tempDefaultPeriod = settingsManager.appSettings.defaultPeriod
                        tempDefaultTimeframe = settingsManager.appSettings.defaultTimeframe
                        tempShowTotalAccounts = settingsManager.appSettings.showTotalAccounts
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("This will reset all settings to their default values.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onNavigateToAccounts?()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Aplicar los cambios temporales a la configuración real
                        settingsManager.updateDefaultPeriod(tempDefaultPeriod)
                        settingsManager.updateDefaultTimeframe(tempDefaultTimeframe)
                        
                        // Actualizar showTotalAccounts directamente
                        settingsManager.appSettings.showTotalAccounts = tempShowTotalAccounts
                        settingsManager.updateAppSettings(settingsManager.appSettings)
                        
                        onNavigateToAccounts?()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: settingsManager.appSettings.showTotalAccounts) { _, newValue in
            tempShowTotalAccounts = newValue
        }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView(accountManager: accountManager)
        }
        .sheet(isPresented: $showingEditCredentials) {
            EditCredentialsView(accountManager: accountManager)
        }
        .background(ColorCompatibility.appBackground())
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
}

// Helper struct para mostrar información en formato label:value
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

// Extension para formatear fechas ya existe en PerformanceView.swift

#Preview {
    iOSSettingsView(accountManager: AccountManager())
}
