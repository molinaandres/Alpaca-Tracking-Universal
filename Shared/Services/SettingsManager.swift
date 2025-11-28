import Foundation
import SwiftUI

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var appSettings: AppSettings
    @Published var accounts: [AccountConfiguration]
    
    private let userDefaults = UserDefaults.standard
    private let accountsKey = "SavedAccounts"
    private let settingsKey = "AppSettings"
    
    private init() {
        self.appSettings = Self.loadAppSettings()
        self.accounts = Self.loadAccounts()
    }
    
    // MARK: - App Settings Management
    func updateAppSettings(_ newSettings: AppSettings) {
        appSettings = newSettings
        saveAppSettings()
    }
    
    func updateSelectedAccount(_ accountId: String?) {
        appSettings.selectedAccountId = accountId
        saveAppSettings()
    }
    
    func updateDefaultPeriod(_ period: PortfolioPeriod) {
        appSettings.defaultPeriod = period
        saveAppSettings()
    }
    
    func updateDefaultTimeframe(_ timeframe: Timeframe) {
        appSettings.defaultTimeframe = timeframe
        saveAppSettings()
    }

    // MARK: - TWR per-account persistence
    func setShowTWR(_ show: Bool, for accountId: String) {
        appSettings.twrPerAccount[accountId] = show
        saveAppSettings()
    }

    func showTWR(for accountId: String) -> Bool {
        return appSettings.twrPerAccount[accountId] ?? false
    }
    
    // Persist custom accounts order
    func updateAccountsOrder(_ orderedIds: [String]) {
        appSettings.accountsOrder = orderedIds
        saveAppSettings()
    }

    // Apply ordering to a given accounts array of AlpacaAccount
    func ordered(_ accounts: [AlpacaAccount]) -> [AlpacaAccount] {
        if appSettings.accountsOrder.isEmpty { return accounts }
        let idToAccount = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id.uuidString, $0) })
        var result: [AlpacaAccount] = []
        // First, known ids in saved order
        for id in appSettings.accountsOrder {
            if let acc = idToAccount[id] { result.append(acc) }
        }
        // Then, any new accounts not present in saved order
        let remaining = accounts.filter { !appSettings.accountsOrder.contains($0.id.uuidString) }
        result.append(contentsOf: remaining)
        return result
    }

    
    // MARK: - Account Management
    func addAccount(_ account: AccountConfiguration) {
        accounts.append(account)
        saveAccounts()
    }
    
    func updateAccount(_ account: AccountConfiguration) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            saveAccounts()
        }
    }
    
    func deleteAccount(_ accountId: String) {
        accounts.removeAll { $0.id == accountId }
        
        // Si eliminamos la cuenta seleccionada, seleccionar la primera disponible
        if appSettings.selectedAccountId == accountId {
            appSettings.selectedAccountId = accounts.first?.id
            saveAppSettings()
        }
        
        saveAccounts()
    }
    
    func setDefaultAccount(_ accountId: String) {
        // Quitar el flag de default de todas las cuentas
        for i in 0..<accounts.count {
            accounts[i] = AccountConfiguration(
                name: accounts[i].name,
                apiKey: accounts[i].apiKey,
                secretKey: accounts[i].secretKey,
                isLive: accounts[i].isLive,
                isDefault: false
            )
        }
        
        // Marcar la cuenta seleccionada como default
        if let index = accounts.firstIndex(where: { $0.id == accountId }) {
            accounts[index] = AccountConfiguration(
                name: accounts[index].name,
                apiKey: accounts[index].apiKey,
                secretKey: accounts[index].secretKey,
                isLive: accounts[index].isLive,
                isDefault: true
            )
        }
        
        saveAccounts()
    }
    
    func getSelectedAccount() -> AccountConfiguration? {
        guard let selectedId = appSettings.selectedAccountId else { return nil }
        return accounts.first { $0.id == selectedId }
    }
    
    func getDefaultAccount() -> AccountConfiguration? {
        return accounts.first { $0.isDefault }
    }
    
    // MARK: - Persistence
    private func saveAppSettings() {
        if let encoded = try? JSONEncoder().encode(appSettings) {
            userDefaults.set(encoded, forKey: settingsKey)
        }
    }
    
    private func saveAccounts() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            userDefaults.set(encoded, forKey: accountsKey)
        }
    }
    
    private static func loadAppSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "AppSettings"),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }
    
    private static func loadAccounts() -> [AccountConfiguration] {
        guard let data = UserDefaults.standard.data(forKey: "SavedAccounts"),
              let accounts = try? JSONDecoder().decode([AccountConfiguration].self, from: data) else {
            return []
        }
        return accounts
    }
    
    // MARK: - Reset
    func resetAllSettings() {
        appSettings = AppSettings()
        accounts = []
        userDefaults.removeObject(forKey: settingsKey)
        userDefaults.removeObject(forKey: accountsKey)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    
    // Variables temporales para los cambios
    @State private var tempDefaultPeriod: PortfolioPeriod
    @State private var tempDefaultTimeframe: Timeframe
    @State private var tempShowTotalAccounts: Bool
    
    init() {
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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
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
            .background(ColorCompatibility.systemBackground())
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 2) {
                    // MARK: - Default Settings Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default settings")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Period")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Granularity")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Granularity", selection: $tempDefaultTimeframe) {
                                ForEach(validTimeframes(for: tempDefaultPeriod), id: \.self) { timeframe in
                                    Text(timeframe.displayName).tag(timeframe)
                                }
                            }
                            .disabled(validTimeframes(for: tempDefaultPeriod).count <= 1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ColorCompatibility.systemBackground())
                    .cornerRadius(12)
                    
                    // MARK: - Account Settings Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accounts")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            Toggle("Show Total Accounts", isOn: $tempShowTotalAccounts)
                            Spacer()
                        }
                        
                        Text("Shows a virtual account that sums the balance of all real accounts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ColorCompatibility.systemBackground())
                    .cornerRadius(12)
                    
                    // MARK: - Reset Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Advanced")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            Button("Reset Settings") {
                                settingsManager.resetAllSettings()
                                // Actualizar las variables temporales también
                                tempDefaultPeriod = settingsManager.appSettings.defaultPeriod
                                tempDefaultTimeframe = settingsManager.appSettings.defaultTimeframe
                                tempShowTotalAccounts = settingsManager.appSettings.showTotalAccounts
                            }
                            .foregroundColor(.red)
                            
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ColorCompatibility.systemBackground())
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
                    // Aplicar los cambios temporales a la configuración real
                    settingsManager.updateDefaultPeriod(tempDefaultPeriod)
                    settingsManager.updateDefaultTimeframe(tempDefaultTimeframe)
                    
                    // Actualizar showTotalAccounts directamente
                    settingsManager.appSettings.showTotalAccounts = tempShowTotalAccounts
                    settingsManager.updateAppSettings(settingsManager.appSettings)
                    
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .background(ColorCompatibility.systemBackground())
    }
    
}

