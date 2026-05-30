//
//  AuthenticatorApp.swift
//  Authenticator
//
//  Created by critter on 5/30/26.
//

import SwiftUI
import FirebaseCore

@main
struct AuthenticatorApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
