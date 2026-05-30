//
//  LoginView.swift
//  Authenticator
//
//  Created by critter on 5/30/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome")
                .font(.largeTitle)
                .bold()

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let error = authViewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }

            Button("Log In") {
                Task { await authViewModel.signIn(email: email, password: password) }
            }
            .buttonStyle(.borderedProminent)

            Button("Sign Up") {
                Task { await authViewModel.signUp(email: email, password: password) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
