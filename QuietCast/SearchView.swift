import SwiftUI

struct SearchView: View {
    @Binding var podcasts: [Podcast]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [iTunesPodcast] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchError: String?

    private var savedFeedURLs: Set<String> {
        Set(podcasts.map { $0.feedURL })
    }

    var body: some View {
        NavigationStack {
            List {
                if !results.isEmpty {
                    Section {
                        Text("\(results.count) results")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                ForEach(results) { result in
                    SearchResultRow(
                        result: result,
                        isSaved: result.feedUrl.map { savedFeedURLs.contains($0) } ?? false,
                        onAdd: { podcast in
                            addPodcast(podcast)
                        }
                    )
                }
            }
            .listStyle(.plain)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search podcasts")
            .onSubmit(of: .search) {
                performSearch()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if let searchError {
                    ContentUnavailableView(
                        searchError,
                        systemImage: "wifi.slash",
                        description: Text("Check your connection and try again."))
                } else if results.isEmpty && hasSearched {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        hasSearched = false
        searchError = nil
        Task {
            do {
                results = try await iTunesSearchService.search(term: searchText)
            } catch let error as URLError
                where error.code == .notConnectedToInternet || error.code == .networkConnectionLost
            {
                results = []
                searchError = "No Internet Connection"
            } catch {
                results = []
                searchError = "Search Failed"
            }
            isSearching = false
            hasSearched = true
        }
    }

    private func addPodcast(_ podcast: Podcast) {
        guard !podcasts.contains(where: { $0.feedURL == podcast.feedURL }) else { return }
        podcasts.append(podcast)
        PersistenceManager.shared.update { library in
            library.podcasts = podcasts
        }
        dismiss()
    }
}

private struct SearchResultRow: View {
    let result: iTunesPodcast
    let isSaved: Bool
    let onAdd: (Podcast) -> Void

    var body: some View {
        HStack(spacing: 12) {
            artwork
            details
            Spacer()
            addButton
        }
        .padding(.vertical, 4)
    }

    private var artwork: some View {
        AsyncImage(url: URL(string: result.artworkUrl100 ?? "")) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.gray.opacity(0.3)
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.collectionName)
                .font(.headline)
                .lineLimit(2)
            Text(result.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            metadata
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            if let count = result.trackCount, count > 0 {
                Text("\(count) episodes")
            }
            if let genre = result.primaryGenreName {
                if result.trackCount != nil {
                    Text("·")
                }
                Text(genre)
            }
            if let rating = result.contentAdvisoryRating {
                if result.trackCount != nil || result.primaryGenreName != nil {
                    Text("·")
                }
                Text(rating)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var addButton: some View {
        if let podcast = result.toPodcast() {
            if isSaved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.warmGreen)
            } else {
                Button {
                    onAdd(podcast)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
