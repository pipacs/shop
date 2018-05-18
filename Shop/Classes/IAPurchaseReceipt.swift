//
//  Created by Akos Polster on 15/05/2018.
//  Copyright © 2018 Pipacs. All rights reserved.
//

import Foundation

/// Receipt for an in-app purchase
struct IAPurchaseReceipt {
    var quantity: Int? = nil
    var productIdentifier: String? = nil
    var transactionIdentifier: String? = nil
    var originalTransactionIdentifier: String? = nil
    var purchaseDate: Date? = nil
    var originalPurchaseDate: Date? = nil
    var subscriptionExpirationDate: Date? = nil
    var cancellationDate: Date? = nil
    var webOrderLineItemID: Int? = nil
    
    init(with asn1Data: UnsafePointer<UInt8>, len: Int) {
        var ptr: UnsafePointer<UInt8>? = asn1Data
        let end = asn1Data.advanced(by: len)
        var type: Int32 = 0
        var xclass: Int32 = 0
        var length = 0
        ASN1_get_object(&ptr, &length, &type, &xclass, Int(len))
        guard type == V_ASN1_SET else {
            return
        }
        while ptr! < end {
            ASN1_get_object(&ptr, &length, &type, &xclass, ptr!.distance(to: end))
            guard type == V_ASN1_SEQUENCE else {
                return
            }
            
            guard let attrType = ASN1ReadInteger(pointer: &ptr, length: ptr!.distance(to: end)) else {
                return
            }
            
            guard let _ = ASN1ReadInteger(pointer: &ptr, length: ptr!.distance(to: end)) else {
                return
            }
            
            ASN1_get_object(&ptr, &length, &type, &xclass, ptr!.distance(to: end))
            guard type == V_ASN1_OCTET_STRING else {
                return
            }
            
            switch attrType {
            case 1701:
                var p = ptr
                self.quantity = ASN1ReadInteger(pointer: &p, length: length)
            case 1702:
                var p = ptr
                self.productIdentifier = ASN1ReadString(pointer: &p, length: length)
            case 1703:
                var p = ptr
                self.transactionIdentifier = ASN1ReadString(pointer: &p, length: length)
            case 1705:
                var p = ptr
                self.originalTransactionIdentifier = ASN1ReadString(pointer: &p, length: length)
            case 1704:
                var p = ptr
                self.purchaseDate = ASN1ReadDate(pointer: &p, length: length)
            case 1706:
                var p = ptr
                self.originalPurchaseDate = ASN1ReadDate(pointer: &p, length: length)
            case 1708:
                var p = ptr
                self.subscriptionExpirationDate = ASN1ReadDate(pointer: &p, length: length)
            case 1712:
                var p = ptr
                self.cancellationDate = ASN1ReadDate(pointer: &p, length: length)
            case 1711:
                var p = ptr
                self.webOrderLineItemID = ASN1ReadInteger(pointer: &p, length: length)
            default:
                break
            }
            ptr = ptr?.advanced(by: length)
        }
    }
}
