import SwiftUI

struct ChangePasswordView: View {
    @StateObject private var authService = SupabaseAuthService.shared
    var accountManager: AccountManager?
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    
    init(accountManager: AccountManager? = nil) {
        self.accountManager = accountManager
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Change Password")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
                .padding(.top, 20)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Password")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SecureField("Enter current password", text: $currentPassword)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Password")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SecureField("Enter new password", text: $newPassword)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm New Password")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SecureField("Confirm new password", text: $confirmNewPassword)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
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
                
                Button(action: handleChangePassword) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Change Password")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isLoading || !isFormValid ? Color.gray : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isLoading || !isFormValid)
                .buttonStyle(PlainButtonStyle())
                
                Button("Cancel") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
            .frame(width: 400)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(width: 500, height: 500)
    }
    
    private var isFormValid: Bool {
        !currentPassword.isEmpty &&
        !newPassword.isEmpty &&
        newPassword == confirmNewPassword &&
        newPassword != currentPassword
    }
    
    private func handleChangePassword() {
        errorMessage = nil
        successMessage = nil
        isLoading = true
        
        authService.changePassword(oldPassword: currentPassword, newPassword: newPassword) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success:
                    successMessage = "Password changed successfully!"
                    // Recargar cuentas después de cambiar password para asegurar que todo esté sincronizado
                    accountManager?.loadAccountsAfterLogin()
                    // Limpiar campos
                    currentPassword = ""
                    newPassword = ""
                    confirmNewPassword = ""
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

