import UIKit

protocol CommentVCDelegate: class {
    func commentVC(_ vc: CommentVC, didTap url: URL)
    func commentVC(_ vc: CommentVC, didTap author: String)
}

class CommentVC: BaseViewController, UITableViewDelegate, UITableViewDataSource, UITextViewDelegate {
    
    weak var doujinshi: Doujinshi!
    @IBOutlet weak var tableView: UITableView!
    private var backGesture: InteractiveBackGesture?
    weak var delegate: CommentVCDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.barTintColor = UIColor(white: 0, alpha: 0.5)
        backGesture = InteractiveBackGesture(viewController: self, toView: tableView, mode: .modal, isSimultaneously: true)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return doujinshi.comments.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CommentCell
        let c = doujinshi.comments[indexPath.row]
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm"
        cell.dateLabel.text = df.string(from: c.date)
        //给名字加下划线
        //cell.authorButton.setTitle(c.author, for: .normal)
        let attributes: [NSAttributedString.Key: Any] = [ .underlineStyle: NSUnderlineStyle.single.rawValue ]
        let attriTitle = NSAttributedString(string: c.author, attributes: attributes)
        cell.authorButton.setAttributedTitle(attriTitle, for: .normal)
        
        cell.commentTextView.attributedText = c.htmlAttributedText
        cell.authorTouched = authorTouched
        return cell
    }
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        delegate?.commentVC(self, didTap: URL)
        return false
    }
    
    @objc private func authorTouched(_ author: String) {
        let string = "uploader:" + author
        delegate?.commentVC(self, didTap: string)
    }

}
