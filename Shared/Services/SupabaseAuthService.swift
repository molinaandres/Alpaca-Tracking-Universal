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
                    
                    // Guardar sesión y actualizar propiedades @Published en el main thread
                    DispatchQueue.main.async {
                        self.saveSession(user: user, password: password)
                        self.currentUser = user
                        self.currentPassword = password
                        self.isAuthenticated = true
                    }
                    
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
                    // Actualizar la contraseña guardada en el main thread
                    DispatchQueue.main.async {
                        self.currentPassword = newPassword
                    }
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
        urlRequest.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let encoder = JSONEncoder()
            // No usar convertToSnakeCase porque los CodingKeys ya definen los nombres correctos
            urlRequest.httpBody = try encoder.encode(request)
            
            // Log request for debugging
            if let requestData = urlRequest.httpBody,
               let requestString = String(data: requestData, encoding: .utf8) {
                print("📤 Request to: \(url)")
                print("📤 Request body: \(requestString)")
            }
        } catch {
            print("❌ Encoding error: \(error.localizedDescription)")
            completion(.failure(.encodingError))
            return
        }
        
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                completion(.failure(.invalidResponse))
                return
            }
            
            guard let data = data else {
                print("❌ No data received. Status code: \(httpResponse.statusCode)")
                completion(.failure(.noData))
                return
            }
            
            // Log response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("📡 Response status: \(httpResponse.statusCode)")
                print("📡 Response body: \(responseString)")
            }
            
            // Manejar diferentes códigos de estado
            switch httpResponse.statusCode {
            case 200:
                do {
                    let decoder = JSONDecoder()
                    // NO usar convertFromSnakeCase porque los CodingKeys ya están definidos explícitamente
                    let authResponse = try decoder.decode(AuthResponse.self, from: data)
                    print("✅ Login/Registration successful")
                    completion(.success(authResponse))
                } catch {
                    print("❌ Decoding error: \(error.localizedDescription)")
                    // Log el contenido completo para debug
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("❌ Response body that failed to decode: \(responseString)")
                    }
                    // Log el error detallado
                    if let decodingError = error as? DecodingError {
                        print("❌ Decoding error details: \(decodingError)")
                    }
                    completion(.failure(.decodingError(error.localizedDescription)))
                }
            case 401:
                // Intentar decodificar el mensaje de error del servidor
                do {
                    let decoder = JSONDecoder()
                    let authResponse = try decoder.decode(AuthResponse.self, from: data)
                    let errorMessage = authResponse.message ?? authResponse.error ?? "Invalid email or password"
                    print("❌ 401 Error: \(errorMessage)")
                    completion(.failure(.serverError(errorMessage)))
                } catch {
                    print("❌ 401 Error (could not decode): \(error.localizedDescription)")
                    completion(.failure(.invalidCredentials))
                }
            case 403:
                do {
                    let decoder = JSONDecoder()
                    let authResponse = try decoder.decode(AuthResponse.self, from: data)
                    if authResponse.status == "pending" {
                        print("⚠️ Account pending approval")
                        completion(.failure(.accountPending))
                    } else {
                        print("❌ Account rejected")
                        completion(.failure(.accountRejected))
                    }
                } catch {
                    print("⚠️ 403 Error (assuming pending): \(error.localizedDescription)")
                    completion(.failure(.accountPending))
                }
            case 409:
                print("❌ Email already exists")
                completion(.failure(.emailAlreadyExists))
            case 400:
                // Bad Request - intentar obtener el mensaje de error
                do {
                    // Intentar decodificar como AuthResponse primero
                    let decoder = JSONDecoder()
                    if let authResponse = try? decoder.decode(AuthResponse.self, from: data) {
                        let errorMessage = authResponse.message ?? authResponse.error ?? "Bad request"
                        print("❌ 400 Error: \(errorMessage)")
                        completion(.failure(.serverError(errorMessage)))
                    } else {
                        // Intentar decodificar como un objeto genérico de error
                        if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let errorMessage = errorDict["error"] as? String ?? 
                                             errorDict["message"] as? String ?? 
                                             "Bad request - Missing required fields"
                            print("❌ 400 Error: \(errorMessage)")
                            print("❌ Full error dict: \(errorDict)")
                            completion(.failure(.serverError(errorMessage)))
                        } else {
                            print("❌ 400 Error (could not decode): \(String(data: data, encoding: .utf8) ?? "unknown")")
                            completion(.failure(.serverError("Invalid request. Please check your input.")))
                        }
                    }
                } catch {
                    print("❌ 400 Error (decoding exception): \(error.localizedDescription)")
                    print("❌ Raw response: \(String(data: data, encoding: .utf8) ?? "unknown")")
                    completion(.failure(.serverError("Invalid request. Please check your input.")))
                }
            case 500:
                print("❌ Server error 500")
                completion(.failure(.serverError("Internal server error")))
            default:
                print("❌ Unexpected status code: \(httpResponse.statusCode)")
                // Intentar obtener el mensaje de error
                do {
                    let decoder = JSONDecoder()
                    let authResponse = try decoder.decode(AuthResponse.self, from: data)
                    let errorMessage = authResponse.message ?? authResponse.error ?? "Unexpected error"
                    completion(.failure(.serverError(errorMessage)))
                } catch {
                    completion(.failure(.serverError("Unexpected status code: \(httpResponse.statusCode)")))
                }
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

