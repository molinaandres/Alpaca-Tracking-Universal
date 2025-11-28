import SwiftUI

struct EditCredentialsView: View {
    @StateObject private var authService = SupabaseAuthService.shared
    private let accountsService = SupabaseAccountsService.shared
    @ObservedObject var accountManager: AccountManager
    
    @State private var newApiKey = ""
    @State private var newSecretKey = ""
    @State private var confirmApiKey = ""
    @State private var confirmSecretKey = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    
    private var maskedApiKey: String {
        String(repeating: "•", count: 20)
    }
    
    private var maskedSecretKey: String {
        String(repeating: "•", count: 20)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Edit API Credentials")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.top, 20)
                    
                    VStack(spacing: 16) {
                        // Current API Key (masked)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(maskedApiKey)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Hidden")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            .padding(12)
                            .background(Color(uiColor: .systemBackground))
                            .cornerRadius(8)
                        }
                        
                        // New API Key
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            SecureField("Enter new API key", text: $newApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // Confirm New API Key
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm New API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            SecureField("Confirm new API key", text: $confirmApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Divider()
                        
                        // Current Secret Key (masked)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Secret Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(maskedSecretKey)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Hidden")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            .padding(12)
                            .background(Color(uiColor: .systemBackground))
                            .cornerRadius(8)
                        }
                        
                        // New Secret Key
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Secret Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            SecureField("Enter new secret key", text: $newSecretKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // Confirm New Secret Key
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm New Secret Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            SecureField("Confirm new secret key", text: $confirmSecretKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 4)
                        }
                        
                        if let successMessage = successMessage {
                            Text(successMessage)
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.top, 4)
                        }
                        
                        Button(action: handleUpdateCredentials) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Update Credentials")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isLoading || !isFormValid ? Color.gray : Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isLoading || !isFormValid)
                        
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Si no hay cuentas pero estamos autenticados, intentar cargarlas
                if accountManager.realAccounts.isEmpty && authService.isAuthenticated {
                    accountManager.loadAccountsAfterLogin()
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        // Si ambos campos están vacíos, no se puede actualizar
        if newApiKey.isEmpty && newSecretKey.isEmpty {
            return false
        }
        
        // Si se proporciona API key, debe coincidir con la confirmación
        if !newApiKey.isEmpty {
            guard newApiKey == confirmApiKey else { return false }
        }
        
        // Si se proporciona Secret key, debe coincidir con la confirmación
        if !newSecretKey.isEmpty {
            guard newSecretKey == confirmSecretKey else { return false }
        }
        
        return true
    }
    
    private func handleUpdateCredentials() {
        errorMessage = nil
        successMessage = nil
        isLoading = true
        
        // Obtener la primera cuenta (o la cuenta principal) - usar realAccounts para evitar cuentas virtuales
        guard let account = accountManager.realAccounts.first else {
            errorMessage = "No account found. Please add an account first."
            isLoading = false
            return
        }
        
        // Desencriptar las credenciales actuales para obtener los valores reales
        let decryptedAccount = account.decryptCredentials()
        let currentApiKey = decryptedAccount.apiKey
        let currentSecretKey = decryptedAccount.secretKey
        
        // Preparar los nuevos valores (usar los actuales si no se proporcionan nuevos)
        let updatedAccount = AlpacaAccount(
            id: account.id,
            name: account.name,
            description: account.description,
            alpacaAccountId: account.alpacaAccountId,
            apiKey: newApiKey.isEmpty ? currentApiKey : newApiKey,
            secretKey: newSecretKey.isEmpty ? currentSecretKey : newSecretKey,
            isLiveTrading: account.isLiveTrading,
            isEncrypted: false, // Se encriptará cuando se guarde
            firstTradeDate: account.firstTradeDate,
            leverage: account.leverage,
            budget: account.budget,
            canCloseAllPositions: account.canCloseAllPositions,
            canDisconnectFromGrecia: account.canDisconnectFromGrecia
        )
        
        accountsService.updateAccount(account: updatedAccount) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success:
                    successMessage = "Credentials updated successfully!"
                    // Recargar cuentas
                    accountManager.loadAccountsAfterLogin()
                    // Limpiar campos
                    newApiKey = ""
                    newSecretKey = ""
                    confirmApiKey = ""
                    confirmSecretKey = ""
                    // Cerrar después de un delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                    
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

