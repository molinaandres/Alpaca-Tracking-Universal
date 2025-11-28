import Foundation
import Combine

/// Servicio para gestionar cuentas Alpaca en Supabase
class SupabaseAccountsService {
    static let shared = SupabaseAccountsService()
    
    private let config = ConfigManager.shared
    private let authService = SupabaseAuthService.shared
    
    private init() {}
    
    // MARK: - Fetch Accounts
    
    func fetchAccounts(completion: @escaping (Result<[AlpacaAccount], AccountServiceError>) -> Void) {
        guard let userId = authService.getCurrentUserId(),
              let password = authService.currentPassword,
              let user = authService.currentUser else {
            completion(.failure(.notAuthenticated))
            return
        }
        
        // Llamar al login para obtener las credenciales actualizadas
        authService.login(email: user.email, password: password) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let authResponse):
                guard let credentials = authResponse.credentials,
                      let kdfSalt = authResponse.kdfSalt else {
                    completion(.failure(.noCredentials))
                    return
                }
                
                // Desencriptar credenciales y convertirlas a AlpacaAccount
                let accounts = credentials.compactMap { credential -> AlpacaAccount? in
                    guard let apiKey = EncryptionService.decryptWithPassword(
                        credential.encApiKey,
                        password: password,
                        salt: kdfSalt
                    ),
                    let secretKey = EncryptionService.decryptWithPassword(
                        credential.encSecretKey,
                        password: password,
                        salt: kdfSalt
                    ) else {
                        return nil
                    }
                    
                    // Convertir firstTradeDate de String a Date si existe
                    var firstTradeDate: Date? = nil
                    if let dateString = credential.firstTradeDate {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
                        firstTradeDate = formatter.date(from: dateString)
                    }
                    
                    return AlpacaAccount(
                        id: UUID(uuidString: credential.id) ?? UUID(),
                        name: credential.label,
                        description: nil,
                        alpacaAccountId: nil,
                        apiKey: apiKey,
                        secretKey: secretKey,
                        isLiveTrading: credential.isLiveTrading,
                        isEncrypted: false, // Ya están desencriptadas
                        firstTradeDate: firstTradeDate,
                        leverage: credential.leverage,
                        budget: credential.budget,
                        canCloseAllPositions: credential.canCloseAllPositions,
                        canDisconnectFromGrecia: credential.canDisconnectFromGrecia
                    )
                }
                
                completion(.success(accounts))
                
            case .failure(let error):
                completion(.failure(.authError(error.localizedDescription)))
            }
        }
    }
    
    // MARK: - Add Account
    
    func addAccount(
        account: AlpacaAccount,
        completion: @escaping (Result<Bool, AccountServiceError>) -> Void
    ) {
        guard let userId = authService.getCurrentUserId() else {
            completion(.failure(.notAuthenticated))
            return
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let firstTradeDateString = account.firstTradeDate.map { formatter.string(from: $0) }
        
        let request = AddCredentialRequest(
            userId: userId,
            apiKey: account.apiKey,
            secretKey: account.secretKey,
            label: account.name,
            isLiveTrading: account.isLiveTrading,
            firstTradeDate: firstTradeDateString,
            leverage: account.leverage,
            budget: account.budget,
            canCloseAllPositions: account.canCloseAllPositions,
            canDisconnectFromGrecia: account.canDisconnectFromGrecia
        )
        
        callEdgeFunction(request: request) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(true))
                } else {
                    completion(.failure(.serverError(response.message ?? "Failed to add account")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Update Account
    
    func updateAccount(
        account: AlpacaAccount,
        completion: @escaping (Result<Bool, AccountServiceError>) -> Void
    ) {
        guard let userId = authService.getCurrentUserId() else {
            completion(.failure(.notAuthenticated))
            return
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let firstTradeDateString = account.firstTradeDate.map { formatter.string(from: $0) }
        
        let request = UpdateCredentialRequest(
            userId: userId,
            credentialId: account.id.uuidString,
            apiKey: account.apiKey,
            secretKey: account.secretKey,
            label: account.name,
            isLiveTrading: account.isLiveTrading,
            firstTradeDate: firstTradeDateString,
            leverage: account.leverage,
            budget: account.budget,
            canCloseAllPositions: account.canCloseAllPositions,
            canDisconnectFromGrecia: account.canDisconnectFromGrecia
        )
        
        callEdgeFunction(request: request) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(true))
                } else {
                    completion(.failure(.serverError(response.message ?? "Failed to update account")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Delete Account
    
    func deleteAccount(
        accountId: UUID,
        completion: @escaping (Result<Bool, AccountServiceError>) -> Void
    ) {
        guard let userId = authService.getCurrentUserId() else {
            completion(.failure(.notAuthenticated))
            return
        }
        
        let request = DeleteCredentialRequest(
            userId: userId,
            credentialId: accountId.uuidString
        )
        
        callEdgeFunction(request: request) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(true))
                } else {
                    completion(.failure(.serverError(response.message ?? "Failed to delete account")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Edge Function Call
    
    private func callEdgeFunction<T: Codable>(
        request: T,
        completion: @escaping (Result<AuthResponse, AccountServiceError>) -> Void
    ) {
        guard let url = URL(string: config.edgeFunctionURL) else {
            completion(.failure(.invalidURL))
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue(config.supabaseAnonKey, forHTTPHeaderField: "Authorization")
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            completion(.failure(.encodingError))
            return
        }
        
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            
            guard let data = data else {
                completion(.failure(.noData))
                return
            }
            
            switch httpResponse.statusCode {
            case 200:
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let authResponse = try decoder.decode(AuthResponse.self, from: data)
                    completion(.success(authResponse))
                } catch {
                    completion(.failure(.decodingError(error.localizedDescription)))
                }
            case 401:
                completion(.failure(.notAuthenticated))
            case 500:
                completion(.failure(.serverError("Internal server error")))
            default:
                completion(.failure(.serverError("Unexpected status code: \(httpResponse.statusCode)")))
            }
        }.resume()
    }
}

// MARK: - Account Service Errors

enum AccountServiceError: LocalizedError {
    case invalidURL
    case encodingError
    case networkError(String)
    case invalidResponse
    case noData
    case decodingError(String)
    case notAuthenticated
    case noCredentials
    case authError(String)
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .encodingError:
            return "Error encoding request"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .noData:
            return "No data received"
        case .decodingError(let message):
            return "Error decoding response: \(message)"
        case .notAuthenticated:
            return "User not authenticated"
        case .noCredentials:
            return "No credentials found"
        case .authError(let message):
            return "Authentication error: \(message)"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

