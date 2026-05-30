//
//  AuthViewModel.swift
//  Authenticator
//
//  Created by critter on 5/30/26.
//

import Foundation
import Combine
import FirebaseAuth

@MainActor
class AuthViewModel: ObservableObject {
    @Published var user: User?           // the signed-in user; nil means logged out
    @Published var errorMessage: String?

    init() {
        // If someone's already signed in from last launch, restore that session
        user = Auth.auth().currentUser
    }

    func signUp(email: String, password: String) async {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            user = result.user
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            user = result.user
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            user = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
