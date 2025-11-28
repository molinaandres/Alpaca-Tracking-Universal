import Foundation

struct AlpacaAccount: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String?
    var alpacaAccountId: String?
    var apiKey: String
    var secretKey: String
    var isLiveTrading: Bool
    var createdAt: Date
    var isEncrypted: Bool
    var firstTradeDate: Date?
    
    // Nuevos campos de configuración (opcionales para migración)
    var leverage: Double?
    var budget: Int? // Porcentaje de 0 a 100 en saltos de 10
    var canCloseAllPositions: Bool?
    var canDisconnectFromGrecia: Bool?
    
    init(id: UUID = UUID(), name: String, description: String? = nil, alpacaAccountId: String? = nil, apiKey: String, secretKey: String, isLiveTrading: Bool, isEncrypted: Bool = false, firstTradeDate: Date? = nil, leverage: Double? = 1.0, budget: Int? = 100, canCloseAllPositions: Bool? = false, canDisconnectFromGrecia: Bool? = false) {
        self.id = id
        self.name = name
        self.description = description
        self.alpacaAccountId = alpacaAccountId
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.isLiveTrading = isLiveTrading
        self.createdAt = Date()
        self.isEncrypted = isEncrypted
        self.firstTradeDate = firstTradeDate
        self.leverage = leverage
        self.budget = budget
        self.canCloseAllPositions = canCloseAllPositions
        self.canDisconnectFromGrecia = canDisconnectFromGrecia
    }
    
    // MARK: - Encryption Methods
    
    /// Encripta las credenciales de la cuenta
    /// - Returns: Una nueva instancia con las credenciales encriptadas
    func encryptCredentials() -> AlpacaAccount {
        guard !isEncrypted else { return self }
        
        let encryptedApiKey = EncryptionService.encrypt(apiKey) ?? apiKey
        let encryptedSecretKey = EncryptionService.encrypt(secretKey) ?? secretKey
        
        return AlpacaAccount(
            id: id,
            name: name,
            description: description,
            alpacaAccountId: alpacaAccountId,
            apiKey: encryptedApiKey,
            secretKey: encryptedSecretKey,
            isLiveTrading: isLiveTrading,
            isEncrypted: true,
            firstTradeDate: firstTradeDate,
            leverage: leverage ?? 1.0,
            budget: budget ?? 100,
            canCloseAllPositions: canCloseAllPositions ?? false,
            canDisconnectFromGrecia: canDisconnectFromGrecia ?? false
        )
    }
    
    /// Desencripta las credenciales de la cuenta
    /// - Returns: Una nueva instancia con las credenciales desencriptadas
    func decryptCredentials() -> AlpacaAccount {
        guard isEncrypted else { return self }
        
        let decryptedApiKey = EncryptionService.decrypt(apiKey) ?? apiKey
        let decryptedSecretKey = EncryptionService.decrypt(secretKey) ?? secretKey
        
        return AlpacaAccount(
            id: id,
            name: name,
            description: description,
            alpacaAccountId: alpacaAccountId,
            apiKey: decryptedApiKey,
            secretKey: decryptedSecretKey,
            isLiveTrading: isLiveTrading,
            isEncrypted: false,
            firstTradeDate: firstTradeDate,
            leverage: leverage ?? 1.0,
            budget: budget ?? 100,
            canCloseAllPositions: canCloseAllPositions ?? false,
            canDisconnectFromGrecia: canDisconnectFromGrecia ?? false
        )
    }
    
    /// Obtiene las credenciales desencriptadas para uso en la API
    /// - Returns: Tupla con (apiKey, secretKey) desencriptadas
    func getDecryptedCredentials() -> (apiKey: String, secretKey: String) {
        if isEncrypted {
            let decryptedApiKey = EncryptionService.decrypt(apiKey) ?? apiKey
            let decryptedSecretKey = EncryptionService.decrypt(secretKey) ?? secretKey
            return (decryptedApiKey, decryptedSecretKey)
        } else {
            return (apiKey, secretKey)
        }
    }
}