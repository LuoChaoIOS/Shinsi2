import Foundation
import RealmSwift
import SDWebImage
import Alamofire

//下载失败，最大重试三次
let maxRetries = 3
//完成后设定下一个任务间隔时间，避免被识别为爬虫？？
var sleepTime = 1
//最大线程并发数设为1，避免被识别为爬虫？？
let maxConcurrentOperationCount = 1

class SSOperation: Operation {
    enum State {
        case ready, executing, finished
        var keyPath: String {
            switch self {
            case .ready:
                return "isReady"
            case .executing:
                return "isExecuting"
            case .finished:
                return "isFinished"
            }
        }
    }
    var state = State.ready {
        willSet {
            willChangeValue(forKey: newValue.keyPath)
            willChangeValue(forKey: state.keyPath)
        }
        didSet {
            didChangeValue(forKey: oldValue.keyPath)
            didChangeValue(forKey: state.keyPath)
        }
    }
    override var isReady: Bool { return super.isReady && state == .ready }
    override var isExecuting: Bool { return state == .executing }
    override var isFinished: Bool { return state == .finished }
    override var isAsynchronous: Bool { return true }
}

class PageDownloadOperation: SSOperation {
    var url: String
    var folderPath: String
    var pageNumber: Int
    var retry = 0

    init(url: String, folderPath: String, pageNumber: Int) {
        self.url = url
        self.folderPath = folderPath
        self.pageNumber = pageNumber
    }
    
    override func start() {
        guard !isCancelled && retry < maxRetries else {
            state = .finished
            return
        }
        retry += 1
        state = .executing
        main()
        print("start count = \(self.retry)")
    }
    
    override func main() {
        RequestManager.shared.getPageImageUrl(url: url) { imageUrl in
            if let imageUrl = imageUrl {
                let documentsURL = URL(fileURLWithPath: self.folderPath)
                let fileURL = documentsURL.appendingPathComponent(String(format: "%04d.jpg", self.pageNumber))
                let destination: DownloadRequest.DownloadFileDestination = { _, _ in
                    return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
                }
                //异步下载，并设定下载间隔时长
                let queue = DispatchQueue(label: "asyncQueue")
                queue.asyncAfter(wallDeadline: .now() + DispatchTimeInterval.seconds(sleepTime)) {
                    Alamofire.download(imageUrl, to: destination).response { _ in
                        self.state = .finished
                        if let image = UIImage(contentsOfFile: fileURL.path) {
                            SDWebImageManager.shared.imageCache.store(image, imageData: image.sd_imageData(), forKey: imageUrl, cacheType: .all, completion: nil)
                        } else {
                            self.start()
                        }
                        if self.isCancelled {
                            try? FileManager.default.removeItem(at: documentsURL)
                        }
                    }
                }
            } else {
                self.state = .finished
            }
        }
    }
}

class DownloadManager: NSObject {
    static let shared = DownloadManager()
    var queues: [OperationQueue] = []
    var books: [String: Doujinshi] = [:]
    
    func download(doujinshi: Doujinshi!) {
        guard let gdata = doujinshi.gdata, doujinshi.pages.count != 0 else {return}
        let folderName = gdata.gid
        let path = documentURL.appendingPathComponent(folderName).path
        
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
        queue.isSuspended = queues.count != 0
        queue.name = gdata.gid
        queues.append(queue)
        books[gdata.gid] = doujinshi
        
        for (i, p) in doujinshi.pages.enumerated() {
            let o = PageDownloadOperation(url: p.url, folderPath: path, pageNumber: i)
            queue.addOperation(o)
        }
        queue.addObserver(self, forKeyPath: "operationCount", options: [.new], context: nil)
    }
    
    func cancelAllDownload() {
        let fileManager = FileManager.default
        for q in queues {
            q.removeObserver(self, forKeyPath: "operationCount")
            q.cancelAllOperations()
            let url = documentURL.appendingPathComponent(q.name!)
            try? fileManager.removeItem(at: url)
        }
        queues.removeAll()
        books.removeAll()
    }
    
    func deleteDownloaded(doujinshi: Doujinshi) {
        try? FileManager.default.removeItem(at: documentURL.appendingPathComponent(doujinshi.gdata!.gid))
        RealmManager.shared.deleteDoujinshi(book: doujinshi)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath, keyPath == "operationCount",
              let change = change, let count = change[.newKey] as? Int,
              let queue = object as? OperationQueue
        else {return}
        
        if count == 0 {
            print("\(queue.name!): Finished!!!")
            RealmManager.shared.saveDownloadedDoujinshi(book: books[queue.name!]!)
            queues.remove(at: queues.firstIndex(of: queue)!)
            queue.removeObserver(self, forKeyPath: "operationCount")
            books.removeValue(forKey: queue.name!)
            if let nextQueue = queues.first {
                nextQueue.isSuspended = false
                print("Start Next queue: \(nextQueue.name!)")
            }
        }
    }
}
