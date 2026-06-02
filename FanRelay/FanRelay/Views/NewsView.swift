import SwiftUI
import SafariServices

/// A league's news: headlines with source + age, tapping into an in-app
/// reader. Uses the same explicit load-state pattern as the scores screen.
struct NewsView: View {

    @StateObject private var vm: NewsViewModel
    /// The article the user tapped, presented in the reader sheet.
    @State private var readerArticle: Article?

    init(query: String, title: String) {
        _vm = StateObject(wrappedValue: NewsViewModel(query: query, title: title))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .loading:
                ProgressView("Loading news…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ContentUnavailableView("No news",
                                       systemImage: "newspaper",
                                       description: Text("No recent \(vm.title) stories found."))
            case .failed(let message):
                errorState(message)
            case .loaded(let articles):
                list(articles)
            }
        }
        .navigationTitle("\(vm.title) News")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .sheet(item: $readerArticle) { article in
            // In-app reader with Safari's reader mode — strips ads/clutter
            // on-device. No scraping or rehosting (spec content decision).
            SafariReader(url: article.url)
                .ignoresSafeArea()
        }
    }

    private func list(_ articles: [Article]) -> some View {
        List(articles) { article in
            Button {
                readerArticle = article
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(article.source)
                        Text("·")
                        Text(article.age)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.load() }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Try Again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SFSafariViewController wrapper

/// Bridges UIKit's SFSafariViewController into SwiftUI. Reader mode is enabled
/// up front so articles open clean and ad-stripped on-device.
private struct SafariReader: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        NewsView(query: "NFL", title: "NFL")
    }
}
