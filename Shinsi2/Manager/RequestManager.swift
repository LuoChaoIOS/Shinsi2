import Alamofire
import Kanna

class RequestManager {
    
    static let shared = RequestManager()

    func getList(page: Int, search keyword: String? = nil, completeBlock block: (([Doujinshi]) -> Void)?) {
        print(#function)
        let categoryFilters = Defaults.Search.categories.map {"f_\($0)=\(UserDefaults.standard.bool(forKey: $0) ? 1 : 0)"}.joined(separator: "&")
        var url = Defaults.URL.host + "/?"
        url += "\(categoryFilters)&f_apply=Apply+Filter" //Apply category filters
        url += "&advsearch=1&f_sname=on&f_stags=on&f_sdesc=on&f_storr=on&f_sh=on" //Advance search  f_storr种子名称 f_sdesc画廊描述
        //Minimum Rating 最低评分
        if  Defaults.Search.isMinimumRating {
            url += "&f_sr=on&f_srdd=\(Defaults.Search.minimumRating)"
        }
        url += "&inline_set=dm_t" //Set mode to Thumbnail View
        
        //https://e-hentai.org/?f_search=naru&advsearch=1&f_spf=&f_spt=
        //https://e-hentai.org/?f_search=naru&advsearch=1&f_sname=on&f_spf=&f_spt=
        //https://e-hentai.org/?f_search=naru&advsearch=1&f_sdt1=on&f_spf=&f_spt=
        
        var cacheFavoritesTitles = false
        if var keyword = keyword {
            if keyword.contains("favorites") {
                url = Defaults.URL.host + "/favorites.php?page=\(page)"
                if let number = Int(keyword.replacingOccurrences(of: "favorites", with: "")) {
                    url += "&favcat=\(number)"
                }
                cacheFavoritesTitles = page == 0
            } else if keyword.contains("popular") {
                if page == 0 {
                    url = Defaults.URL.host + "/popular"
                } else {
                    block?([])
                    return
                }
            } else if keyword.contains("watched") {
                 url = Defaults.URL.host + "/watched?page=\(page)"
            } else if keyword.contains(",") {
                if page == 0 {
                    getNewList(with: keyword.components(separatedBy: ","), completeBlock: block)
                } else {
                    block?([])
                }
                return
            } else {
                var skipPage = 0
                if let s = keyword.matches(for: "p:[0-9]+").first, let p = Int(s.replacingOccurrences(of: "p:", with: "")) {
                    keyword = keyword.replacingOccurrences(of: s, with: "")
                    skipPage = p
                }
                url += "&f_search=\(keyword.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!)"
                url += "&page=\(page + skipPage)"
            }
        } else {
            url += "&page=\(page)"
        }
        
        Alamofire.request(url, method: .get).responseString { response in
            guard let html = response.result.value else { block?([]); return }
            if let doc = try? Kanna.HTML(html: html, encoding: .utf8) {
                var items: [Doujinshi] = []
//                for link in doc.xpath("//div [@class='gl3t'] //a") {
//                    if let url = link["href"], let imgNode = link.at_css("img"), let imgUrl = imgNode["src"], let title = imgNode["title"] {
//                for link in doc.xpath("//div [@class='gl1t']") {
//                    if let url = link.xpath("div[1] //a").first?["href"], let imgUrl = link.xpath("div[1] //a //img").first?["src"] , let title = link.xpath("a[1] //div").first?.text  {
//                        items.append(Doujinshi(value: ["coverUrl": imgUrl, "title": title, "url": url]))
//                    }
//                }
                for link in doc.xpath("//div [@class='gl1t']") {
                    
                    var imageUrl: String?
                    var title: String?
                    var url: String?
                    
                    if keyword?.contains("favorites") ?? false {
                        url = link.xpath("div[1] //a").first?["href"]
                        imageUrl = link.xpath("div[2] //a //img").first?["src"]
                        title = link.xpath("div[1] //div //a //span").first?.text
                    } else {
                        imageUrl = link.xpath("div[1] //a //img").first?["src"]
                        title = link.xpath("a[1] //div").first?.text
                        url = link.xpath("div[1] //a").first?["href"]
                    }
                    items.append(Doujinshi(value: ["coverUrl": imageUrl ?? "", "title": title ?? "", "url": url ?? ""]))
                }
                block?(items)
                if cacheFavoritesTitles {
                    DispatchQueue.global(qos: .background).async {
                        let favTitles = doc.xpath("//option [contains(@value, 'fav')]").filter { $0.text != nil }.map { $0.text! }
                        if favTitles.count == 10 { Defaults.List.favoriteTitles = favTitles }
                    }
                }
            } else {
                block?([])
            }
        }
    }
    
    func getDoujinshi(doujinshi: Doujinshi, at page: Int, completeBlock block: (([Page]) -> Void)?, failuedBlock failuedblock: ((_ message: String) -> Void)?) {
        print(#function)
        var url = doujinshi.url + "?p=\(page)"
        url += "&inline_set=ts_l" //Set thumbnal size to large
        if page == 0 {
            url += "&hc=1#comments" //显示所有评论 &hc=1#comments
        }
        Alamofire.request(url, method: .get).responseString { response in
            guard let html = response.result.value else {
                block?([])
                return
            }
            if let doc = try? Kanna.HTML(html: html, encoding: String.Encoding.utf8) {
                
                //check removed
                let p = doc.xpath("//div [@class='d'] //p")
                if p.count > 0 {
                    let p1 = p[0]
                    if p1.text?.contains("unavailable") ?? false || p1.text?.contains("removed") ?? false {
                        failuedblock?(p1.text ?? "")
                    }
                }
                
                //TODO: tag 处理，接口获取的不全
//                let tagKeys = doc.xpath("//div [@id='taglist'] //td [@class='tc']")
//                for i in 0..<tagKeys.count {
//                    let str = tagKeys[i].text
//                    let key = str?.replacingOccurrences(of: ":", with: "")
//                }
                
                var pages: [Page] = []
                for link in doc.xpath("//div [@class='gdtl'] //a") {
                    if let url = link["href"] {
                        if let imgNode = link.at_css("img"), let thumbUrl = imgNode["src"] {
                            let page = Page(value: ["thumbUrl": thumbUrl, "url": url])
                            page.photo = SSPhoto(URL: url)
                            pages.append(page)
                        }
                    }
                }
                
                if page == 0 {
                    doujinshi.isFavorite = doc.xpath("//div [@class='i']").count != 0
                    //Parse comments
                    let commentDateFormatter = DateFormatter()
                    commentDateFormatter.dateFormat = "dd MMMM  yyyy, HH:mm zzz"
                    for c in doc.xpath("//div [@id='cdiv'] //div [@class='c1']") {
                        if let dateAndAuthor = c.at_xpath("div [@class='c2'] /div [@class='c3']")?.text,
                            let author = c.at_xpath("div [@class='c2'] /div [@class='c3'] /a")?.text,
                            let text = c.at_xpath("div [@class='c6']")?.innerHTML {
                            let dateString = dateAndAuthor.replacingOccurrences(of: author, with: "").replacingOccurrences(of: "Posted on ", with: "").replacingOccurrences(of: " by:   ", with: "")
                            let r = Comment(author: author, date: commentDateFormatter.date(from: dateString) ?? Date(), text: text)
                            doujinshi.comments.append(r)
                        }
                    }
                    doujinshi.perPageCount = pages.count
                }
                block?(pages)
            } else {
                block?([])
            }
        }
    }

    func getPageImageUrl(url: String, completeBlock block: ( (_ imageURL: String?) -> Void )?) {
        print(#function)
        Alamofire.request(url, method: .get).responseString { response in
            guard let html = response.result.value else {
                block?(nil)
                return
            }
            if let doc = try? Kanna.HTML(html: html, encoding: String.Encoding.utf8) {
                if let imageNode = doc.at_xpath("//img [@id='img']") {
                    if let imageURL = imageNode["src"] {
                        block?(imageURL)
                        return
                    }
                }
            }
            block?(nil)
        }
    }
    
    private func getNewList(with keywords: [String], completeBlock block: (([Doujinshi]) -> Void)?) {
        print(#function)
        guard keywords.count > 0 else {
            block?([])
            return
        }
        var results: [Doujinshi] = []
        let totalCount = keywords.count
        var completedCount = 0
        for (index, keyword) in keywords.enumerated() {
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .milliseconds(333 * index) ) {
                RequestManager.shared.getList(page: 0, search: keyword, completeBlock: { (books) in
                    results.append(contentsOf: books)
                    completedCount += 1
                    if completedCount == totalCount {
                        block?(results.sorted(by: { $0.id > $1.id }))
                    }
                })
            }
        }
    }

    func getGData( doujinshi: Doujinshi, completeBlock block: ((GData?) -> Void)? ) {
        print(#function)
        //Api http://ehwiki.org/wiki/API
        guard doujinshi.isIdTokenValide else { block?(nil); return}
        
        let p: [String: Any] = [
            "method": "gdata",
            "gidlist": [ [ doujinshi.id, doujinshi.token ] ],
            "namespace": 1
        ]
        
        Alamofire.request(Defaults.URL.host + "/api.php", method: .post, parameters: p, encoding: JSONEncoding(), headers: nil).responseJSON { response in
            if let dic = response.result.value as? NSDictionary {
                if let metadatas = dic["gmetadata"] as? NSArray {
                    if let metadata = metadatas[0] as? NSDictionary {
                        if let count = metadata["filecount"]  as? String,
                            let rating = metadata["rating"] as? String,
                            let category = metadata["category"] as? String,
                            let posted = metadata["posted"] as? String,
                            let title = metadata["title"] as? String,
                            let title_jpn = metadata["title_jpn"] as? String,
                            let tags = metadata["tags"] as? [String],
                            let thumb = metadata["thumb"] as? String,
                            let uploader = metadata["uploader"] as? String,
                            let gid = metadata["gid"] as? Int {
                            let gdata = GData(value: ["filecount": Int(count)!,
                                                      "rating": Float(rating)!,
                                                      "category": category,
                                                      "posted": posted,
                                                      "title": title.isEmpty ? doujinshi.title : title,
                                                      "title_jpn": title_jpn.isEmpty ? doujinshi.title: title_jpn,
                                                      "coverUrl": thumb,
                                                      "gid": String(gid),
                                                      "uploader": uploader])
                            for t in tags {
                                gdata.tags.append(Tag(value: ["name": t]))
                            }
                            block?(gdata)
                            //Cache
                            let cachedURLResponse = CachedURLResponse(response: response.response!, data: response.data!, userInfo: nil, storagePolicy: .allowed)
                            URLCache.shared.storeCachedResponse(cachedURLResponse, for: response.request!)
                            
                            return
                        }
                    }
                }
                block?(nil)
            }
            block?(nil)
        }
    }

    func login(username name: String, password pw: String, completeBlock block: (() -> Void)? ) {
        let url = Defaults.URL.login.absoluteString + "&CODE=01"
        let parameters: [String: String] = [
            "CookieDate": "1",
            "b": "d",
            "bt": "1-1",
            "UserName": name,
            "PassWord": pw,
            "ipb_login_submit": "Login!"]
        Alamofire.request(url, method: .post, parameters: parameters, encoding: URLEncoding(), headers: nil).responseString { _ in
            block?()
        }
    }

    func addDoujinshiToFavorite(doujinshi: Doujinshi, category: Int = 0) {
        guard doujinshi.isIdTokenValide else {return}
        doujinshi.isFavorite = true
        let url = Defaults.URL.host + "/gallerypopups.php?gid=\(doujinshi.id)&t=\(doujinshi.token)&act=addfav"
        let parameters: [String: String] = ["favcat": "\(category)", "favnote": "", "apply": "Add to Favorites", "update": "1"]
        Alamofire.request(url, method: .post, parameters: parameters, encoding: URLEncoding(), headers: nil).responseString { _ in
        }
    }

    func deleteFavorite(doujinshi: Doujinshi) {
        guard doujinshi.isIdTokenValide else {return}
        let url = Defaults.URL.host + "/favorites.php"
        let parameters: [String: Any] = ["ddact": "delete", "modifygids[]": doujinshi.id, "apply": "Apply"]
        Alamofire.request(url, method: .post, parameters: parameters, encoding: URLEncoding(), headers: nil).responseString { _ in
        }
    }
    
    func moveFavorite(doujinshi: Doujinshi, to catogory: Int) {
        guard 0...9 ~= catogory else {return}
        guard doujinshi.isIdTokenValide else {return}
        let url = Defaults.URL.host + "/favorites.php"
        let parameters: [String: Any] = ["ddact": "fav\(catogory)", "modifygids[]": doujinshi.id, "apply": "Apply"]
        Alamofire.request(url, method: .post, parameters: parameters, encoding: URLEncoding(), headers: nil).responseString { _ in
        }
    }
}
