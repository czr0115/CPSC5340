//
//  ContentView.swift
//  EmojiCounter
//
//  Created by critter on 5/22/26.
//

import SwiftUI

struct EmojiItem: Identifiable {
    let id = UUID()
    var emoji: String
    var name: String
    var count: Int = 0
}

struct ContentView: View {
    @State private var emojis: [EmojiItem] = [
        EmojiItem(emoji: "😀", name: "Happy"),
        EmojiItem(emoji: "🔥", name: "Fire"),
        EmojiItem(emoji: "⭐", name: "Star"),
        EmojiItem(emoji: "❤️", name: "Heart"),
        EmojiItem(emoji: "🎉", name: "Party")
    ]
    
    var body: some View {
        NavigationStack {
            List {
                ForEach($emojis) { $item in
                    HStack {
                        Text(item.emoji)
                            .font(.largeTitle)
                        
                        Text(item.name)
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: {
                            if item.count > 0 {
                                item.count -= 1
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        
                        Text("\(item.count)")
                            .font(.title3)
                            .frame(minWidth: 30)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            item.count += 1
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Emoji Counter")
        }
    }
}

#Preview {
    ContentView()
}
