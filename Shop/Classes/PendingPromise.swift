//
//  Created by Akos Polster on 17/12/2017.
//  Copyright © 2017 Pipacs. All rights reserved.
//

import PromiseKit

/// A pending promise of type T
typealias PendingPromise<T> = (promise: Promise<T>, resolver: Resolver<T>)
