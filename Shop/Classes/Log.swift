//
//  Created by Akos Polster on 30/10/2017.
//  Copyright © 2017 Pipacs. All rights reserved.
//

import Foundation

/// Log using NSLog
func Log(_ msg: String = "", _ file: NSString = #file, _ function: String = #function) {
    let baseName = file.lastPathComponent
    let line = String(format: "%@ %@ %@", baseName, function, msg)
    NSLog(line)
}
