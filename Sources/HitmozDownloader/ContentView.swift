import SwiftUI
import AppKit

struct ContentView: View {
    @State private var query: String = ""
    @State private var tracks: [Track] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var downloadProgress: [String: Double] = [:] // id -> 0..1
    @State private var downloadingIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            statusBar
        }
    }

    // MARK: - Поиск

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Название трека или исполнитель", text: $query)
                .textFieldStyle(.plain)
                .onSubmit { Task { await performSearch() } }

            if isSearching {
                ProgressView().controlSize(.small)
            }

            Button("Найти") {
                Task { await performSearch() }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
        .padding(10)
    }

    // MARK: - Контент

    @ViewBuilder
    private var content: some View {
        if tracks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Введите запрос и нажмите «Найти»")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(tracks) { track in
                TrackRow(
                    track: track,
                    isDownloading: downloadingIDs.contains(track.id),
                    progress: downloadProgress[track.id] ?? 0,
                    onDownload: { Task { await download(track) } }
                )
            }
        }
    }

    // MARK: - Статус-бар

    private var statusBar: some View {
        HStack {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .lineLimit(1)
            } else if let statusMessage {
                Label(statusMessage, systemImage: "info.circle")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text("\(tracks.count) результат(ов)").foregroundColor(.secondary)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Действия

    private func performSearch() async {
        isSearching = true
        errorMessage = nil
        statusMessage = "Поиск…"
        defer { isSearching = false }

        do {
            let result = try await HitmozService.shared.search(query: query)
            await MainActor.run {
                self.tracks = result
                self.statusMessage = "Найдено: \(result.count)"
            }
        } catch {
            await MainActor.run {
                self.tracks = []
                self.errorMessage = error.localizedDescription
                self.statusMessage = nil
            }
        }
    }

    private func download(_ track: Track) async {
        let panel = NSSavePanel()
        panel.title = "Сохранить трек"
        panel.nameFieldStringValue = suggestedFileName(for: track)
        panel.allowedContentTypes = [.mp3]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        await MainActor.run {
            _ = downloadingIDs.insert(track.id)
            downloadProgress[track.id] = 0
            errorMessage = nil
            statusMessage = "Скачивание: \(track.title)"
        }

        do {
            try await HitmozService.shared.download(track: track, to: destination) { value in
                DispatchQueue.main.async {
                    downloadProgress[track.id] = value
                }
            }
            await MainActor.run {
                downloadingIDs.remove(track.id)
                downloadProgress[track.id] = 1.0
                statusMessage = "Готово: \(destination.lastPathComponent)"
            }
        } catch {
            await MainActor.run {
                downloadingIDs.remove(track.id)
                downloadProgress[track.id] = nil
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
        }
    }

    private func suggestedFileName(for track: Track) -> String {
        let base: String
        if track.artist.isEmpty {
            base = track.title
        } else {
            base = "\(track.artist) - \(track.title)"
        }
        let safe = base.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
        return safe + ".mp3"
    }
}

// MARK: - Строка трека

private struct TrackRow: View {
    let track: Track
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
            }

            Spacer()

            if isDownloading {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: progress)
                        .frame(width: 120)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: onDownload) {
                    Label("Скачать", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}