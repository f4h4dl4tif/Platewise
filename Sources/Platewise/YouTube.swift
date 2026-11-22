import Foundation

/// Real video links come from the YouTube Data API v3, never from the AI (models can invent URLs that don't exist).
/// Without a YouTube key the app offers a YouTube search link instead, which always works.
enum YouTube {
    static func searchLink(_ query: String) -> VideoLink {
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return VideoLink(title: "Search YouTube for “\(query)”", channel: "YouTube", url: c.url!.absoluteString, isSearch: true)
    }

    static func videos(for query: String, apiKey: String) async -> [VideoLink] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [searchLink(query)] }

        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        c.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "3"),
            URLQueryItem(name: "safeSearch", value: "strict"),
            URLQueryItem(name: "videoEmbeddable", value: "true"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: key),
        ]
        guard let url = c.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return [searchLink(query)] }

        let found: [VideoLink] = items.compactMap { item in
            guard let id = (item["id"] as? [String: Any])?["videoId"] as? String,
                  let snippet = item["snippet"] as? [String: Any] else { return nil }
            let thumbs = snippet["thumbnails"] as? [String: Any]
            let thumb = ((thumbs?["medium"] ?? thumbs?["default"]) as? [String: Any])?["url"] as? String
            return VideoLink(title: decodeEntities(snippet["title"] as? String ?? "Video"),
                             channel: decodeEntities(snippet["channelTitle"] as? String ?? ""),
                             url: "https://www.youtube.com/watch?v=\(id)", thumbnailURL: thumb)
        }
        return found + [searchLink(query)]
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
