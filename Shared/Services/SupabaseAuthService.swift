import Foundation
import Combine

/// Servicio para manejar autenticación con Supabase
class SupabaseAuthService: ObservableObject {
    static let shared = SupabaseAuthService()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var currentPassword: String? // Guardado temporalmente para desencriptar credenciales
    
    private let config = ConfigManager.shared
    private let userDefaults = UserDefaults.standard
    private let userIdKey = "supabase_user_id"
    private let userEmailKey = "supabase_user_email"
    private let sessionKey = "supabase_session"
    
    private init() {
        // No establecer isAuthenticated = true automáticamente
        // El usuario debe hacer login explícitamente para obtener la contraseña
        // y desencriptar las credenciales
        isAuthenticated = false
        currentUser = nil
        currentPassword = nil
        
        // Limpiar cualquier sesión guardada anterior
        // porque necesitamos la contraseña para desencriptar credenciales
        clearSession()
    }
    
    // MARK: - Registration
    
    func register(
        email: String,
        password: String,
        apiKey: String,
        secretKey: String,
        isLiveTrading: Bool,
        label: String?,
        firstTradeDate: String? = nil,
        leverage: Double? = nil,
        budget: Int? = nil,
        canCloseAllPositions: Bool? = nil,
        canDisconnectFromGrecia: Bool? = nil,
        completion: @escaping (Result<AuthResponse, AuthError>) -> Void
    ) {
        let request = RegisterRequest(
            email: email,
            password: password,
            apiKey: apiKey,
            secretKey: secretKey,
            isLiveTrading: isLiveTrading,
            label: label,
            firstTradeDate: firstTradeDate,
            leverage: leverage,
            budget: budget,
            canCloseAllPositions: canCloseAllPositions,
            canDisconnectFromGrecia: canDisconnectFromGrecia
        )
        
        callEdgeFunction(request: request) { [weak self] result in
            switch result {
            case .success(let response):
                if response.success {
                    // Registro exitoso, pero el usuario está pendiente de aprobación
                    completion(.success(response))
                } else {
                    let error = AuthError.serverError(response.message ?? "Registration failed")
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Login
    
    func login(
        email: String,
        password: String,
        completion: @escaping (Result<AuthResponse, AuthError>) -> Void
    ) {
        let request = LoginRequest(email: email, password: password)
        
        callEdgeFunction(request: request) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                if response.success, let userResponse = response.user, let kdfSalt = response.kdfSalt {
                    // Login exitoso
                    let user = User(
                        id: userResponse.id,
                        email: userResponse.email,
                        status: UserStatus(rawValue: userResponse.status) ?? .pending,
                        kdfSalt: kdfSalt,
                        createdAt: nil,
                        lastLoginAt: Date()
                    )
                    
                    // Guardar sesión
                    self.saveSession(user: user, password: password)
                    self.currentUser = user
                    self.currentPassword = password
                    self.isAuthenticated = true
                    
                    completion(.success(response))
                } else {
                    // Error en login
                    let errorMessage = response.message ?? response.error ?? "Login failed"
                    let status = response.status
                    
                    if status == "pending" {
                        completion(.failure(.accountPending))
                    } else if status == "rejected" {
                        completion(.failure(.accountRejected))
                    } else {
                        completion(.failure(.invalidCredentials))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Change Password
    
    func changePassword(
        oldPassword: String,
        newPassword: String,
        completion: @escaping (Result<Bool, AuthError>) -> Void
    ) {
        guard let userId = currentUser?.id else {
            completion(.failure(.notAuthenticated))
            return
        }
        
        let request = ChangePasswordRequest(
            userId: userId,
            oldPassword: oldPassword,
            newPassword: newPassword
        )
        
        callEdgeFunction(request: request) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                if response.success {
                    // Actualizar la contraseña guardada
                    self.currentPassword = newPassword
                    completion(.success(true))
                } else {
                    let error = AuthError.serverError(response.message ?? "Password change failed")
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Logout
    
    func logout() {
        currentUser = nil
        currentPassword = nil
        isAuthenticated = false
        clearSession()
    }
    
    // MARK: - Session Management
    
    private func saveSession(user: User, password: String) {
        userDefaults.set(user.id, forKey: userIdKey)
        userDefaults.set(user.email, forKey: userEmailKey)
        userDefaults.set(true, forKey: sessionKey)
    }
    
    private func clearSession() {
        userDefaults.removeObject(forKey: userIdKey)
        userDefaults.removeObject(forKey: userEmailKey)
        userDefaults.removeObject(forKey: sessionKey)
    }
    
    func getCurrentUserId() -> String? {
        return currentUser?.id
    }
    
    // MARK: - Edge Function Call
    
    private func callEdgeFunction<T: Codable>(
        request: T,
        completion: @escaping (Result<AuthResponse, AuthError>) -> Void
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
            
            // Manejar diferentes códigos de estado
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
                completion(.failure(.invalidCredentials))
            case 403:
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let authResponse = try decoder.decode(AuthResponse.self, from: data)
                    if authResponse.status == "pending" {
                        completion(.failure(.accountPending))
                    } else {
                        completion(.failure(.accountRejected))
                    }
                } catch {
                    completion(.failure(.accountPending))
                }
            case 409:
                completion(.failure(.emailAlreadyExists))
            case 500:
                completion(.failure(.serverError("Internal server error")))
            default:
                completion(.failure(.serverError("Unexpected status code: \(httpResponse.statusCode)")))
            }
        }.resume()
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidURL
    case encodingError
    case networkError(String)
    case invalidResponse
    case noData
    case decodingError(String)
    case invalidCredentials
    case accountPending
    case accountRejected
    case emailAlreadyExists
    case serverError(String)
    case notAuthenticated
    
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
        case .invalidCredentials:
            return "Invalid email or password"
        case .accountPending:
            return "Account pending approval"
        case .accountRejected:
            return "Account has been rejected"
        case .emailAlreadyExists:
            return "Email already registered"
        case .serverError(let message):
            return "Server error: \(message)"
        case .notAuthenticated:
            return "User not authenticated"
        }
    }
}

