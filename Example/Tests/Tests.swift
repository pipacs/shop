// Copyright (c) Akos Polster. All rights reserved.

import KeychainSwift
import PromiseKit
@testable import Shop
import StoreKit
import XCTest

class Tests: XCTestCase {
    class TestProduct: SKProduct {
        var _productIdentifier: String = ""
        override var productIdentifier: String { return _productIdentifier }
        
        init(productIdentifier: String) {
            _productIdentifier = productIdentifier
            super.init()
        }
    }
    
    class TestProductResponse: SKProductsResponse {
        let _products: [SKProduct]
        let _invalidProductIdentifiers: [String]
        override var products: [SKProduct] { return _products }
        override var invalidProductIdentifiers: [String] { return _invalidProductIdentifiers }
        
        init(products: [SKProduct], invalidProductIdentifiers: [String]) {
            _products = products
            _invalidProductIdentifiers = invalidProductIdentifiers
            super.init()
        }
    }
    
    class TestPayment: SKPayment {
        let _productIdentifier: String
        let _quantity: Int
        override var productIdentifier: String { return _productIdentifier }
        override var quantity: Int { return _quantity }
        
        init(productIdentifier: String, quantity: Int = 1) {
            _productIdentifier = productIdentifier
            _quantity = quantity
            super.init()
        }
    }
    
    class TestPaymentTransaction: SKPaymentTransaction {
        let _payment: SKPayment
        let _transactionState: SKPaymentTransactionState
        override var payment: SKPayment { return _payment }
        override var transactionState: SKPaymentTransactionState { return _transactionState }
        
        init(payment: SKPayment, transactionState: SKPaymentTransactionState) {
            _payment = payment
            _transactionState = transactionState
            super.init()
        }
    }
    
    class TestPaymentQueue: SKPaymentQueue {
        override func finishTransaction(_ transaction: SKPaymentTransaction) {}
    }
    
    func testUpdatingTransactions() {
        let s = Shop(consumableProductIds: ["foo", "bar"])
        s.removeAllPurchasesLocally()
        s.pendingPurchases["foo"] = Promise<Void>.pending()
        s.pendingPurchases["bar"] = Promise<Void>.pending()
        let t1 = TestPaymentTransaction(payment: TestPayment(productIdentifier: "foo"), transactionState: .purchased)
        let t2 = TestPaymentTransaction(payment: TestPayment(productIdentifier: "bar"), transactionState: .failed)
        let t3 = TestPaymentTransaction(payment: TestPayment(productIdentifier: "baz"), transactionState: .failed)
        s.paymentQueue(TestPaymentQueue(), updatedTransactions: [t1, t2, t3])
        XCTAssertEqual(s.pendingPurchases["foo"]?.promise.isResolved, true)
        XCTAssertEqual(s.count(of: "foo"), 1)
        XCTAssertEqual(s.pendingPurchases["bar"]?.promise.isRejected, true)
        XCTAssertEqual(s.count(of: "bar"), 0)
        s.paymentQueue(TestPaymentQueue(), updatedTransactions: [t1])
        XCTAssertEqual(s.count(of: "foo"), 1)
    }

    func testProductsResponse() {
        let s = Shop()
        let p = TestProduct(productIdentifier: "foo")
        let productsReq = SKProductsRequest(productIdentifiers: ["foo", "bar"])
        let productsResp = TestProductResponse(products: [p], invalidProductIdentifiers: ["bar"])
        s.productsRequest(productsReq, didReceive: productsResp)
        XCTAssertEqual(s.products["foo"], p)
        XCTAssertNil(s.products["bar"])
        
        let e = Shop.errorTransaction
        s.request(productsReq, didFailWithError: e)
        XCTAssertEqual(s.products.count, 0)
    }
    
    func testReceiptResponse() {
        let s = Shop()
        let pendingReceiptRefresh = Promise<Void>.pending()
        s.pendingReceiptRefreshes = [pendingReceiptRefresh]
        s.request(SKReceiptRefreshRequest(), didFailWithError: Shop.errorTransaction)
        XCTAssertEqual(s.pendingReceiptRefreshes.count, 0)
        XCTAssertTrue(pendingReceiptRefresh.promise.isRejected)
    }
    
    func testRestorePurchases() {
        let s = Shop()
        let q = SKPaymentQueue()
        let pending1 = Promise<Void>.pending()
        s.pendingRestores = [pending1]
        s.paymentQueueRestoreCompletedTransactionsFinished(q)
        XCTAssertEqual(s.pendingRestores.count, 0)
        XCTAssertTrue(pending1.promise.isFulfilled)
        let e = Shop.errorTransaction
        let pending2 = Promise<Void>.pending()
        s.pendingRestores = [pending2]
        s.paymentQueue(q, restoreCompletedTransactionsFailedWithError: e)
        XCTAssertEqual(s.pendingRestores.count, 0)
        XCTAssertTrue(pending2.promise.isRejected)
        XCTAssertEqual(pending2.promise.error as NSError?, e)
    }
    
    func testKeychainExtensions() {
        let k = KeychainSwift(keyPrefix: "test")
        k.delete("foo")
        XCTAssertEqual(k.getInt("foo"), 0)
        k.set(42, forKey: "foo")
        XCTAssertEqual(k.getInt("foo"), 42)
    }
    
    func testLocally() {
        let s = Shop(consumableProductIds: ["foo"], nonConsumableProductIds: ["bar"])
        s.removeAllPurchasesLocally()
        XCTAssertEqual(s.count(of: "foo"), 0)
        XCTAssertEqual(s.count(of: "bar"), 0)
        s.purchaseAllLocally()
        XCTAssertEqual(s.count(of: "foo"), 1)
        XCTAssertEqual(s.count(of: "bar"), 1)
        XCTAssertFalse(s.consume(productId: "bar"))
        XCTAssertTrue(s.consume(productId: "foo"))
        XCTAssertEqual(s.count(of: "foo"), 0)
        XCTAssertEqual(s.count(of: "bar"), 1)
        XCTAssertFalse(s.has(productId: "foo"))
        XCTAssertTrue(s.has(productId: "bar"))
        XCTAssertFalse(s.consume(productId: "foo"))
        XCTAssertEqual(s.count(of: "foo"), 0)
        s.setCount(of: "foo", 3)
        XCTAssertEqual(s.count(of: "foo"), 3)
    }
}
