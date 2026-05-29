//
//  CharacterViewModel.swift
//  RickAndMorty
//
//  Created by critter on 5/29/26.
//

import Foundation
import Combine

@MainActor
class CharacterViewModel: ObservableObject {
    @Published var characters: [Character] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchCharacters() async {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "https://rickandmortyapi.com/api/character") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(CharacterResponse.self, from: data)
            characters = decoded.results
        } catch {
            errorMessage = "Failed to load characters: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
