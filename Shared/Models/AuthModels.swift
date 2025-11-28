import Foundation

// MARK: - User Model

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let status: UserStatus
    let kdfSalt: String
    let createdAt: Date?
    let lastLoginAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case status
        case kdfSalt = "kdf_salt"
        case createdAt = "created_at"
        case lastLoginAt = "last_login_at"
    }
}

enum UserStatus: String, Codable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
}

// MARK: - Request Models

struct LoginRequest: Codable {
    let action: String = "login"
    let email: String
    let password: String
}

struct RegisterRequest: Codable {
    let action: String = "register"
    let email: String
    let password: String
    let apiKey: String
    let secretKey: String
    let isLiveTrading: Bool
    let label: String?
    let firstTradeDate: String?
    let leverage: Double?
    let budget: Int?
    let canCloseAllPositions: Bool?
    let canDisconnectFromGrecia: Bool?
    
    enum CodingKeys: String, CodingKey {
        case action
        case email
        case password
        case apiKey = "apiKey"
        case secretKey = "secretKey"
        case isLiveTrading = "isLiveTrading"
        case label
        case firstTradeDate = "firstTradeDate"
        case leverage
        case budget
        case canCloseAllPositions = "canCloseAllPositions"
        case canDisconnectFromGrecia = "canDisconnectFromGrecia"
    }
}

struct ChangePasswordRequest: Codable {
    let action: String = "change_password"
    let userId: String
    let oldPassword: String
    let newPassword: String
    
    enum CodingKeys: String, CodingKey {
        case action
        case userId = "userId"
        case oldPassword = "oldPassword"
        case newPassword = "newPassword"
    }
}

// MARK: - Response Models

struct AuthResponse: Codable {
    let success: Bool
    let user: UserResponse?
    let credentials: [EncryptedCredential]?
    let kdfSalt: String?
    let message: String?
    let error: String?
    let status: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case user
        case credentials
        case kdfSalt = "kdf_salt"
        case message
        case error
        case status
    }
}

struct UserResponse: Codable {
    let id: String
    let email: String
    let status: String
}

struct EncryptedCredential: Codable, Identifiable {
    let id: String
    let label: String
    let encApiKey: String
    let encSecretKey: String
    let isLiveTrading: Bool
    let firstTradeDate: String?
    let leverage: Double?
    let budget: Int?
    let canCloseAllPositions: Bool
    let canDisconnectFromGrecia: Bool
    let kdfSalt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case label
        case encApiKey = "enc_api_key"
        case encSecretKey = "enc_secret_key"
        case isLiveTrading = "is_live_trading"
        case firstTradeDate = "first_trade_date"
        case leverage
        case budget
        case canCloseAllPositions = "can_close_all_positions"
        case canDisconnectFromGrecia = "can_disconnect_from_grecia"
        case kdfSalt = "kdf_salt"
    }
}

// MARK: - Account Management Requests

struct AddCredentialRequest: Codable {
    let action: String = "add_credential"
    let userId: String
    let apiKey: String
    let secretKey: String
    let label: String?
    let isLiveTrading: Bool
    let firstTradeDate: String?
    let leverage: Double?
    let budget: Int?
    let canCloseAllPositions: Bool?
    let canDisconnectFromGrecia: Bool?
    
    enum CodingKeys: String, CodingKey {
        case action
        case userId = "userId"
        case apiKey = "apiKey"
        case secretKey = "secretKey"
        case label
        case isLiveTrading = "isLiveTrading"
        case firstTradeDate = "firstTradeDate"
        case leverage
        case budget
        case canCloseAllPositions = "canCloseAllPositions"
        case canDisconnectFromGrecia = "canDisconnectFromGrecia"
    }
}

struct UpdateCredentialRequest: Codable {
    let action: String = "update_credential"
    let userId: String
    let credentialId: String
    let apiKey: String?
    let secretKey: String?
    let label: String?
    let isLiveTrading: Bool?
    let firstTradeDate: String?
    let leverage: Double?
    let budget: Int?
    let canCloseAllPositions: Bool?
    let canDisconnectFromGrecia: Bool?
    
    enum CodingKeys: String, CodingKey {
        case action
        case userId = "userId"
        case credentialId = "credentialId"
        case apiKey = "apiKey"
        case secretKey = "secretKey"
        case label
        case isLiveTrading = "isLiveTrading"
        case firstTradeDate = "firstTradeDate"
        case leverage
        case budget
        case canCloseAllPositions = "canCloseAllPositions"
        case canDisconnectFromGrecia = "canDisconnectFromGrecia"
    }
}

struct DeleteCredentialRequest: Codable {
    let action: String = "delete_credential"
    let userId: String
    let credentialId: String
    
    enum CodingKeys: String, CodingKey {
        case action
        case userId = "userId"
        case credentialId = "credentialId"
    }
}

