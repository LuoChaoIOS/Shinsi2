import UIKit
import Kingfisher

class ImageManager {
    static let shared: ImageManager = ImageManager()
    let imageCache = KingfisherManager.shared.cache
    private var downloadingUrls: Set<URL> = Set<URL>()
    
    func getCache(forKey name: String, complete: @escaping ((_ image: UIImage?) -> Void)) {
        imageCache.retrieveImage(forKey: name, options: nil, callbackQueue: .mainAsync) { (result) in
            switch result {
            case .success(let value):
                complete(value.image)
            case .failure(let error):
                print(error)
                complete(nil)
            }
        }
    }
    
    func prefetch(urls: [URL]) {
        var prefetchUrls: [URL] = []
        for url in urls {
            guard !downloadingUrls.contains(url) else {return}
            self.downloadingUrls.insert(url)
            prefetchUrls.append(url)
        }
        let prefetcher = ImagePrefetcher(
        urls: prefetchUrls,
        options: [.cacheOriginalImage],
        progressBlock: nil) { (_, _, _) in
            prefetchUrls.forEach { self.downloadingUrls.remove($0.downloadURL) }
        }
        prefetcher.maxConcurrentDownloads = maxConcurrentOperationCount
        prefetcher.start()
    }
}

extension UIImage {
    /// 压缩图片数据-不压尺寸
    ///
    /// - Parameters:
    ///   - maxLength: 最大长度
    /// - Returns:
    func compressImageOnlength(maxLength: Int) -> UIImage? {
        guard let vData = self.jpegData(compressionQuality: 1) else { return nil }
        print("压缩前kb: \( Double((vData.count)/1024))")
        if vData.count < maxLength {
            return UIImage(data: vData)
        }
        var compress:CGFloat = 0.9
        guard var data = self.jpegData(compressionQuality: compress) else { return nil }
        while data.count > maxLength && compress > 0.01 {
            print("压缩比: \(compress)")
            compress -= 0.02
            data = self.jpegData(compressionQuality: compress)!
        }
        print("压缩后kb: \(Double((data.count)/1024))")
        return UIImage(data: vData)
    }
    
    //二分压缩法
    func compressImageMid(maxLength: Int) -> Data? {
        var compression: CGFloat = 1
        guard var data = self.jpegData(compressionQuality: 1) else { return nil }
        print("压缩前kb: \( Double((data.count)/1024))")
        if data.count < maxLength {
            return data
        }
        print("压缩前kb", data.count / 1024, "KB")
        var max: CGFloat = 1
        var min: CGFloat = 0
        for _ in 0..<6 {
            compression = (max + min) / 2
            data = self.jpegData(compressionQuality: compression)!
            if CGFloat(data.count) < CGFloat(maxLength) * 0.9 {
                min = compression
            } else if data.count > maxLength {
                max = compression
            } else {
                break
            }
        }
        var resultImage: UIImage = UIImage(data: data)!
        if data.count < maxLength {
            return data
        }
        return nil
    }
        /// 根据尺寸重新生成图片
        ///
        /// - Parameter size: 设置的大小
        /// - Returns: 新图
        func imageWithNewSize(size: CGSize) -> UIImage? {
            
            if self.size.height > size.height {
                
                let width = size.height / self.size.height * self.size.width
                
                let newImgSize = CGSize(width: width, height: size.height)
                
                UIGraphicsBeginImageContext(newImgSize)
                
                self.draw(in: CGRect(x: 0, y: 0, width: newImgSize.width, height: newImgSize.height))
                
                let theImage = UIGraphicsGetImageFromCurrentImageContext()
                
                UIGraphicsEndImageContext()
                
                guard let newImg = theImage else { return  nil}
                
                return newImg
                
            } else {
                
                let newImgSize = CGSize(width: size.width, height: size.height)
                
                UIGraphicsBeginImageContext(newImgSize)
                
                self.draw(in: CGRect(x: 0, y: 0, width: newImgSize.width, height: newImgSize.height))
                
                let theImage = UIGraphicsGetImageFromCurrentImageContext()
                
                UIGraphicsEndImageContext()
                
                guard let newImg = theImage else { return  nil}
                
                return newImg
            }
        }
}
