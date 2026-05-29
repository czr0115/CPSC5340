//
//  CharacterDetailView.swift
//  RickAndMorty
//
//  Created by critter on 5/29/26.
//

import SwiftUI

struct CharacterDetailView: View {
    let character: Character

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AsyncImage(url: URL(string: character.image)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(character.name)
                    .font(.title)
                    .bold()

                VStack(alignment: .leading, spacing: 12) {
                    detailRow(label: "Status", value: character.status)
                    detailRow(label: "Species", value: character.species)
                    detailRow(label: "Gender", value: character.gender)
                    detailRow(label: "Origin", value: character.origin.name)
                    detailRow(label: "Last Known Location", value: character.location.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // Small reusable helper for a labeled field
    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

#Preview {
    NavigationStack {
        CharacterDetailView(character: Character(
            id: 1,
            name: "Rick Sanchez",
            status: "Alive",
            species: "Human",
            gender: "Male",
            image: "https://rickandmortyapi.com/api/character/avatar/1.jpeg",
            origin: LocationInfo(name: "Earth (C-137)"),
            location: LocationInfo(name: "Earth (Replacement Dimension)")
        ))
    }
}
