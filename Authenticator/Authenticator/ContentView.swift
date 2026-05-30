//
//  ContentView.swift
//  Authenticator
//
//  Created by critter on 5/30/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some View {
        if authViewModel.user != nil {
            HomeView()
                .environmentObject(authViewModel)
        } else {
            LoginView()
                .environmentObject(authViewModel)
        }
    }
}

#Preview {
    ContentView()
}
