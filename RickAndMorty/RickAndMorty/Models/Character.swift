//
//  Character.swift
//  RickAndMorty
//
//  Created by critter on 5/29/26.
//

import Foundation

// The API wraps everything in an object with a "results" array.
struct CharacterResponse: Codable {
    let results: [Character]
}

// One character. Identifiable lets us use it in List/ForEach.
struct Character: Codable, Identifiable {
    let id: Int
    let name: String
    let status: String      // "Alive", "Dead", or "unknown"
    let species: String
    let gender: String
    let image: String       // a URL string to the character's photo
    let origin: LocationInfo
    let location: LocationInfo
}

// origin and location are nested objects. We only need the name;
// Codable safely ignores the other keys (like "url").
struct LocationInfo: Codable {
    let name: String
}
