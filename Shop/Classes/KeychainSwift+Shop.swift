//
//  Created by Akos Polster on 13/05/2018.
//  Copyright © 2018 Pipacs. All rights reserved.
//

import KeychainSwift

extension KeychainSwift {
    /// Get an integer from the Keychain
    func getInt(_ key: String) -> Int? {
        guard let value = get(key) else {
            return 0
        }
        return Int(value)
    }

    /// Set an integer on the Keychain
    @discardableResult
    func set(_ value: Int, forKey key: String, withAccess access: KeychainSwiftAccessOptions? = nil) -> Bool {
        return set(String(value), forKey: key, withAccess: access)
    }
}
