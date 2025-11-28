import Foundation
import CryptoKit

#if os(macOS)
import IOKit
#elseif os(iOS)
import UIKit
#endif

/// Servicio para encriptar y desencriptar datos sensibles usando AES-GCM
class EncryptionService {
    
    // MARK: - Properties
    
    /// Clave de encriptación derivada del identificador del dispositivo
    private static var encryptionKey: SymmetricKey {
        // Usar el identificador único del dispositivo como base para la clave
        let deviceId = getDeviceIdentifier()
        let keyData = SHA256.hash(data: deviceId.data(using: .utf8) ?? Data())
        return SymmetricKey(data: keyData)
    }
    
    // MARK: - Public Methods
    
    /// Encripta un string usando AES-GCM
    /// - Parameter plaintext: El texto a encriptar
    /// - Returns: El texto encriptado en base64, o nil si falla
    static func encrypt(_ plaintext: String) -> String? {
        guard let data = plaintext.data(using: .utf8) else {
            return nil
        }
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
            return sealedBox.combined?.base64EncodedString()
        } catch {
            return nil
        }
    }
    
    /// Desencripta un string encriptado
    /// - Parameter encryptedText: El texto encriptado en base64
    /// - Returns: El texto desencriptado, o nil si falla
    static func decrypt(_ encryptedText: String) -> String? {
        guard let data = Data(base64Encoded: encryptedText),
              let sealedBox = try? AES.GCM.SealedBox(combined: data) else {
            return nil
        }
        
        do {
            let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    /// Verifica si un string está encriptado
    /// - Parameter text: El texto a verificar
    /// - Returns: true si el texto parece estar encriptado
    static func isEncrypted(_ text: String) -> Bool {
        // Un texto encriptado en base64 debería tener ciertas características
        guard let data = Data(base64Encoded: text) else {
            return false
        }
        
        // Verificar que tenga el tamaño mínimo esperado para AES-GCM
        // (al menos 12 bytes para el nonce + 16 bytes para el tag + datos)
        return data.count >= 28
    }
    
    // MARK: - Private Methods
    
    /// Obtiene un identificador único del dispositivo
    /// - Returns: Un string único para este dispositivo
    private static func getDeviceIdentifier() -> String {
        #if os(macOS)
        // En macOS, usar el identificador del hardware del sistema
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, 
                                                        IOServiceMatching("IOPlatformExpertDevice"))
        
        guard platformExpert != 0 else {
            // Fallback: usar un identificador basado en el sistema
            return "\(ProcessInfo.processInfo.hostName)-\(ProcessInfo.processInfo.processIdentifier)"
        }
        
        defer { IOObjectRelease(platformExpert) }
        
        guard let serialNumber = IORegistryEntryCreateCFProperty(platformExpert,
                                                               "IOPlatformSerialNumber" as CFString,
                                                               kCFAllocatorDefault,
                                                               0) else {
            // Fallback si no se puede obtener el serial
            return "\(ProcessInfo.processInfo.hostName)-\(ProcessInfo.processInfo.processIdentifier)"
        }
        
        return (serialNumber.takeRetainedValue() as? String) ?? 
               "\(ProcessInfo.processInfo.hostName)-\(ProcessInfo.processInfo.processIdentifier)"
        #elseif os(iOS)
        // En iOS, usar el identificador del dispositivo
        return UIDevice.current.identifierForVendor?.uuidString ?? 
               "\(ProcessInfo.processInfo.hostName)-\(ProcessInfo.processInfo.processIdentifier)"
        #else
        // Fallback para otras plataformas
        return "\(ProcessInfo.processInfo.hostName)-\(ProcessInfo.processInfo.processIdentifier)"
        #endif
    }
}

// MARK: - Extensions

extension EncryptionService {
    
    /// Encripta un array de strings
    /// - Parameter strings: Array de strings a encriptar
    /// - Returns: Array de strings encriptados
    static func encryptArray(_ strings: [String]) -> [String] {
        return strings.compactMap { encrypt($0) }
    }
    
    /// Desencripta un array de strings
    /// - Parameter encryptedStrings: Array de strings encriptados
    /// - Returns: Array de strings desencriptados
    static func decryptArray(_ encryptedStrings: [String]) -> [String] {
        return encryptedStrings.compactMap { decrypt($0) }
    }
}
