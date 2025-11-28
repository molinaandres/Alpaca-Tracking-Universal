import Foundation
import CryptoKit

// Simular el servicio de encriptación
class EncryptionService {
    static func decrypt(_ encryptedString: String) -> String? {
        // Para este test, vamos a intentar decodificar base64
        guard let data = Data(base64Encoded: encryptedString) else {
            return nil
        }
        
        // Intentar decodificar como string
        if let decrypted = String(data: data, encoding: .utf8) {
            return decrypted
        }
        
        return nil
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
    
    // Intentar desencriptar las credenciales
    let decryptedApiKey = EncryptionService.decrypt(nachoAccount.apiKey) ?? nachoAccount.apiKey
    let decryptedSecretKey = EncryptionService.decrypt(nachoAccount.secretKey) ?? nachoAccount.secretKey
    
    print("\n🔑 Credenciales:")
    print("   API Key: \(decryptedApiKey)")
    print("   Secret Key: \(decryptedSecretKey)")
    
    // Hacer la llamada a la API
    let urlString = "https://api.alpaca.markets/v2/account/portfolio/history?start_date=2025-07-01T00:00:00Z&end_date=2025-07-15T23:59:59Z&timeframe=1D&extended_hours=true"
    
    guard let url = URL(string: urlString) else {
        print("❌ URL inválida")
        exit(1)
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(decryptedApiKey, forHTTPHeaderField: "APCA-API-KEY-ID")
    request.setValue(decryptedSecretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    
    print("\n🔍 Llamando a la API de Alpaca...")
    print("   URL: \(urlString)")
    print("   Fecha inicio: 2025-07-01T00:00:00Z")
    print("   Fecha fin: 2025-07-15T23:59:59Z")
    
    let semaphore = DispatchSemaphore(value: 0)
    
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        
        if let error = error {
            print("❌ Error de red: \(error.localizedDescription)")
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Respuesta inválida")
            return
        }
        
        print("📊 Status Code: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            guard let data = data else {
                print("❌ No hay datos en la respuesta")
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                print("✅ Datos recibidos:")
                print("   JSON: \(json)")
                
                // Intentar decodificar como PortfolioHistory
                if let portfolioData = try? JSONDecoder().decode(PortfolioHistory.self, from: data) {
                    
                    
                    if let timestamps = portfolioData.timestamp,
                       let equities = portfolioData.equity {
                        
                        
                        for i in 0..<min(timestamps.count, equities.count) {
                            let timestamp = Date(timeIntervalSince1970: TimeInterval(timestamps[i]))
                            let equity = equities[i]
                            
                            let formatter = DateFormatter()
                            formatter.dateStyle = .short
                            formatter.timeStyle = .none
                            
                            
                        }
                    }
                }
                
            } catch {
                
                if let data = data {
                    let responseString = String(data: data, encoding: .utf8) ?? "No se puede decodificar"
                    
                }
            }
        } else {
            
            if let data = data {
                
            }
        }
    }
    
    task.resume()
    semaphore.wait()
    
} catch {
    
    exit(1)
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
