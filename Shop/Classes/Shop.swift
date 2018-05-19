//
//  Created by Akos Polster on 15/04/2017.
//  Copyright © 2017 Pipacs. All rights reserved.
//

import Foundation
import KeychainSwift
import PromiseKit
import StoreKit

/// A shop with products to purchase
public class Shop: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver, SKRequestDelegate {
    /// Framework domain
    public static let domain = "com.pipacs.Shop"
    
    /// Product ID is invalid
    public static let errorInvalidProduct = NSError(domain: domain, code: 1)
    
    /// Another purchase is pending
    public static let errorPurchasePending = NSError(domain: domain, code: 2)
    
    /// App Store receipt verification failed
    public static let errorReceipt = NSError(domain: domain, code: 3)
    
    /// Transaction (purchase or restoring purchases) failed
    public static let errorTransaction = NSError(domain: domain, code: 4)
    
    /// Non-consumable product IDs
    public let nonConsumableProductIds: Set<String>
    
    /// Consumable product IDs
    public let consumableProductIds: Set<String>

    /// Available products, indexed by product ID
    public private(set) var products: [String: SKProduct] = [:]
    
    var pendingRestores: [PendingPromise<Void>] = []
    var pendingPurchases: [String: PendingPromise<Void>] = [:]
    var productsRequests: [SKProductsRequest] = []
    var receiptRefreshRequests: [SKReceiptRefreshRequest] = []
    var pendingReceiptRefreshes: [PendingPromise<Void>] = []
    let keychain = KeychainSwift(keyPrefix: Shop.domain)
    let receiptVerifier: ((String, URL) -> Bool)?
    let receiptURL: URL?

    /// Initializer
    ///
    /// - Parameters:
    ///   - consumableProductIds: Set of consumable product IDs
    ///   - nonConsumableProductIds: Set of non-consumable product IDs
    ///   - receiptURL: Location of the App Store receipt
    ///   - receiptVerifier: Method verifying the given product ID in the App Store receipt
    public required init(
        consumableProductIds: Set<String> = Set(),
        nonConsumableProductIds: Set<String> = Set(),
        receiptURL: URL? = nil,
        receiptVerifier: ((String, URL) -> Bool)? = nil
    ) {
        Log()
        self.consumableProductIds = consumableProductIds
        self.nonConsumableProductIds = nonConsumableProductIds
        self.receiptURL = receiptURL
        self.receiptVerifier = receiptVerifier
        super.init()
        SKPaymentQueue.default().add(self)
        let request = SKProductsRequest(productIdentifiers: consumableProductIds.union(nonConsumableProductIds))
        request.delegate = self
        productsRequests.append(request)
        request.start()
    }

    /// Does the user have one or more instances of the given product
    public func has(productId: String) -> Bool {
        return count(of: productId) > 0
    }

    /// Current count of a given product
    public func count(of productId: String) -> Int {
        return keychain.getInt(productId) ?? 0
    }
    
    /// Purchase a product
    public func purchase(productId: String) -> Promise<Void> {
        Log("\(productId)")
        guard let product = products[productId] else {
            return Promise(error: Shop.errorInvalidProduct)
        }
        if let oldPendingPurchase = pendingPurchases[productId], oldPendingPurchase.promise.isPending {
            return Promise(error: Shop.errorPurchasePending)
        }

        let pendingPurchase = Promise<Void>.pending()
        let payment = SKPayment(product: product)
        self.pendingPurchases[productId] = pendingPurchase
        SKPaymentQueue.default().add(payment)

        return pendingPurchase.promise
    }
    
    /// Consume an instance of a consumable product
    @discardableResult
    public func consume(productId: String) -> Bool {
        if !consumableProductIds.contains(productId) {
            Log("Attempting to consume a non-consumable product")
            return false
        }
        let cnt = count(of: productId)
        if cnt < 1 {
            Log("No more products to consume")
            return false
        }
        setCount(of: productId, cnt - 1)
        return true
    }
    
    /// Restore purchases
    /// - Note: If the App Store receipt URL (set in ```init```) is non-nil,
    /// this method will attempt to restore the receipt first
    public func restorePurchases() -> Promise<Void> {
        Log()
        return Promise { seal in
            firstly { () -> Promise<Void> in
                self.refreshReceipt()
            }.then { _ -> Promise<Void> in
                self.doRestorePurchases()
            }.done {
                seal.fulfill(())
            }.catch { error in
                seal.reject(error)
            }
        }
    }

    /// Remove all local product instances
    public func removeAllPurchasesLocally() {
        for id in consumableProductIds.union(nonConsumableProductIds) {
            setCount(of: id, 0)
        }
    }

    /// Set all non-consumable product instance counts to 1, increment all consumable product instance counts
    public func purchaseAllLocally() {
        for id in consumableProductIds {
            setCount(of: id, count(of: id) + 1)
        }
        for id in nonConsumableProductIds {
            setCount(of: id, 1)
        }
    }
    
    // MARK: - Delegates

    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        Log()
        pendingRestores.forEach { $0.resolver.fulfill(()) }
        pendingRestores.removeAll()
    }

    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        Log("\(error)")
        pendingRestores.forEach { $0.resolver.reject(error) }
        pendingRestores.removeAll()
    }

    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Log()
        for product in response.products {
            Log("Valid: \(product.productIdentifier)")
            self.products[product.productIdentifier] = product
        }
        for productId in response.invalidProductIdentifiers {
            Log("Invalid: \(productId)")
        }
    }

    public func request(_ request: SKRequest, didFailWithError error: Error) {
        Log("Request \(request): \(error)")
        if request.isKind(of: SKProductsRequest.self) {
            Log("Removing products")
            self.products.removeAll()
        } else if request.isKind(of: SKReceiptRefreshRequest.self) {
            Log("Rejecting receipt requests")
            pendingReceiptRefreshes.forEach { $0.resolver.reject(error) }
            pendingReceiptRefreshes.removeAll()
        }
    }

    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Log()
        for transaction in transactions {
            let productId = transaction.payment.productIdentifier
            guard let pendingPurchase = self.pendingPurchases[productId] else {
                continue
            }
            if !pendingPurchase.promise.isPending {
                continue
            }
            switch transaction.transactionState {
            case .failed:
                Log("Failed: \(String(describing: transaction.error))")
                queue.finishTransaction(transaction)
                pendingPurchase.resolver.reject(transaction.error ?? Shop.errorTransaction)
            case .purchased:
                Log("Purchased")
                queue.finishTransaction(transaction)
                if let url = receiptURL, receiptVerifier?(productId, url) == false {
                    pendingPurchase.resolver.reject(Shop.errorReceipt)
                } else {
                    let quantity = transaction.payment.quantity
                    setCount(of: productId, count(of: productId) + quantity)
                    pendingPurchase.resolver.fulfill(())
                }
            case .restored:
                Log("Restored")
                queue.finishTransaction(transaction)
                if let url = receiptURL, receiptVerifier?(productId, url) == false {
                    keychain.set(0, forKey: productId)
                    pendingPurchase.resolver.reject(Shop.errorReceipt)
                } else {
                    keychain.set(transaction.payment.quantity, forKey: productId)
                    pendingPurchase.resolver.fulfill(())
                }
            case .purchasing:
                Log("Purchasing")
            case .deferred:
                Log("Deferred")
                pendingPurchase.resolver.fulfill(())
            }
        }
    }
    
    // MARK: - Internal
    
    /// Promise refreshing the receipt of all IAPs
    func refreshReceipt() -> Promise<Void> {
        Log()
        guard let receiptURL = receiptURL else {
            return .value(())
        }
        if let isReachable = try? receiptURL.checkResourceIsReachable(), isReachable {
            return .value(())
        }
        let pending = Promise<Void>.pending()
        pendingReceiptRefreshes.append(pending)
        let request = SKReceiptRefreshRequest()
        request.delegate = self
        receiptRefreshRequests.append(request)
        request.start()
        return pending.promise
    }
    
    /// Restore purchases only
    func doRestorePurchases() -> Promise<Void> {
        Log()
        SKPaymentQueue.default().restoreCompletedTransactions()
        let pendingRestore = Promise<Void>.pending()
        pendingRestores.append(pendingRestore)
        return pendingRestore.promise
    }
    
    /// Set the count of a product ID
    func setCount(of productId: String, _ count: Int) {
        keychain.set(count, forKey: productId)
    }
}
