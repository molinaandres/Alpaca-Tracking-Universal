import SwiftUI

struct MacOSSettingsView: View {
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
        // Inicializar con valores por defecto para evitar problemas de concurrencia
        _tempDefaultPeriod = State(initialValue: .oneMonth)
        _tempDefaultTimeframe = State(initialValue: .oneDay)
        _tempShowTotalAccounts = State(initialValue: false)
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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    onNavigateToAccounts?()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // MARK: - Default Settings Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default settings")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Period")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Picker("Period", selection: $tempDefaultPeriod) {
                                ForEach(PortfolioPeriod.allCases, id: \.self) { period in
                                    Text(period.displayName).tag(period)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: tempDefaultPeriod) { _, newPeriod in
                                // Validar y ajustar el timeframe cuando cambia el período
                                let validTimeframes = validTimeframes(for: newPeriod)
                                if !validTimeframes.contains(tempDefaultTimeframe) {
                                    tempDefaultTimeframe = validTimeframes.first ?? .oneDay
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Granularity")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Picker("Granularity", selection: $tempDefaultTimeframe) {
                                ForEach(validTimeframes(for: tempDefaultPeriod), id: \.self) { timeframe in
                                    Text(timeframe.displayName).tag(timeframe)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(validTimeframes(for: tempDefaultPeriod).count <= 1)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // MARK: - Account Settings Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accounts")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Checkbox(title: "Show Total Accounts", isChecked: $tempShowTotalAccounts)
                        
                        Text("Shows a virtual account that sums the balance of all real accounts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // MARK: - User Account Section
                    if SupabaseAuthService.shared.isAuthenticated {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Account")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            if let user = SupabaseAuthService.shared.currentUser {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Email")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(user.email)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            Divider()
                            
                            Button("Change Password") {
                                showingChangePassword = true
                            }
                            .foregroundColor(.accentColor)
                            
                            Divider()
                            
                            // API Credentials Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("API Credentials")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                // Mostrar credenciales enmascaradas
                                if let account = accountManager.realAccounts.first {
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
                                    .padding(8)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(6)
                                }
                                
                                Button("Edit API Credentials") {
                                    showingEditCredentials = true
                                }
                                .foregroundColor(.accentColor)
                            }
                            
                            Divider()
                            
                            // Registration Information Section
                            if let account = accountManager.realAccounts.first {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Registration Information")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    VStack(alignment: .leading, spacing: 8) {
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
                                    }
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // MARK: - Reset Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Advanced")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Button("Reset settings") {
                            resetSettings()
                        }
                        .foregroundColor(.red)
                        
                        Text("This will reset all settings to their default values.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 500, maxWidth: 600, minHeight: 400, maxHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView(accountManager: accountManager)
        }
        .sheet(isPresented: $showingEditCredentials) {
            EditCredentialsView(accountManager: accountManager)
        }
        .onAppear {
            loadSettings()
        }
    }
    
    private func saveSettings() {
        // Aplicar los cambios temporales a la configuración real
        settingsManager.updateDefaultPeriod(tempDefaultPeriod)
        settingsManager.updateDefaultTimeframe(tempDefaultTimeframe)
        
        // Actualizar showTotalAccounts directamente
        settingsManager.appSettings.showTotalAccounts = tempShowTotalAccounts
        settingsManager.updateAppSettings(settingsManager.appSettings)
        
        onNavigateToAccounts?()
    }
    
    private func loadSettings() {
        let settings = settingsManager.appSettings
        tempDefaultPeriod = settings.defaultPeriod
        tempDefaultTimeframe = settings.defaultTimeframe
        tempShowTotalAccounts = settings.showTotalAccounts
    }
    
    private func resetSettings() {
        settingsManager.resetAllSettings()
        // Actualizar las variables temporales también
        loadSettings()
    }
}

// Custom Checkbox component for macOS
struct Checkbox: View {
    let title: String
    @Binding var isChecked: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                isChecked.toggle()
            }) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? .accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(title)
                .font(.body)
        }
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
    MacOSSettingsView(accountManager: AccountManager())
}
