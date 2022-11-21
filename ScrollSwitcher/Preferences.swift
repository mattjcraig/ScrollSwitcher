//
//  Preferences.swift
//  ScrollSwitcher
//
//  Created by Shadowfacts on 9/12/21.
//

import Foundation

struct Preferences {
    
    private static let autoModeKey = "autoMode"
    static var autoMode: AutoMode {
        get {
            AutoMode(rawValue: UserDefaults.standard.integer(forKey: autoModeKey)) ?? .disabled
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: autoModeKey)
        }
    }
    
}

extension Preferences {
    enum AutoMode: Int, Codable, CaseIterable, Equatable {
        case disabled = 0
        case normalWhenMousePresent = 1
        case naturalWhenTrackpadPresent = 2
        
        var displayName: String {
            switch self {
            case .disabled:
                return "Disabled"
            case .normalWhenMousePresent:
                return "Normal when mouse present"
            case .naturalWhenTrackpadPresent:
                return "Natural when trackpad present"
            }
        }
        
        var displayDescription: String {
            switch self {
            case .disabled:
                return "Scroll direction is never changed automatically"
            case .normalWhenMousePresent:
                return "Scroll direction is changed to normal when at least 1 mouse is connected. Optimal for computers with built-in trackpads."
            case .naturalWhenTrackpadPresent:
                return "Scroll direction is changed to natural when at least 1 trackpad is connected. Optimal for computers with rarely-connected trackpads."
            }
        }
    }
}
