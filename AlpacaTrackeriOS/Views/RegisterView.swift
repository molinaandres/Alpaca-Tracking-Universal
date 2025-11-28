import SwiftUI

struct RegisterView: View {
    @ObservedObject var accountManager: AccountManager
    @Binding var showingRegister: Bool
    
    @StateObject private var authService = SupabaseAuthService.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var apiKey = ""
    @State private var secretKey = ""
    @State private var isLiveTrading = false
    @State private var label: String = ""
    @State private var firstTradeDate = Date()
    @State private var leverage: Double = 1.0
    @State private var budget: Int = 100
    @State private var canCloseAllPositions = false
    @State private var canDisconnectFromGrecia = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Create Account")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Your account will be pending approval")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter your password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        SecureField("Confirm your password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alpaca API Key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter your Alpaca API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alpaca Secret Key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter your Alpaca secret key", text: $secretKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account Label (Optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., Main Account", text: $label)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Toggle("Live Trading", isOn: $isLiveTrading)
                        .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("First Trade Date")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        DatePicker("Select first trade date", selection: $firstTradeDate, displayedComponents: .date)
                            .datePickerStyle(CompactDatePickerStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Leverage")
                            .font(.subheadline)
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
                            .font(.subheadline)
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
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Can Close All Positions", isOn: $canCloseAllPositions)
                        Toggle("Can Disconnect From Grecia", isOn: $canDisconnectFromGrecia)
                    }
                    .padding(.vertical, 8)
                    
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
                    
                    Button(action: handleRegister) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Sign Up")
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
                    
                    Button("Back to Sign In") {
                        showingRegister = false
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
    
    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        password == confirmPassword &&
        !apiKey.isEmpty &&
        !secretKey.isEmpty &&
        email.contains("@")
    }
    
    private func handleRegister() {
        errorMessage = nil
        successMessage = nil
        isLoading = true
        
        let accountLabel = label.isEmpty ? nil : label
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let firstTradeDateString = formatter.string(from: firstTradeDate)
        
        authService.register(
            email: email,
            password: password,
            apiKey: apiKey,
            secretKey: secretKey,
            isLiveTrading: isLiveTrading,
            label: accountLabel,
            firstTradeDate: firstTradeDateString,
            leverage: leverage,
            budget: budget,
            canCloseAllPositions: canCloseAllPositions,
            canDisconnectFromGrecia: canDisconnectFromGrecia
        ) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success:
                    successMessage = "Registration successful! Your account is pending approval. You will be able to sign in once approved."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showingRegister = false
                    }
                    
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

