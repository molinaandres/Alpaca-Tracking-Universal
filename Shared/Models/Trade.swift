import Foundation

/// Representa un trade ejecutado en Alpaca
struct Trade: Identifiable, Codable, Equatable {
    let id: String
    let symbol: String
    let exchange: String
    let assetClass: String
    let qty: String
    let side: String
    let orderType: String
    let type: String
    let status: String
    let filledQty: String
    let filledAvgPrice: String
    let filledAt: String
    let submittedAt: String
    let createdAt: String
    let updatedAt: String
    let legs: [TradeLeg]?
    let trailPrice: String?
    let trailPercent: String?
    let hwm: String?
    let limitPrice: String?
    let stopPrice: String?
    let extendedHours: Bool
    let notional: String?
    let orderId: String
    let clientOrderId: String?
    let assetId: String
    let assetStatus: String
    let assetMarginable: Bool
    let assetShortable: Bool
    let assetEasyToBorrow: Bool
    let assetFungible: Bool
    let assetTradable: Bool
    let assetFractionable: Bool
    let assetClassId: String
    
    // MARK: - Computed Properties
    
    /// Cantidad como Double
    var quantity: Double {
        return Double(qty) ?? 0.0
    }
    
    /// Cantidad ejecutada como Double
    var filledQuantity: Double {
        return Double(filledQty) ?? 0.0
    }
    
    /// Precio promedio de ejecución como Double
    var filledAveragePrice: Double {
        return Double(filledAvgPrice) ?? 0.0
    }
    
    /// Valor notional como Double
    var notionalValue: Double {
        return Double(notional ?? "0") ?? 0.0
    }
    
    /// Precio límite como Double
    var limitPriceDouble: Double {
        return Double(limitPrice ?? "0") ?? 0.0
    }
    
    /// Precio de stop como Double
    var stopPriceDouble: Double {
        return Double(stopPrice ?? "0") ?? 0.0
    }
    
    /// Precio de trail como Double
    var trailPriceDouble: Double {
        return Double(trailPrice ?? "0") ?? 0.0
    }
    
    /// Porcentaje de trail como Double
    var trailPercentDouble: Double {
        return Double(trailPercent ?? "0") ?? 0.0
    }
    
    /// High Water Mark como Double
    var hwmDouble: Double {
        return Double(hwm ?? "0") ?? 0.0
    }
    
    /// Indica si el trade es de compra
    var isBuy: Bool {
        return side.lowercased() == "buy"
    }
    
    /// Indica si el trade es de venta
    var isSell: Bool {
        return side.lowercased() == "sell"
    }
    
    /// Indica si el trade está completamente ejecutado
    var isFilled: Bool {
        return status.lowercased() == "filled"
    }
    
    /// Indica si el trade está parcialmente ejecutado
    var isPartiallyFilled: Bool {
        return status.lowercased() == "partially_filled"
    }
    
    /// Indica si el trade está cancelado
    var isCancelled: Bool {
        return status.lowercased() == "canceled"
    }
    
    /// Indica si el trade está pendiente
    var isPending: Bool {
        return status.lowercased() == "pending_new"
    }
    
    /// Indica si el trade está rechazado
    var isRejected: Bool {
        return status.lowercased() == "rejected"
    }
    
    /// Fecha de ejecución como Date
    var filledAtDate: Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: filledAt) ?? Date()
    }
    
    /// Fecha de envío como Date
    var submittedAtDate: Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: submittedAt) ?? Date()
    }
    
    /// Fecha de creación como Date
    var createdAtDate: Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: createdAt) ?? Date()
    }
    
    /// Fecha de actualización como Date
    var updatedAtDate: Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: updatedAt) ?? Date()
    }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case exchange
        case assetClass = "asset_class"
        case qty
        case side
        case orderType = "order_type"
        case type
        case status
        case filledQty = "filled_qty"
        case filledAvgPrice = "filled_avg_price"
        case filledAt = "filled_at"
        case submittedAt = "submitted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case legs
        case trailPrice = "trail_price"
        case trailPercent = "trail_percent"
        case hwm
        case limitPrice = "limit_price"
        case stopPrice = "stop_price"
        case extendedHours = "extended_hours"
        case notional
        case orderId = "order_id"
        case clientOrderId = "client_order_id"
        case assetId = "asset_id"
        case assetStatus = "asset_status"
        case assetMarginable = "asset_marginable"
        case assetShortable = "asset_shortable"
        case assetEasyToBorrow = "asset_easy_to_borrow"
        case assetFungible = "asset_fungible"
        case assetTradable = "asset_tradable"
        case assetFractionable = "asset_fractionable"
        case assetClassId = "asset_class_id"
    }
    
    // MARK: - Initializers
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        symbol = try container.decode(String.self, forKey: .symbol)
        exchange = try container.decode(String.self, forKey: .exchange)
        assetClass = try container.decode(String.self, forKey: .assetClass)
        qty = try container.decode(String.self, forKey: .qty)
        side = try container.decode(String.self, forKey: .side)
        orderType = try container.decode(String.self, forKey: .orderType)
        type = try container.decode(String.self, forKey: .type)
        status = try container.decode(String.self, forKey: .status)
        filledQty = try container.decode(String.self, forKey: .filledQty)
        filledAvgPrice = try container.decode(String.self, forKey: .filledAvgPrice)
        filledAt = try container.decode(String.self, forKey: .filledAt)
        submittedAt = try container.decode(String.self, forKey: .submittedAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        legs = try container.decodeIfPresent([TradeLeg].self, forKey: .legs)
        trailPrice = try container.decodeIfPresent(String.self, forKey: .trailPrice)
        trailPercent = try container.decodeIfPresent(String.self, forKey: .trailPercent)
        hwm = try container.decodeIfPresent(String.self, forKey: .hwm)
        limitPrice = try container.decodeIfPresent(String.self, forKey: .limitPrice)
        stopPrice = try container.decodeIfPresent(String.self, forKey: .stopPrice)
        extendedHours = try container.decode(Bool.self, forKey: .extendedHours)
        notional = try container.decodeIfPresent(String.self, forKey: .notional)
        orderId = try container.decode(String.self, forKey: .orderId)
        clientOrderId = try container.decodeIfPresent(String.self, forKey: .clientOrderId)
        assetId = try container.decode(String.self, forKey: .assetId)
        assetStatus = try container.decode(String.self, forKey: .assetStatus)
        assetMarginable = try container.decode(Bool.self, forKey: .assetMarginable)
        assetShortable = try container.decode(Bool.self, forKey: .assetShortable)
        assetEasyToBorrow = try container.decode(Bool.self, forKey: .assetEasyToBorrow)
        assetFungible = try container.decode(Bool.self, forKey: .assetFungible)
        assetTradable = try container.decode(Bool.self, forKey: .assetTradable)
        assetFractionable = try container.decode(Bool.self, forKey: .assetFractionable)
        assetClassId = try container.decode(String.self, forKey: .assetClassId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(exchange, forKey: .exchange)
        try container.encode(assetClass, forKey: .assetClass)
        try container.encode(qty, forKey: .qty)
        try container.encode(side, forKey: .side)
        try container.encode(orderType, forKey: .orderType)
        try container.encode(type, forKey: .type)
        try container.encode(status, forKey: .status)
        try container.encode(filledQty, forKey: .filledQty)
        try container.encode(filledAvgPrice, forKey: .filledAvgPrice)
        try container.encode(filledAt, forKey: .filledAt)
        try container.encode(submittedAt, forKey: .submittedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(legs, forKey: .legs)
        try container.encodeIfPresent(trailPrice, forKey: .trailPrice)
        try container.encodeIfPresent(trailPercent, forKey: .trailPercent)
        try container.encodeIfPresent(hwm, forKey: .hwm)
        try container.encodeIfPresent(limitPrice, forKey: .limitPrice)
        try container.encodeIfPresent(stopPrice, forKey: .stopPrice)
        try container.encode(extendedHours, forKey: .extendedHours)
        try container.encodeIfPresent(notional, forKey: .notional)
        try container.encode(orderId, forKey: .orderId)
        try container.encodeIfPresent(clientOrderId, forKey: .clientOrderId)
        try container.encode(assetId, forKey: .assetId)
        try container.encode(assetStatus, forKey: .assetStatus)
        try container.encode(assetMarginable, forKey: .assetMarginable)
        try container.encode(assetShortable, forKey: .assetShortable)
        try container.encode(assetEasyToBorrow, forKey: .assetEasyToBorrow)
        try container.encode(assetFungible, forKey: .assetFungible)
        try container.encode(assetTradable, forKey: .assetTradable)
        try container.encode(assetFractionable, forKey: .assetFractionable)
        try container.encode(assetClassId, forKey: .assetClassId)
    }
}

/// Representa una pierna de un trade complejo
struct TradeLeg: Codable, Equatable {
    let id: String
    let symbol: String
    let exchange: String
    let assetClass: String
    let qty: String
    let side: String
    let orderType: String
    let type: String
    let status: String
    let filledQty: String
    let filledAvgPrice: String
    let filledAt: String
    let submittedAt: String
    let createdAt: String
    let updatedAt: String
    let trailPrice: String?
    let trailPercent: String?
    let hwm: String?
    let limitPrice: String?
    let stopPrice: String?
    let extendedHours: Bool
    let notional: String?
    let orderId: String
    let clientOrderId: String?
    let assetId: String
    let assetStatus: String
    let assetMarginable: Bool
    let assetShortable: Bool
    let assetEasyToBorrow: Bool
    let assetFungible: Bool
    let assetTradable: Bool
    let assetFractionable: Bool
    let assetClassId: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case exchange
        case assetClass = "asset_class"
        case qty
        case side
        case orderType = "order_type"
        case type
        case status
        case filledQty = "filled_qty"
        case filledAvgPrice = "filled_avg_price"
        case filledAt = "filled_at"
        case submittedAt = "submitted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case trailPrice = "trail_price"
        case trailPercent = "trail_percent"
        case hwm
        case limitPrice = "limit_price"
        case stopPrice = "stop_price"
        case extendedHours = "extended_hours"
        case notional
        case orderId = "order_id"
        case clientOrderId = "client_order_id"
        case assetId = "asset_id"
        case assetStatus = "asset_status"
        case assetMarginable = "asset_marginable"
        case assetShortable = "asset_shortable"
        case assetEasyToBorrow = "asset_easy_to_borrow"
        case assetFungible = "asset_fungible"
        case assetTradable = "asset_tradable"
        case assetFractionable = "asset_fractionable"
        case assetClassId = "asset_class_id"
    }
}
