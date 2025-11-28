import SwiftUI

struct LoginView: View {
    @StateObject private var authService = SupabaseAuthService.shared
    @ObservedObject var accountManager: AccountManager
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingRegister = false
    
    var body: some View {
        VStack(spacing: 0) {
            if showingRegister {
                RegisterView(accountManager: accountManager, showingRegister: $showingRegister)
            } else {
                loginContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var loginContent: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 8) {
                Text("Grecia Tracker")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Sign in to continue")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter your email", text: $email)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .disableAutocorrection(true)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SecureField("Enter your password", text: $password)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .onSubmit {
                            if !isLoading && !email.isEmpty && !password.isEmpty {
                                handleLogin()
                            }
                        }
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
                
                Button(action: handleLogin) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isLoading ? Color.gray : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .buttonStyle(PlainButtonStyle())
                
                HStack {
                    Text("Don't have an account?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Sign Up") {
                        showingRegister = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 8)
            }
            .frame(width: 400)
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func handleLogin() {
        errorMessage = nil
        isLoading = true
        
        authService.login(email: email, password: password) { [weak accountManager] result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success:
                    // Cargar cuentas desde Supabase
                    accountManager?.loadAccountsAfterLogin()
                    
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

