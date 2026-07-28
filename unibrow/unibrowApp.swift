//
//  unibrowApp.swift
//  unibrow
//
//  Created by Joey Scarim on 7/27/26.
//

import SwiftUI

@main
struct unibrowApp: App {
    
    @StateObject private var smbStore = SMBStore()
     @StateObject private var savedConnectionsStore = SavedConnectionsStore()

     var body: some Scene {
         WindowGroup {
             ContentView()
                 .environmentObject(smbStore)
                 .environmentObject(savedConnectionsStore)
         }
     }
    
   
}
