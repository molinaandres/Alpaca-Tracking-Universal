import Foundation

// MARK: - Account Activity Models

struct AccountActivity: Codable, Identifiable {
    let id: String
    let activityType: String
    let date: String?
    let createdAt: String?
    let netAmount: String?
    let description: String?
    let qty: String?
    let perShareAmount: String?
    let side: String?
    let symbol: String?
    let leavesQty: String?
    let orderId: String?
    let cumQty: String?
    let orderStatus: String?
    let orderType: String?
    let price: String?
    let stopPrice: String?
    let timeInForce: String?
    let legs: [ActivityLeg]?
    let executionId: String?
    let orderLegs: [OrderLeg]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case activityType = "activity_type"
        case date
        case createdAt = "created_at"
        case netAmount = "net_amount"
        case description
        case qty
        case perShareAmount = "per_share_amount"
        case side
        case symbol
        case leavesQty = "leaves_qty"
        case orderId = "order_id"
        case cumQty = "cum_qty"
        case orderStatus = "order_status"
        case orderType = "order_type"
        case price
        case stopPrice = "stop_price"
        case timeInForce = "time_in_force"
        case legs
        case executionId = "execution_id"
        case orderLegs = "order_legs"
    }
}

struct ActivityLeg: Codable {
    let id: String
    let instrumentType: String
    let instrument: String
    let qty: String
    let side: String
    let symbol: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case instrumentType = "instrument_type"
        case instrument
        case qty
        case side
        case symbol
    }
}

struct OrderLeg: Codable {
    let id: String
    let instrumentType: String
    let instrument: String
    let qty: String
    let side: String
    let symbol: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case instrumentType = "instrument_type"
        case instrument
        case qty
        case side
        case symbol
    }
}

// MARK: - Account Activities Response

struct AccountActivitiesResponse: Codable {
    let activities: [AccountActivity]
    let nextPageToken: String?
    
    enum CodingKeys: String, CodingKey {
        case activities
        case nextPageToken = "next_page_token"
    }
}

// MARK: - First Trade Info

struct FirstTradeInfo: Codable {
    let accountName: String
    let accountId: String
    let firstTradeDate: Date
    let firstTradeSymbol: String?
    let firstTradeSide: String?
    let firstTradeQty: String?
    let firstTradePrice: String?
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: firstTradeDate)
    }
}
