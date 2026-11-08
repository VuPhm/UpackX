import Foundation
import AppKit

public struct GitHubAsset: Codable {
    public let name: String
    public let browserDownloadURL: String
    public let size: Int64
    public let contentType: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }
}

public struct GitHubReleaseResponse: Codable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: String
    public let publishedAt: String?
    public let assets: [GitHubAsset]?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

public struct UpdateInfo {
    public let version: SemVer
    public let title: String
    public let releaseNotes: String
    public let releaseDate: String?
    public let htmlURL: URL
    public let downloadURL: URL?
    public let assetName: String?
    public let assetSize: Int64?
}

public enum UpdateCheckResult {
    case upToDate(currentVersion: String)
    case updateAvailable(UpdateInfo)
    case error(String)
}

public final class UpdateManager {
    public static let shared = UpdateManager()
    
    public static let repoOwner = "VuPhm"
    public static let repoName = "UpackX"
    public static let latestReleaseEndpoint = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
    
    private let lastCheckKey = "UpackX_LastUpdateCheckTimestamp"
    private let autoCheckEnabledKey = "UpackX_AutoUpdateCheckEnabled"
    
    // 24 hours between background checks
    public static let backgroundCheckInterval: TimeInterval = 86400
    
    public var currentVersionString: String {
        if let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !ver.isEmpty {
            return ver
        }
        return "1.3.1"
    }
    
    public var isAutoCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoCheckEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoCheckEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoCheckEnabledKey)
        }
    }
    
    public var lastCheckDate: Date? {
        let ts = UserDefaults.standard.double(forKey: lastCheckKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
    
    private init() {}
    
    public func recordCheckTime() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
    }
    
    /// Checks for updates against GitHub Releases
    public func checkForUpdates(
        customEndpoint: String? = nil,
        completion: @escaping (UpdateCheckResult) -> Void
    ) {
        let endpointStr = customEndpoint ?? Self.latestReleaseEndpoint
        guard let url = URL(string: endpointStr) else {
            completion(.error("URL kiểm tra cập nhật không hợp lệ."))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("UpackX/\(currentVersionString) (Macintosh; Intel macOS)", forHTTPHeaderField: "User-Agent")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.error("Không thể kết nối đến máy chủ cập nhật: \(error.localizedDescription)"))
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.error("Phản hồi máy chủ không hợp lệ."))
                }
                return
            }
            
            guard httpResponse.statusCode == 200, let data = data else {
                DispatchQueue.main.async {
                    if httpResponse.statusCode == 404 {
                        completion(.error("Không tìm thấy thông tin phiên bản phát hành trên GitHub."))
                    } else {
                        completion(.error("Máy chủ cập nhật trả về mã lỗi HTTP \(httpResponse.statusCode)."))
                    }
                }
                return
            }
            
            do {
                let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
                self.recordCheckTime()
                
                guard let remoteVer = SemVer(string: release.tagName) else {
                    DispatchQueue.main.async {
                        completion(.error("Định dạng phiên bản '\(release.tagName)' không hợp lệ theo chuẩn SemVer."))
                    }
                    return
                }
                
                let currentVer = SemVer(string: self.currentVersionString) ?? SemVer(string: "1.0.0")!
                
                if remoteVer > currentVer {
                    // Find preferred macOS package (.dmg > .pkg > .zip)
                    var preferredAsset: GitHubAsset? = nil
                    if let assets = release.assets {
                        preferredAsset = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                            ?? assets.first(where: { $0.name.lowercased().hasSuffix(".pkg") })
                            ?? assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
                    }
                    
                    let downloadURL: URL?
                    if let direct = preferredAsset?.browserDownloadURL, let dURL = URL(string: direct) {
                        downloadURL = dURL
                    } else if let html = URL(string: release.htmlURL) {
                        downloadURL = html
                    } else {
                        downloadURL = nil
                    }
                    
                    let updateInfo = UpdateInfo(
                        version: remoteVer,
                        title: release.name ?? "UpackX v\(remoteVer)",
                        releaseNotes: release.body ?? "Bản cập nhật mới với nhiều cải tiến hiệu năng và sửa lỗi.",
                        releaseDate: release.publishedAt,
                        htmlURL: URL(string: release.htmlURL) ?? url,
                        downloadURL: downloadURL,
                        assetName: preferredAsset?.name,
                        assetSize: preferredAsset?.size
                    )
                    
                    DispatchQueue.main.async {
                        completion(.updateAvailable(updateInfo))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.upToDate(currentVersion: self.currentVersionString))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.error("Lỗi giải mã thông tin cập nhật: \(error.localizedDescription)"))
                }
            }
        }
        task.resume()
    }
    
    /// Performs non-intrusive periodic background check
    public func checkInBackgroundIfNeeded(onUpdateAvailable: ((UpdateInfo) -> Void)? = nil) {
        guard isAutoCheckEnabled else { return }
        
        if let last = lastCheckDate {
            if Date().timeIntervalSince(last) < Self.backgroundCheckInterval {
                return
            }
        }
        
        checkForUpdates { result in
            if case .updateAvailable(let info) = result {
                NotificationHelper.shared.notifyUpdateAvailable(version: info.version.description, releaseNotes: info.title)
                onUpdateAvailable?(info)
            }
        }
    }
}
