//
//  HomeView.swift
//  Authenticator
//
//  Created by critter on 5/30/26.
//

import SwiftUI
import FirebaseAuth

struct HomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("You're logged in!")
                    .font(.title)
                    .bold()

                if let email = authViewModel.user?.email {
                    Text(email)
                        .foregroundStyle(.secondary)
                }

                Button("Log Out") {
                    authViewModel.signOut()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthViewModel())
}
