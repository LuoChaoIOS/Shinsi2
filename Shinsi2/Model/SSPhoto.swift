import Foundation
import Kingfisher

public extension Notification.Name {
    static let photoLoaded = Notification.Name("SSPHOTO_LOADING_DID_END_NOTIFICATION")
}

class SSPhoto: NSObject {
    
    var underlyingImage: UIImage?
    var urlString: String
    var isLoading = false
    let imageCache = KingfisherManager.shared.cache
    var imageUrl: String?
    
    init(URL url: String) {
        urlString = url
        super.init()
    }

    func loadUnderlyingImageAndNotify() {
        guard isLoading == false, underlyingImage == nil else { return }
        isLoading = true
        if imageUrl != nil {
            download()
            return
        }
        RequestManager.shared.getPageImageUrl(url: urlString) { [weak self] url in
            guard let self = self else { return }
            guard let url = url else {
                self.imageLoadComplete()
                return
            }
            self.imageUrl = url
            self.download()
        }
        
    }
    
    func download() {
        KingfisherManager.shared.downloader.downloadImage(
            with: URL(string: imageUrl!)!,
            options: [.cacheOriginalImage],
            progressBlock: nil,
            completionHandler: { [weak self] (result) in
                switch result {
                case .success(let value):
                    guard let self = self else { return }
                    self.underlyingImage = value.image
                    KingfisherManager.shared.cache.storeToDisk(value.originalData, forKey: self.urlString)  //缓存到磁盘
                    DispatchQueue.main.async {
                        print("下载完成" + self.urlString)
                        self.imageLoadComplete()
                    }
                case .failure(let error):
                    print(error)
                }
        })
    }

    func checkCache() {
        imageCache.retrieveImage(forKey: urlString) { [weak self] (result) in
            switch result {
            case .success(let value):
                guard let self = self else { return }
                self.underlyingImage = value.image
                self.imageLoadComplete()
            case .failure(let error):
                print(error)
            }
        }
    }

    func imageLoadComplete() {
        isLoading = false
        NotificationCenter.default.post(name: .photoLoaded, object: self)
    }
}
