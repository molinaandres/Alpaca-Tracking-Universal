import Foundation

struct AccountBalance: Codable, Identifiable, Equatable {
    let id: UUID
    let accountId: UUID
    let balance: Double
    let lastUpdated: Date
    let accountInfo: AlpacaAPIAccount?
    let error: String?
    
    init(accountId: UUID, balance: Double, lastUpdated: Date = Date(), accountInfo: AlpacaAPIAccount? = nil, error: String? = nil) {
        self.id = UUID()
        self.accountId = accountId
        self.balance = balance
        self.lastUpdated = lastUpdated
        self.accountInfo = accountInfo
        self.error = error
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case balance
        case lastUpdated
        case accountInfo
        case error
    }
    
    var hasError: Bool {
        return error != nil
    }
    
    var formattedBalance: String {
        return String(format: "$%.2f", balance)
    }
    
    var formattedLastUpdate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: lastUpdated)
    }
}