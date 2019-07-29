import UIKit
import RealmSwift
import SVProgressHUD
import Kingfisher

//缓存gdata
var cachedGdatas = [String: GData]()
fileprivate var checkingDoujinshi = [Int]()

class ListVC: BaseViewController {
    @IBOutlet weak var collectionView: UICollectionView!
    private(set) lazy var searchController: UISearchController = {
        return UISearchController(searchResultsController: historyVC)
    }()
    private lazy var historyVC: SearchHistoryVC = {
        return self.storyboard!.instantiateViewController(withIdentifier: "SearchHistoryVC") as! SearchHistoryVC
    }()
    private var items: [Doujinshi] = []
    private var currentPage = -1
    private var loadingPage = -1
    private var backGesture: InteractiveBackGesture?
    private var rowCount: Int { return min(12, max(2, Int(floor(collectionView.bounds.width / Defaults.List.cellWidth)))) }
    @IBOutlet weak var loadingView: LoadingView!
    
    enum Mode: String {
        case normal = "normal"
        case download = "download"
        case favorite = "favorites"
        case news = "news"
    }
    private var mode: Mode {
        let text = searchController.searchBar.text?.lowercased() ?? ""
        if text == Mode.download.rawValue {
            return .download
        } else if text.contains("favorites") {
            return .favorite
        } else if text.contains(",") {
            return .news
        } else {
            return .normal
        }
    }
    private var favoriteCategory: Int? {
        guard mode == .favorite else { return nil }
        let text = searchController.searchBar.text?.lowercased() ?? ""
        return text == "favorites" ? -1 : Int(text.replacingOccurrences(of: "favorites", with: ""))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        //顶部logo由图片改为按钮，点击后显示当前热门 Popular
        //navigationItem.titleView = UIImageView(image: #imageLiteral(resourceName: "title_icon"))
        let btn = UIButton()
        btn.setImage(#imageLiteral(resourceName: "title_icon"), for: .normal)
        btn.addTarget(self, action: #selector(showPopular), for: .touchUpInside)
        navigationItem.titleView = btn
        
        if traitCollection.forceTouchCapability == .available {
            registerForPreviewing(with: self, sourceView: collectionView)
        }
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPress(ges:)))
        longPressGesture.delaysTouchesBegan = true
        collectionView.addGestureRecognizer(longPressGesture)
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinch(ges:)))
        collectionView.addGestureRecognizer(pinchGesture)
        
        searchController.delegate = self
        if navigationController?.viewControllers.count == 1 {
            searchController.searchBar.text = Defaults.List.lastSearchKeyword
        } else {
            Defaults.List.lastSearchKeyword = searchController.searchBar.text ?? ""
            backGesture = InteractiveBackGesture(viewController: self, toView: collectionView)
        }
        historyVC.searchController = searchController
        historyVC.selectBlock = {[unowned self] text in
            self.searchController.isActive = false
            self.searchController.searchBar.text = text
            self.reloadData()
        }
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.delegate = self
        searchController.searchBar.showsCancelButton = false
        searchController.searchBar.enablesReturnKeyAutomatically = false
        searchController.searchBar.tintColor = view.tintColor
        definesPresentationContext = true
        
        loadNextPage()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(settingChanged(notification:)), name: .settingChanged, object: nil)
        collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if searchController.isActive {
            searchController.dismiss(animated: false, completion: nil)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let indexPath = collectionView.indexPathsForVisibleItems.first
        super.viewWillTransition(to: size, with: coordinator)
        collectionView?.collectionViewLayout.invalidateLayout()
        coordinator.animate(alongsideTransition: { _ in
            if let indexPath = indexPath {
                self.collectionView!.scrollToItem(at: indexPath, at: .top, animated: true)
            }
        })
    }
    
    private var initCellWidth = Defaults.List.defaultCellWidth
    @objc func pinch(ges: UIPinchGestureRecognizer) {
        if ges.state == .began {
            initCellWidth = collectionView.visibleCells.first?.frame.size.width ?? Defaults.List.defaultCellWidth
        } else if ges.state == .changed {
            let scale = ges.scale - 1
            let dx = initCellWidth * scale
            let width = min(max(initCellWidth + dx, 80), view.bounds.width)
            print("\(width)")
            if width != Defaults.List.cellWidth {
                Defaults.List.cellWidth = width
                collectionView.performBatchUpdates({
                    collectionView.collectionViewLayout.invalidateLayout() 
                }, completion: nil)
            }
        }
    }

    func loadNextPage() {
        if mode == .download {
            loadingView.hide()
            items = RealmManager.shared.downloaded.map { $0 }
            collectionView.reloadData()
        } else {
            guard loadingPage != currentPage + 1 else {return}
            loadingPage = currentPage + 1
            if loadingPage == 0 { loadingView.show() }
            RequestManager.shared.getList(page: loadingPage, search: searchController.searchBar.text) {[weak self] books in
                guard let self = self else {return}
                self.loadingView.hide()
                guard books.count > 0 else {return}
                let lastIndext = max(0, self.items.count - 1)
                //如果使用最低评分过滤，页面返回的数据会有重复内容，网站上会有个from参数去重，暂时不知怎么解析，所以才去手动去除重复画廊
                let existedIds = self.items.map { $0.id }
                let newBooks = books.filter { return !existedIds.contains($0.id) }
                let insertIndexPaths = newBooks.enumerated().map { IndexPath(item: $0.offset + lastIndext, section: 0) }
                self.items += newBooks
                self.collectionView.performBatchUpdates({
                    self.collectionView.insertItems(at: insertIndexPaths)
                }, completion: nil)
                self.currentPage += 1
                self.loadingPage = -1
            }
        }
    }

    func reloadData() {
        checkingDoujinshi.removeAll()   //清除正在获取数据的id
        currentPage = -1
        loadingPage = -1
        let deleteIndexPaths = items.enumerated().map { IndexPath(item: $0.offset, section: 0)}
        items = []
        collectionView.performBatchUpdates({
            self.collectionView.deleteItems(at: deleteIndexPaths)
        }, completion: { _ in
            self.loadNextPage()
        })
    }
    
    func checkGData(indexPath: IndexPath, completeBlock block: (() -> Void)?) {
        let index = indexPath.item
        guard items.count >= index, !checkingDoujinshi.contains(items[index].id) else { return }
        
        if items[index].isDownloaded || items[index].gdata != nil {
            return
        } else {
            
            let doujinshi = items[index]
            
            //Temp cover
            doujinshi.pages.removeAll()
            if !doujinshi.coverUrl.isEmpty {
                let coverPage = Page()
                coverPage.thumbUrl = doujinshi.coverUrl
                doujinshi.pages.append(coverPage)
            }
            
            if let gdata = cachedGdatas["\(doujinshi.id)"] {
                doujinshi.gdata = gdata
                block?()
                return
            }
            //保存需要请求的id
            checkingDoujinshi.append(doujinshi.id)
            
            RequestManager.shared.getGData(doujinshi: doujinshi) { [weak self] gdata in
                //网络请求有延迟，如果当前页面快速切换，需要判断当前画廊是否还存在
                guard let gdata = gdata,
                    let self = self,
                    self.items.count >= index,
                    doujinshi.id == self.items[index].id,
                    checkingDoujinshi.contains(doujinshi.id)
                    else { return }
                
                doujinshi.gdata = gdata
                cachedGdatas["\(doujinshi.id)"] = gdata  //缓存 gdata
                //删除已请求的id
                let temp = checkingDoujinshi.filter { return $0 != doujinshi.id }
                checkingDoujinshi = temp
                block?()
            }
        }
    }

    @IBAction func showFavorites(sender: UIBarButtonItem) {
        guard navigationController?.presentedViewController == nil else {return}
        if Defaults.List.isShowFavoriteList {
            let sheet = UIAlertController(title: "Favorites", message: nil, preferredStyle: .actionSheet)
            let all = UIAlertAction(title: "ALL", style: .default, handler: { (_) in
                self.showSearch(with: "favorites")
                Defaults.List.lastSearchKeyword = self.searchController.searchBar.text ?? ""
            })
            sheet.addAction(all)
            Defaults.List.favoriteTitles.enumerated().forEach { f in
                let a = UIAlertAction(title: f.element, style: .default, handler: { (_) in
                    self.showSearch(with: "favorites\(f.offset)")
                    Defaults.List.lastSearchKeyword = self.searchController.searchBar.text ?? ""
                })
                sheet.addAction(a)
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            sheet.popoverPresentationController?.barButtonItem = sender
            present(sheet, animated: true, completion: nil)
        } else {
            showSearch(with: "favorites")
            Defaults.List.lastSearchKeyword = searchController.searchBar.text ?? ""
        } 
    }
    
    @IBAction func showDownloads() {
        guard navigationController?.presentedViewController == nil else {return}
        showSearch(with: "download")
        Defaults.List.lastSearchKeyword = searchController.searchBar.text ?? ""
    }
    
    func showSearch(with shotcut: String) {
        searchController.searchBar.text = shotcut
        if searchController.isActive {
            searchController.dismiss(animated: false, completion: nil)
        }
        reloadData()
    }
    
    @objc func showPopular() {
        guard navigationController?.presentedViewController == nil else {return}
        self.showSearch(with: "popular")
        Defaults.List.lastSearchKeyword = self.searchController.searchBar.text ?? ""
    }

    @objc func longPress(ges: UILongPressGestureRecognizer) {
        guard mode == .download || mode == .favorite else {return}
        guard ges.state == .began, let indexPath = collectionView.indexPathForItem(at: ges.location(in: collectionView)) else {return}

        let doujinshi = items[indexPath.item]
        let title = mode == .download ? "Delete" : "Action"
        let actionTitle = mode == .download ? "Delete" : "Remove"
        let alert = UIAlertController(title: title, message: doujinshi.title, preferredStyle: .alert)
        let deleteAction = UIAlertAction(title: actionTitle, style: .destructive) { _ in
            if self.mode == .download {
                DownloadManager.shared.deleteDownloaded(doujinshi: doujinshi)
                self.items = RealmManager.shared.downloaded.map { $0 }
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [indexPath])
                }, completion: nil)
            } else if self.mode == .favorite {
                RequestManager.shared.deleteFavorite(doujinshi: doujinshi)
                self.items.remove(at: indexPath.item)
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [indexPath])
                }, completion: nil)
            }
        }
        if mode == .favorite {
            let moveAction = UIAlertAction(title: "Move", style: .default) { (_) in
                self.showFavoriteMoveSheet(with: indexPath)
            }
            alert.addAction(moveAction)
        }
        if mode == .download {
            let cell = collectionView.cellForItem(at: indexPath)!
            let vc = UIActivityViewController(activityItems: doujinshi.pages.map { $0.localUrl }, applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = collectionView
            vc.popoverPresentationController?.sourceRect = cell.frame
            let shareAction = UIAlertAction(title: "Share", style: .default) { (_) in
                self.present(vc, animated: true, completion: nil)
            }
            alert.addAction(shareAction)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        present(alert, animated: true, completion: nil)
    }
    
    @objc func showFavoriteMoveSheet(with indexPath: IndexPath) {
        let doujinshi = items[indexPath.item]
        let sheet = UIAlertController(title: "Move to", message: doujinshi.title, preferredStyle: .actionSheet)
        let displayingFavCategory = favoriteCategory ?? -1
        Defaults.List.favoriteTitles.enumerated().forEach { f in
            if displayingFavCategory != f.offset {
                let a = UIAlertAction(title: f.element, style: .default, handler: { (_) in
                    RequestManager.shared.moveFavorite(doujinshi: doujinshi, to: f.offset)
                    if displayingFavCategory != -1 {
                        self.items.remove(at: indexPath.item)
                        self.collectionView.performBatchUpdates({
                            self.collectionView.deleteItems(at: [indexPath])
                        }, completion: nil)
                    } else {
                        SVProgressHUD.show("→".toIcon(), status: nil)
                        SVProgressHUD.dismiss(withDelay: 1)
                    }
                })
                sheet.addAction(a)
            }
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        let sourceView = collectionView.cellForItem(at: indexPath)
        sheet.popoverPresentationController?.sourceView = sourceView
        sheet.popoverPresentationController?.sourceRect = CGRect(x: 0, y: sourceView!.bounds.height/2, width: sourceView!.bounds.width, height: 0)
        present(sheet, animated: true, completion: nil)
    }
    
    @objc func settingChanged(notification: Notification) {
        collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: self)
        if segue.identifier == "showSetting" {
            segue.destination.hero.modalAnimationType = .selectBy(presenting: .cover(direction: .up), dismissing: .uncover(direction: .down))
        }
    }
}

extension ListVC: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        
        let doujinshi = self.items[indexPath.item]
        
        checkGData(indexPath: indexPath) { [weak cell] in
            guard let c = cell, c.tag == doujinshi.id else { return }
            
            let cell = c as! ListCell
            
            if let rating = doujinshi.gdata?.rating, rating > 0 {
                cell.ratingLabel.text = "🌟\(rating)"
                cell.ratingLabel.isHidden = false
                cell.ratingLabel.layer.cornerRadius = cell.ratingLabel.bounds.height/2
            } else {
                cell.ratingLabel.isHidden = true
            }
            
            if let category = doujinshi.gdata?.category {
                cell.categoryLabel.isHidden = false
                cell.categoryLabel.text = category
                cell.categoryLabel.layer.cornerRadius = cell.categoryLabel.bounds.height/2
            } else {
                cell.categoryLabel.isHidden = true
            }
            
            if let time = doujinshi.gdata?.posted {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                let date = Date(timeIntervalSince1970: TimeInterval(integerLiteral: Int64(time)!))
                let timeStr = formatter.string(from: date)
                cell.timeLabel.text = timeStr
                cell.timeLabel.isHidden = false
            } else {
                cell.timeLabel.isHidden = true
            }
            
            if let fileCount = doujinshi.gdata?.filecount {
                cell.fileCountLabel.text = "\(fileCount) pages"
                cell.fileCountLabel.isHidden = false
            } else {
                cell.fileCountLabel.isHidden = true
            }
            
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ListCell
        
        let doujinshi = items[indexPath.item]
        cell.imageView.hero.id = "image_\(doujinshi.id)_0"
        cell.imageView.hero.modifiers = [.arc(intensity: 1), .forceNonFade]
        cell.imageView.isOpaque = true
        cell.tag = doujinshi.id
        
        if doujinshi.isDownloaded {
            if let image = UIImage(contentsOfFile: documentURL.appendingPathComponent(doujinshi.coverUrl).path) {
                cell.imageView.image = image
                cell.imageView.contentMode = image.preferContentMode
            }
        } else {
            let resource = ImageResource(downloadURL: URL(string: doujinshi.coverUrl)!, cacheKey: doujinshi.coverUrl)
            cell.imageView.kf.setImage(
                with: resource,
                placeholder: nil,
                options: [.cacheOriginalImage],
                progressBlock: nil) { (result) in
                    switch result {
                    case .success(let value):
                        cell.imageView.contentMode = value.image.preferContentMode
                    case .failure(let error):
                        print(error)
                    }
            }
        }
        
        if let language = doujinshi.title.language {
            cell.languageLabel.isHidden = Defaults.List.isHideTag
            cell.languageLabel.text = language.capitalized
            cell.languageLabel.layer.cornerRadius = cell.languageLabel.bounds.height/2
        } else {
            cell.languageLabel.isHidden = true
        }

        if let convent = doujinshi.title.conventionName {
            cell.conventionLabel.isHidden = Defaults.List.isHideTag
            cell.conventionLabel.text = convent
            cell.conventionLabel.layer.cornerRadius = cell.conventionLabel.bounds.height/2
        } else {
            cell.conventionLabel.isHidden = true
        }
        
        if let rating = doujinshi.gdata?.rating, rating > 0 {
            cell.ratingLabel.text = "🌟\(rating)"
            cell.ratingLabel.isHidden = false
            cell.ratingLabel.layer.cornerRadius = cell.ratingLabel.bounds.height/2
        } else {
            cell.ratingLabel.isHidden = true
        }
        
        if let category = doujinshi.gdata?.category {
            cell.categoryLabel.isHidden = false
            cell.categoryLabel.text = category
            cell.categoryLabel.layer.cornerRadius = cell.categoryLabel.bounds.height/2
        } else {
            cell.categoryLabel.isHidden = true
        }
        
        if let time = doujinshi.gdata?.posted {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let date = Date(timeIntervalSince1970: TimeInterval(integerLiteral: Int64(time)!))
            let timeStr = formatter.string(from: date)
            cell.timeLabel.text = timeStr
            cell.timeLabel.isHidden = false
        } else {
            cell.timeLabel.isHidden = true
        }
        
        if let fileCount = doujinshi.gdata?.filecount {
            cell.fileCountLabel.text = "\(fileCount) pages"
            cell.fileCountLabel.isHidden = false
        } else {
            cell.fileCountLabel.isHidden = true
        }
        
        cell.titleLabel?.text = doujinshi.title
        cell.titleLabel?.isHidden = Defaults.List.isHideTitle
        
        cell.layer.shouldRasterize = true
        cell.layer.rasterizationScale = UIScreen.main.scale
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard mode != .download else {return}
        
        let tempItems = indexPaths.map { $0.item }
        if tempItems.contains(items.count) || items.count == 0 { return }
        
        let urls = indexPaths.map { URL(string: self.items[$0.item].coverUrl)! }
        ImageManager.shared.prefetch(urls: urls)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let vc = storyboard!.instantiateViewController(withIdentifier: "GalleryVC") as! GalleryVC
        let item = items[indexPath.item]
        vc.doujinshi = item
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let flowLayout = collectionViewLayout as! UICollectionViewFlowLayout
        let width = (collectionView.bounds.width - flowLayout.sectionInset.left - flowLayout.sectionInset.right - flowLayout.minimumInteritemSpacing * CGFloat((rowCount - 1))) / CGFloat(rowCount)
        return CGSize(width: width, height: width * paperRatio)
    }
}

extension ListVC: UIViewControllerPreviewingDelegate {
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard let indexPath = collectionView.indexPathForItem(at: location) else {return nil}
        let vc = storyboard!.instantiateViewController(withIdentifier: "GalleryVC") as! GalleryVC
        let item = items[indexPath.item]
        vc.doujinshi = item
        if mode == .favorite {
            vc.doujinshi.isFavorite = true 
        }
        vc.delegate = self
        return vc
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        navigationController?.pushViewController(viewControllerToCommit, animated: true)
    }
}

extension ListVC: GalleryVCPreviewActionDelegate {
    
    func galleryDidSelectTag(text: String) {
        pushToListVC(with: text)
    }
    
    func pushToListVC(with tag: String) {
        let vc = storyboard!.instantiateViewController(withIdentifier: "ListVC") as! ListVC
        vc.searchController.searchBar.text = tag
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension ListVC: UISearchBarDelegate, UISearchControllerDelegate {
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
        searchController.dismiss(animated: true, completion: nil)
        reloadData()
        RealmManager.shared.saveSearchHistory(text: searchBar.text)
        Defaults.List.lastSearchKeyword = searchController.searchBar.text ?? ""
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        DispatchQueue.main.async {
            self.searchController.searchResultsController?.view.isHidden = false
        }
    }
    
    func willPresentSearchController(_ searchController: UISearchController) {
        navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }
        DispatchQueue.main.async {
            searchController.searchResultsController?.view.isHidden = false
        }
    }
    
    func didPresentSearchController(_ searchController: UISearchController) {
        searchController.searchResultsController?.view.isHidden = false
    }
    
    func didDismissSearchController(_ searchController: UISearchController) {
        navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
        Defaults.List.lastSearchKeyword = searchController.searchBar.text ?? ""
    }
}

extension ListVC: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard mode != .download else {return}
        if let indexPath = collectionView.indexPathsForVisibleItems.sorted().last, indexPath.item > items.count - max(rowCount * 2, 10) {
            loadNextPage()
        }
    }
} 
