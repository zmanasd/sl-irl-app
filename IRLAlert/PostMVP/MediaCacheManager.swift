import Foundation
import os.log

/// Downloads and caches remote sound files to disk for offline/repeated playback.
/// Uses a simple file-based cache in the app's Caches directory.
actor MediaCacheManager {
    
    static let shared = MediaCacheManager()
    
    private let cacheDirectory: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.irlalert.app", category: "MediaCache")
    
    /// Tracks in-flight downloads to avoid duplicates
    private var activeDownloads: [URL: Task<URL, Error>] = [:]
    
    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("AlertSounds", isDirectory: true)
        
        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure URL session with reasonable timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Get the local file URL for a remote sound. Downloads if not cached.
    /// Returns nil if the download fails.
    func localURL(for remoteURL: URL) async -> URL? {
        let cachedPath = cacheFilePath(for: remoteURL)
        
        // Return cached file if it exists
        if FileManager.default.fileExists(atPath: cachedPath.path) {
            logger.debug("Cache hit: \(remoteURL.lastPathComponent)")
            return cachedPath
        }
        
        // Check for in-flight download of the same URL
        if let existingTask = activeDownloads[remoteURL] {
            logger.debug("Joining existing download: \(remoteURL.lastPathComponent)")
            return try? await existingTask.value
        }
        
        // Start new download
        let downloadTask = Task<URL, Error> {
            logger.info("Downloading: \(remoteURL.lastPathComponent)")
            let (tempURL, response) = try await urlSession.download(from: remoteURL)
            
            // Validate response
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw MediaCacheError.httpError(httpResponse.statusCode)
            }
            
            // Move to cache
            try? FileManager.default.removeItem(at: cachedPath) // Remove stale version
            try FileManager.default.moveItem(at: tempURL, to: cachedPath)
            
            logger.info("Cached: \(remoteURL.lastPathComponent)")
            return cachedPath
        }
        
        activeDownloads[remoteURL] = downloadTask
        
        defer {
            activeDownloads[remoteURL] = nil
        }
        
        do {
            return try await downloadTask.value
        } catch {
            logger.error("Download failed for \(remoteURL.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Clear all cached sound files.
    func clearCache() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            logger.info("Cache cleared: \(files.count) files removed")
        } catch {
            logger.error("Failed to clear cache: \(error.localizedDescription)")
        }
    }
    
    /// Get the total size of the cache in bytes.
    func cacheSize() -> Int64 {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            return files.reduce(0) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + Int64(size)
            }
        } catch {
            return 0
        }
    }
    
    // MARK: - Helpers
    
    /// Generate a deterministic cache file path from a remote URL
    private func cacheFilePath(for remoteURL: URL) -> URL {
        // Use a hash of the full URL as the filename to avoid collisions
        let hash = remoteURL.absoluteString.data(using: .utf8)!
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(32)
        let ext = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
        return cacheDirectory.appendingPathComponent("\(hash).\(ext)")
    }
    
    enum MediaCacheError: LocalizedError {
        case httpError(Int)
        
        var errorDescription: String? {
            switch self {
            case .httpError(let code):
                return "HTTP error \(code)"
            }
        }
    }
}
