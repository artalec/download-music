import Foundation

struct Track: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let songURL: URL
    var duration: String? = nil

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum HitmozError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case parseError(String)
    case noResults
    case downloadLinkNotFound
    case fileSaveError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:              return "Некорректный URL"
        case .networkError(let e):     return "Ошибка сети: \(e.localizedDescription)"
        case .parseError(let msg):     return "Ошибка разбора страницы: \(msg)"
        case .noResults:               return "Ничего не найдено"
        case .downloadLinkNotFound:    return "Не удалось найти ссылку на скачивание"
        case .fileSaveError(let e):    return "Ошибка сохранения файла: \(e.localizedDescription)"
        }
    }
}