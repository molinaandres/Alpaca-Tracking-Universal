import SwiftUI

struct EditAccountView: View {
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
        NavigationView {
            VStack(spacing: 0) {
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
                                Text(description.isEmpty ? "Not available" : description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(ColorCompatibility.systemBackground())
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
                        .background(ColorCompatibility.systemBackground())
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
                            .background(ColorCompatibility.systemBackground())
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
                        .background(ColorCompatibility.systemBackground())
                        .cornerRadius(12)
                        
                        // Botones de Acción (ocultos temporalmente)
                        if false {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Account Actions")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                HStack(spacing: 12) {
                                    Button("Close All Positions") {
                                        showingCloseAllConfirmation = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)

                                    Button("Disconnect From Grecia") {
                                        showingDisconnectConfirmation = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding()
                            .background(ColorCompatibility.systemBackground())
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save Changes") {
                        saveAccount()
                        // Forzar refresco de la lista y tarjeta
                        DispatchQueue.main.async {
                            accountManager.objectWillChange.send()
                        }
                    }
                    .disabled(name.isEmpty || apiKey.isEmpty || secretKey.isEmpty)
                }
            }
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
