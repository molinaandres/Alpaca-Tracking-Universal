import Foundation

/// Manager para gestionar la configuración de Supabase
class ConfigManager {
    static let shared = ConfigManager()
    
    // MARK: - Supabase Configuration
    
    let supabaseURL: String
    let supabaseAnonKey: String
    let edgeFunctionURL: String
    
    private init() {
        // Configuración de Supabase
        self.supabaseURL = "https://nknsmzbnniupacyydhfy.supabase.co"
        self.supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5rbnNtemJubml1cGFjeXlkaGZ5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQzMjk1OTQsImV4cCI6MjA3OTkwNTU5NH0.5ESFkW8-2cLZdPR4bUsrShqx47k-ceAReepQQ44VxSM"
        self.edgeFunctionURL = "\(supabaseURL)/functions/v1/encrypt-decrypt-credentials"
    }
}

