//
//  Direction.swift
//  ScrollSwitcher
//
//  Created by Shadowfacts on 9/12/21.
//

import AppKit

let defaultsKey = "com.apple.swipescrolldirection"

enum Direction: Equatable {
    case normal, natural
    
    static var current: Direction {
        let value = UserDefaults.standard.bool(forKey: defaultsKey)
        if value {
            return .natural
        } else {
            return .normal
        }
    }
    
    var image: NSImage {
        switch self {
        case .normal:
            return NSImage(systemSymbolName: "magicmouse", accessibilityDescription: nil)!
        case .natural:
            return NSImage(systemSymbolName: "rectangle.and.hand.point.up.left", accessibilityDescription: nil)!
        }
    }
}

