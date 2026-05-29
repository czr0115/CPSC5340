//
// CategoryManager.swift : Favorites
//
// Copyright © 2025 Auburn University.
// All Rights Reserved.


import Foundation

class CategoryManager<T: Favoritable> {
    private let storageKey: String
    
    init(storageKey: String) {
        self.storageKey = storageKey
    }
    
    func toggleFavorite(items : inout [T], targetItem: T) {
        if let index = items.firstIndex(where: { $0.id == targetItem.id}) {
            items[index].isFavorite.toggle()
            let favoriteIds = items.filter({ $0.isFavorite }).map { $0.id }
            saveFavoriteIds(ids: favoriteIds)
        }
    }
    
    func saveFavoriteIds(ids : [Int]) {
        UserDefaults.standard.set(ids, forKey: storageKey)
    }
    
    func filteredItems(items: [T], searchText: String) -> [T] {
        if searchText.isEmpty {
            return items
        } else {
            return items.filter {
                $0.searchableText.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    func loadFavoriteIds() -> [Int] {
        return UserDefaults.standard.array(forKey: storageKey) as? [Int] ?? []
    }
    
    func initializeFavorites(items: [T]) -> [T] {
        let savedIds = loadFavoriteIds()
        return items.map { item in
            var updatedItem = item
            updatedItem.isFavorite = savedIds.contains(item.id)
            return updatedItem
        }
    }
    
    func clearFavorites(items: inout [T]) {
        for index in items.indices {
            items[index].isFavorite = false
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
