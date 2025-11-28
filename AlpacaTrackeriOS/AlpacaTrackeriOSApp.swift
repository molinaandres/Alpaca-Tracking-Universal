//
//  AlpacaTrackeriOSApp.swift
//  AlpacaTrackeriOS
//
//  Created by Andrés Molina on 12/9/25.
//

import SwiftUI

@main
struct AlpacaTrackeriOSApp: App {
    
    init() {
        // Suppress system debug messages
        #if DEBUG
        // Disable console logging for system messages
        setenv("OS_ACTIVITY_MODE", "disable", 1)
        setenv("SIMULATOR_LOGGING", "0", 1)
        setenv("SIMULATOR_DEBUG_LOGGING", "0", 1)
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
