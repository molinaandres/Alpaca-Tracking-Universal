import Foundation

// Simular el servicio de encriptación (simplificado)
class SimpleEncryptionService {
    static func decrypt(_ encryptedString: String) -> String? {
        // Para este test, vamos a usar las credenciales directamente
        // En un entorno real, necesitarías la clave de encriptación
        return encryptedString
    }
}

// Estructura para la cuenta
struct AlpacaAccount: Codable {
    let id: String
    let name: String
    let apiKey: String
    let secretKey: String
    let isLiveTrading: Bool
    let isEncrypted: Bool
}

// Estructura para la respuesta de la API
struct PortfolioHistory: Codable {
    let timestamp: [Int]?
    let equity: [Double]?
    let profitLoss: [Double]?
    let profitLossPct: [Double]?
    let baseValue: [Double]?
    let timeFrame: String?
}

// Función para hacer la llamada a la API
func callAlpacaAPI(apiKey: String, secretKey: String, startDate: String, endDate: String) {
    let urlString = "https://api.alpaca.markets/v2/account/portfolio/history?start_date=\(startDate)&end_date=\(endDate)&timeframe=1D&extended_hours=true"
    
    guard let url = URL(string: urlString) else {
        print("❌ URL inválida")
        return
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(apiKey, forHTTPHeaderField: "APCA-API-KEY-ID")
    request.setValue(secretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    
    print("🔍 Llamando a la API de Alpaca...")
    print("   URL: \(urlString)")
    print("   Fecha inicio: \(startDate)")
    print("   Fecha fin: \(endDate)")
    
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("❌ Error de red: \(error.localizedDescription)")
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Respuesta inválida")
            return
        }
        
    
        
        if httpResponse.statusCode == 200 {
            guard let data = data else {
                print("❌ No hay datos en la respuesta")
                return
            }
            
            do {
                let portfolioHistory = try JSONDecoder().decode(PortfolioHistory.self, from: data)
                
                
                
                if let timestamps = portfolioHistory.timestamp,
                   let equities = portfolioHistory.equity {
                    
                    
                    for i in 0..<min(timestamps.count, equities.count) {
                        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestamps[i]))
                        let equity = equities[i]
                        
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        formatter.timeStyle = .none
                        
                        
                    }
                }
                
            } catch {
                
                if let data = data {
                    
                } else {
                    print("   No hay datos en la respuesta")
                }
            }
        } else {
            
            if let data = data {
                
            } else {
                print("   No hay datos en la respuesta")
            }
        }
    }
    
    task.resume()
}

// Leer las cuentas del archivo
let accountsPath = "/Users/charly/Documents/alpaca_accounts.json"
guard let data = FileManager.default.contents(atPath: accountsPath) else {
    print("❌ No se pudo leer el archivo de cuentas")
    exit(1)
}

do {
    let accounts = try JSONDecoder().decode([AlpacaAccount].self, from: data)
    
    // Buscar la cuenta "Nacho Tripero"
    guard let nachoAccount = accounts.first(where: { $0.name == "Nacho Tripero" }) else {
        print("❌ No se encontró la cuenta 'Nacho Tripero'")
        exit(1)
    }
    
    print("✅ Cuenta encontrada: \(nachoAccount.name)")
    print("   ID: \(nachoAccount.id)")
    print("   Live Trading: \(nachoAccount.isLiveTrading)")
    print("   Encriptada: \(nachoAccount.isEncrypted)")
    
    // Para este test, vamos a usar las credenciales tal como están
    // En un entorno real, necesitarías desencriptarlas
    let apiKey = nachoAccount.apiKey
    let secretKey = nachoAccount.secretKey
    
    // Fechas del 1 al 15 de julio de 2025
    let startDate = "2025-07-01T00:00:00Z"
    let endDate = "2025-07-15T23:59:59Z"
    
    callAlpacaAPI(apiKey: apiKey, secretKey: secretKey, startDate: startDate, endDate: endDate)
    
    // Mantener el programa ejecutándose para que la llamada asíncrona termine
    RunLoop.main.run()
    
} catch {
    print("❌ Error decodificando cuentas: \(error)")
    exit(1)
}
