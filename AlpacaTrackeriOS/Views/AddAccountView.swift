import SwiftUI

struct AddAccountView: View {
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
                                Text(description.isEmpty ? "Will be obtained automatically" : description)
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
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveAccount()
                    }
                    .disabled(name.isEmpty || apiKey.isEmpty || secretKey.isEmpty)
                }
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
