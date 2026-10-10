import Foundation
import SwiftSoup

/// Сервис для работы с ru.hitmoz.org:
/// - поиск треков
/// - получение прямой ссылки на MP3
/// - скачивание файла
final class HitmozService {

    static let shared = HitmozService()

    private let baseURL = "https://ru.hitmoz.org"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
                            "Version/17.0 Safari/605.1.15"

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "ru-RU,ru;q=0.9,en;q=0.8"
        ]
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Поиск

    func search(query: String) async throws -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let encoded = trimmed.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else { throw HitmozError.invalidURL }

        // Сайт поддерживает поиск по адресу /search?q=...
        guard let url = URL(string: "\(baseURL)/search?q=\(encoded)") else {
            throw HitmozError.invalidURL
        }

        let html = try await fetchHTML(url: url)
        let tracks = try parseSearchResults(html: html)
        if tracks.isEmpty { throw HitmozError.noResults }
        return tracks
    }

    // MARK: - Получение ссылки на MP3

    func fetchDownloadURL(for track: Track) async throws -> URL {
        let html = try await fetchHTML(url: track.songURL)
        return try parseDownloadURL(html: html, pageURL: track.songURL)
    }

    // MARK: - Скачивание

    /// Скачивает трек, сообщая о прогрессе (0.0 ... 1.0).
    func download(
        track: Track,
        to destination: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        let mp3URL = try await fetchDownloadURL(for: track)
        try await downloadFile(from: mp3URL, to: destination, progress: progress)
    }

    // MARK: - Сетевые утилиты

    private func fetchHTML(url: URL) async throws -> String {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw HitmozError.parseError("HTTP \(http.statusCode)")
            }
            // Пытаемся декодировать в UTF-8, затем в windows-1251 (частая кодировка на таких сайтах)
            if let html = String(data: data, encoding: .utf8) {
                return html
            }
            if let html = String(data: data, encoding: .windowsCP1251) {
                return html
            }
            throw HitmozError.parseError("Не удалось декодировать страницу")
        } catch let e as HitmozError {
            throw e
        } catch {
            throw HitmozError.networkError(error)
        }
    }

    private func downloadFile(
        from url: URL,
        to destination: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = session.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    cont.resume(throwing: HitmozError.networkError(error))
                    return
                }
                guard let tempURL = tempURL else {
                    cont.resume(throwing: HitmozError.parseError("Пустой ответ при скачивании"))
                    return
                }
                do {
                    // Удаляем существующий файл, если есть
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    cont.resume()
                } catch {
                    cont.resume(throwing: HitmozError.fileSaveError(error))
                }
            }

            // Наблюдаем за прогрессом
            let observation = task.progress.observe(\.fractionCompleted) { prog, _ in
                progress(prog.fractionCompleted)
            }
            _ = observation // удерживаем, пока задача выполняется

            task.resume()
        }
    }

    // MARK: - Парсинг

    private func parseSearchResults(html: String) throws -> [Track] {
        let doc = try SwiftSoup.parse(html)
        var tracks: [Track] = []
        var seen = Set<String>()

        // Способ 1: ищем все ссылки, ведущие на страницы песен.
        // На hitmoz страницы треков обычно имеют вид /song/<id> или /track/<id>.
        let links = try doc.select("a[href]")

        for link in links {
            let href = try link.attr("href")
            guard isSongLink(href) else { continue }

            let fullURL = makeAbsoluteURL(href)
            guard let songURL = fullURL else { continue }

            // Уникальный идентификатор трека
            let id = songURL.path
            guard !seen.contains(id) else { continue }
            seen.insert(id)

            // Пытаемся извлечь название и исполнителя
            let linkText = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)

            // Иногда название/исполнитель лежат в родителе или соседних узлах
            var artist = ""
            var title = linkText

            // Попытка 1: разделить по " - " (типичный формат "Артист - Название")
            if let range = linkText.range(of: " - ") {
                artist = String(linkText[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                title  = String(linkText[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }

            // Попытка 2: найти элементы с классами artist/performer и title/name внутри родителя
            if let parent = link.parent() {
                if let artistEl = try? parent.select(".artist, .performer, .singer").first(),
                   let a = try? artistEl.text(), !a.isEmpty {
                    artist = a
                }
                if let titleEl = try? parent.select(".title, .name, .song-title").first(),
                   let t = try? titleEl.text(), !t.isEmpty {
                    title = t
                }
            }

            guard !title.isEmpty else { continue }

            tracks.append(Track(
                id: id,
                title: title,
                artist: artist,
                songURL: songURL
            ))
        }

        return tracks
    }

    private func parseDownloadURL(html: String, pageURL: URL) throws -> URL {
        let doc = try SwiftSoup.parse(html)

        // 1. Ищем ссылки, заканчивающиеся на .mp3
        if let el = try doc.select("a[href$=.mp3], a[href*='.mp3']").first(),
           let href = try? el.attr("href"),
           let url = makeAbsoluteURL(href) {
            return url
        }

        // 2. Ищем элементы с классом download / download-link
        let downloadSelectors = [
            "a.download-link", "a.download", "a[data-download]",
            "a[href*='/download/']", "a[href*='download.php']",
            "button[data-url]", "a.btn-download"
        ]
        for selector in downloadSelectors {
            if let el = try doc.select(selector).first() {
                let candidates = [
                    try? el.attr("href"),
                    try? el.attr("data-url"),
                    try? el.attr("data-href")
                ]
                for candidate in candidates {
                    if let c = candidate, !c.isEmpty, let url = makeAbsoluteURL(c) {
                        return url
                    }
                }
            }
        }

        // 3. Ищем в <script> строки с .mp3
        let scripts = try doc.select("script")
        let regex = try NSRegularExpression(
            pattern: #"https?://[^"'\s]+\.mp3"#,
            options: []
        )
        for script in scripts {
            let text = try script.html()
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let r = Range(match.range, in: text) {
                let urlString = String(text[r])
                if let url = URL(string: urlString) {
                    return url
                }
            }
        }

        throw HitmozError.downloadLinkNotFound
    }

    // MARK: - Утилиты

    private func isSongLink(_ href: String) -> Bool {
        let patterns = ["/song/", "/track/", "/music/", "/mp3/"]
        return patterns.contains { href.contains($0) }
    }

    private func makeAbsoluteURL(_ href: String) -> URL? {
        if href.hasPrefix("http://") || href.hasPrefix("https://") {
            return URL(string: href)
        }
        if href.hasPrefix("//") {
            return URL(string: "https:" + href)
        }
        if href.hasPrefix("/") {
            return URL(string: baseURL + href)
        }
        return URL(string: baseURL + "/" + href)
    }
}