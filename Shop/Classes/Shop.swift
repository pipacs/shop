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
    public static let domain = "com.pipacs.Shop"
    public static let ErrorInvalidProduct = NSError(domain: domain, code: 1)
    public static let ErrorPurchasePending = NSError(domain: domain, code: 2)
    
    /// App Store receipt is missing or invalid
    public static let ErrorReceipt = NSError(domain, code: 3)
    
    /// Transaction (purchase or restoring purchases) failed
    public static let ErrorTransaction = NSError(domain, code: 4)

    /// Available products, indexed by product ID
    public private(set) var products: [String: SKProduct] = [:]
    
    private var pendingRestores: [PendingPromise<Void>] = []
    private var pendingPurchases: [String: PendingPromise<Void>] = [:]
    private var productsRequests: [SKProductsRequest] = []
    private var receiptRefreshRequests: [SKReceiptRefreshRequest] = []
    private var pendingReceiptRefreshes: [PendingPromise<Void>] = []
    private let keychain = KeychainSwift(keyPrefix: Shop.domain)
    private let productIds: Set<String>

    public required init(productIds: Set<String>) {
        Log()
        self.productIds = productIds
        super.init()
        SKPaymentQueue.default().add(self)
        let request = SKProductsRequest(productIdentifiers: productIds)
        request.delegate = self
        productsRequests.append(request)
        request.start()
    }

    public func has(productId: String) -> Bool {
        return count(of: productId) > 0
    }

    public func count(of productId: String) -> Int {
        return keychain.getInt(productId) ?? 0
    }
    
    public func purchase(productId: String) -> Promise<Void> {
        Log("\(productId)")
        guard let product = products[productId] else {
            return Promise(error: Shop.ErrorInvalidProduct)
        }
        if let oldPendingPurchase = pendingPurchases[productId], oldPendingPurchase.promise.isPending {
            return Promise(error: Shop.ErrorPurchasePending)
        }

        let pendingPurchase = Promise<Void>.pending()
        let payment = SKPayment(product: product)
        self.pendingPurchases[productId] = pendingPurchase
        SKPaymentQueue.default().add(payment)

        return pendingPurchase.promise
    }
    
    /// Restore the App Store receipt, then the purchases
    func restorePurchases() -> Promise<Void> {
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

    public func removeAllPurchases() {
        for id in productIds {
            keychain.set(0, forKey: id)
        }
    }

    public func purchaseAll() {
        for id in productIds {
            keychain.set(1, forKey: id)
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
            Log("Removing producs")
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
                pendingPurchase.resolver.reject(transaction.error ?? Shop.ErrorTransaction)
            case .purchased:
                Log("Purchased")
                queue.finishTransaction(transaction)
                if !verifyReceipt(productId: productId) {
                    pendingPurchase.resolver.reject(Shop.ErrorReceipt)
                } else {
                    let count = keychain.getInt(productId) ?? 0
                    keychain.set(count + 1, forKey: productId)
                    pendingPurchase.resolver.fulfill(())
                }
            case .restored:
                Log("Restored")
                queue.finishTransaction(transaction)
                if !verifyReceipt(productId: productId) {
                    keychain.set(0, forKey: productId)
                    pendingPurchase.resolver.reject(Shop.ErrorReceipt)
                } else {
                    keychain.set(1, forKey: productId)
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
    
    // MARK: - Private
    
    /// Promise refreshing the receipt of all IAPs
    private func refreshReceipt() -> Promise<Void> {
        Log()
        if let receiptURL = Bundle.main.appStoreReceiptURL, let isReachable = try? receiptURL.checkResourceIsReachable(), isReachable {
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
    private func doRestorePurchases() -> Promise<Void> {
        Log()
        SKPaymentQueue.default().restoreCompletedTransactions()
        let pendingRestore = Promise<Void>.pending()
        pendingRestores.append(pendingRestore)
        return pendingRestore.promise
    }
    
    /// Verify if the App Store receipt contains a given product ID
    private func verifyReceipt(productId: String) -> Bool {
        Log()
        guard let receipt = AppStoreReceipt() else {
            return false
        }
        return receipt.contains(productId: productId)
    }
}
