import SwiftUI

struct FavoritesView: View {
    
    @EnvironmentObject var favorites: FavoritesViewModel
    
    var body: some View {
        NavigationStack {
            List {
                let favCities = favorites.cities.filter { $0.isFavorite }
                let favHobbies = favorites.hobbies.filter { $0.isFavorite }
                let favBooks = favorites.books.filter { $0.isFavorite }
                
                if favCities.isEmpty && favHobbies.isEmpty && favBooks.isEmpty {
                    Section {
                        Text("No favorites yet.")
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !favCities.isEmpty {
                    Section(header: Text("Cities")) {
                        ForEach(favCities) { city in
                            HStack {
                                Text(city.cityName)
                                Spacer()
                                Button(action: {
                                    favorites.toggleFavoriteCity(city: city)
                                }) {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
                
                if !favHobbies.isEmpty {
                    Section(header: Text("Hobbies")) {
                        ForEach(favHobbies) { hobby in
                            HStack {
                                Text(hobby.hobbyIcon)
                                Text(hobby.hobbyName)
                                Spacer()
                                Button(action: {
                                    favorites.toggleFavoriteHobby(hobby: hobby)
                                }) {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
                
                if !favBooks.isEmpty {
                    Section(header: Text("Books")) {
                        ForEach(favBooks) { book in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(book.bookTitle)
                                    Text(book.bookAuthor)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    favorites.toggleFavoriteBook(book: book)
                                }) {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
        }
    }
}

#Preview {
    FavoritesView()
        .environmentObject(FavoritesViewModel())
}
