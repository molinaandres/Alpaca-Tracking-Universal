import Foundation

/// Representa una posición de trading en Alpaca
struct Position: Identifiable, Codable, Equatable {
    let assetId: String
    let symbol: String
    let exchange: String
    let assetClass: String
    let assetMarginable: Bool
    let qty: String
    let side: String
    let marketValue: String
    let costBasis: String
    let unrealizedPl: String
    let unrealizedPlpc: String
    let unrealizedIntradayPl: String
    let unrealizedIntradayPlpc: String
    let currentPrice: String
    let lastdayPrice: String
    let changeToday: String
    let avgEntryPrice: String
    
    // MARK: - Computed Properties
    
    /// ID único para Identifiable
    var id: String {
        return assetId
    }
    
    /// Cantidad como Double
    var quantity: Double {
        return Double(qty) ?? 0.0
    }
    
    /// Valor de mercado como Double
    var marketValueDouble: Double {
        return Double(marketValue) ?? 0.0
    }
    
    /// P&L no realizado como Double
    var unrealizedPLDouble: Double {
        return Double(unrealizedPl) ?? 0.0
    }
    
    /// Precio actual como Double
    var currentPriceDouble: Double {
        return Double(currentPrice) ?? 0.0
    }
    
    /// Indica si la posición tiene ganancias
    var isProfitable: Bool {
        return unrealizedPLDouble > 0
    }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case symbol
        case exchange
        case assetClass = "asset_class"
        case assetMarginable = "asset_marginable"
        case qty
        case side
        case marketValue = "market_value"
        case costBasis = "cost_basis"
        case unrealizedPl = "unrealized_pl"
        case unrealizedPlpc = "unrealized_plpc"
        case unrealizedIntradayPl = "unrealized_intraday_pl"
        case unrealizedIntradayPlpc = "unrealized_intraday_plpc"
        case currentPrice = "current_price"
        case lastdayPrice = "lastday_price"
        case changeToday = "change_today"
        case avgEntryPrice = "avg_entry_price"
    }
}
