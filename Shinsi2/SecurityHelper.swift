//
//  SecurityHelper.swift
//  Shinsi2
//
//  Created by 罗超 on 2019/7/25.
//  Copyright © 2019 PowHu Yang. All rights reserved.
//

import Foundation
import UIKit

class SecurityHelper {
    
    static let Instance = SecurityHelper()
    
    fileprivate lazy var bgView: UIView = {
        let bg = Bundle.main.loadNibNamed("SecurityView", owner: nil, options: nil)?[0] as! SecurityView
        return bg
    }()
    
    func showSecurityBackground() {
        bgView.alpha = 0
        UIApplication.shared.keyWindow?.addSubview(bgView)
        
        bgView.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
        
        UIView.animate(withDuration: TimeInterval(0.26)) {
            self.bgView.alpha = 1
        }
    }
    
    func hiddenSecurityBackground() {
        UIView.animate(withDuration: TimeInterval(0.26), animations: {
            self.bgView.alpha = 0
        }, completion: { (_) in
            self.bgView.removeFromSuperview()
        })
    }
}
