import Foundation
import SDWebImage

public extension Notification.Name {
    static let photoLoaded = Notification.Name("SSPHOTO_LOADING_DID_END_NOTIFICATION")
}

class SSPhoto: NSObject {
    
    var underlyingImage: UIImage?
    var lowQualityImage: UIImage? {
        return underlyingImage?.sd_imageFormat == .GIF ? underlyingImage?.compressImageOnlength(maxLength: 1024 * 1024) : underlyingImage
    }
    var urlString: String
    var isLoading = false
    let imageCache = SDWebImageManager.shared.imageCache
    
    init(URL url: String) {
        urlString = url
        super.init()
    }

    func loadUnderlyingImageAndNotify() {
        guard isLoading == false, underlyingImage == nil else { return } 
        isLoading = true
        RequestManager.shared.getPageImageUrl(url: urlString) { [weak self] url in
            guard let self = self else { return }
            guard let url = url else {
                self.imageLoadComplete()
                return
            }
            SDWebImageDownloader.shared.downloadImage(with: URL(string: url)!, options: [.highPriority, .handleCookies, .useNSURLCache], progress: nil, completed: { [weak self] (image, data, _, _) in
                guard let self = self else { return }
                self.imageCache.store(image, imageData: data, forKey: self.urlString, cacheType: .all)
                self.underlyingImage = image
                DispatchQueue.main.async {
                    print("下载完成" + self.urlString)
                    self.imageLoadComplete()
                }
            })
        }
        
    }

    func checkCache() {
        imageCache.queryImage(forKey: urlString, options: [.highPriority], context: nil) { [weak self] (image, _, _) in
            if let diskCache = image, let self = self {
                self.underlyingImage = diskCache
                self.imageLoadComplete()
            }
        }
    }

    func imageLoadComplete() {
        isLoading = false
        NotificationCenter.default.post(name: .photoLoaded, object: self)
    }
}
