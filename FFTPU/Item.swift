//
//  Item.swift
//  FFTPU
//
//  Created by Jonas on 2025-04-17.
//

// This file is left in place for backward compatibility but is no longer used.
// See the Models directory for the updated data models.

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
