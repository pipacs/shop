//
//  Created by Akos Polster on 15/05/2018.
//  Copyright © 2018 Pipacs. All rights reserved.
//

import Foundation

/// Receipt from the App Store
struct AppStoreReceipt {
    var bundleIdData: NSData?
    var bundleIdString: String?
    var bundleVersionString: String?
    var opaqueData: NSData?
    var hashData: NSData?
    var iapReceipts: [IAPurchaseReceipt] = []
    var expirationDate: Date?

    /// Initialize from data at the given URL; fail if the data is invalid or missing
    init?(receiptURL: URL? = Bundle.main.appStoreReceiptURL) {
        // Verify the receipt is signed by Apple
        guard
            let receiptURL = receiptURL,
            let certificateURL = Bundle.main.url(forResource: "AppleIncRootCertificate", withExtension: "cer"),
            let receiptData = NSData(contentsOf: receiptURL),
            let certificateData = NSData(contentsOf: certificateURL)
        else {
            ogLog("Can't read receipt")
            return nil
        }
        let bio = BIOWrapper(data: receiptData)
        let p7: UnsafeMutablePointer<PKCS7>? = d2i_PKCS7_bio(bio.bio, nil)
        if p7 == nil {
            ogLog("Invalid PKCS #7 container")
            return nil
        }
        OpenSSL_add_all_digests()
        let x509Store = X509StoreWrapper()
        let certificate = X509Wrapper(data: certificateData)
        x509Store.addCert(x509: certificate)
        let payload = BIOWrapper()
        guard PKCS7_verify(p7!, nil, x509Store.store, nil, payload.bio, 0) == 1 else {
            ogLog("Failed to verify PKCS #7 container")
            return nil
        }
        
        // Parse the receipt
        if
            let contents = p7!.pointee.d.sign.pointee.contents,
            OBJ_obj2nid(contents.pointee.type) == NID_pkcs7_data,
            let octets = contents.pointee.d.data
        {
            var ptr: UnsafePointer? = UnsafePointer(octets.pointee.data)
            let end = ptr!.advanced(by: Int(octets.pointee.length))
            var type: Int32 = 0
            var xclass: Int32 = 0
            var length = 0
            ASN1_get_object(&ptr, &length, &type, &xclass,Int(octets.pointee.length))
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
                case 2:
                    var strPtr = ptr
                    self.bundleIdData = NSData(bytes: strPtr, length: length)
                    self.bundleIdString = ASN1ReadString(pointer: &strPtr, length: length)
                case 3:
                    var strPtr = ptr
                    self.bundleVersionString = ASN1ReadString(pointer: &strPtr, length: length)
                case 4:
                    self.opaqueData = NSData(bytes: ptr!, length: length)
                case 5:
                    self.hashData = NSData(bytes: ptr!, length: length)
                case 17:
                    let p = ptr
                    let iapReceipt = IAPurchaseReceipt(with: p!, len: length)
                    self.iapReceipts.append(iapReceipt)
                case 21:
                    var strPtr = ptr
                    self.expirationDate = ASN1ReadDate(pointer: &strPtr, length: length)
                default:
                    break
                }
                ptr = ptr?.advanced(by: length)
            }
        }
        
        // Verify receipt fields
        if bundleIdString == nil || (Bundle.main.bundleIdentifier != bundleIdString) {
            ogLog("Bundle ID doesn't match: \(String(describing: bundleIdString))")
            return nil
        }
        if hashData != computedHashData() {
            ogLog("Hash doesn't match")
            return nil
        }
    }
    
    /// Does the receipt contain a given IAP product ID?
    func contains(productId: String) -> Bool {
        for iap in iapReceipts where iap.productIdentifier == productId {
            return true
        }
        return false
    }
    
    private func computedHashData() -> NSData {
        let device = UIDevice.current
        var uuid = device.identifierForVendor?.uuid
        let address = withUnsafePointer(to: &uuid) { UnsafeRawPointer($0) }
        let data = NSData(bytes: address, length: 16)
        var hash = Array<UInt8>(repeating: 0, count: 20)
        var ctx = SHA_CTX()
        SHA1_Init(&ctx)
        SHA1_Update(&ctx, data.bytes, data.length)
        SHA1_Update(&ctx, opaqueData!.bytes, opaqueData!.length)
        SHA1_Update(&ctx, bundleIdData!.bytes, bundleIdData!.length)
        SHA1_Final(&hash, &ctx)
        return NSData(bytes: &hash, length: 20)
    }
}
