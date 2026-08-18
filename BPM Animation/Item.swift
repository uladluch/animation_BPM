//
//  Item.swift
//  BPM Animation
//
//  Created by Ulad Luch on 18/08/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
