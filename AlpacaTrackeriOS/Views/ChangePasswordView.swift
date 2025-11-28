import SwiftUI

struct ChangePasswordView: View {
    @StateObject private var authService = SupabaseAuthService.shared
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
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
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Password")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            SecureField("Enter new password", text: $newPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm New Password")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            SecureField("Confirm new password", text: $confirmNewPassword)
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
        }
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
                    currentPassword = ""
                    newPassword = ""
                    confirmNewPassword = ""
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

