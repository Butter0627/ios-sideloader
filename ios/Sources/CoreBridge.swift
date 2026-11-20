import Foundation
import SideloaderCore

enum CoreBridge {
    private static func consume(_ ptr: UnsafeMutablePointer<CChar>?, fallback: String) -> String {
        guard let ptr else { return fallback }
        defer { core_free_string(ptr) }
        return String(cString: ptr)
    }

    static func initializeCore() -> String {
        configureSupportDirectory()
        return consume(core_init(), fallback: "錯誤：core_init 回傳空指標")
    }

    static func configureSupportDirectory() {
        let fm = FileManager.default
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = base.appendingPathComponent("Sideloader", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            dir.path.withCString { cStr in
                core_set_support_dir(cStr)
            }
        }
    }

    static func pairingStatus() -> String {
        configureSupportDirectory()
        return consume(core_pairing_status(), fallback: "錯誤：無法取得配對狀態")
    }

    static func startLocalPairing() -> String {
        configureSupportDirectory()
        return consume(core_start_local_pairing(), fallback: "錯誤：無法啟動本機配對")
    }

    static func appleStatus() -> String {
        consume(core_apple_status(), fallback: "ERR:無法取得 Apple ID 狀態")
    }

    static func appleLogin(email: String, password: String) -> String {
        email.withCString { idPtr in
            password.withCString { pwPtr in
                consume(core_apple_login(idPtr, pwPtr), fallback: "ERR:無法送出 Apple ID 登入")
            }
        }
    }

    static func appleSubmit2FA(code: String) -> String {
        code.withCString { codePtr in
            consume(core_apple_submit_2fa(codePtr), fallback: "ERR:無法送出 2FA 驗證碼")
        }
    }

    static func appleConfirm7460(allowCleanup: Bool) -> String {
        consume(core_apple_confirm_7460(allowCleanup), fallback: "ERR:無法處理 7460 確認")
    }

    static func ipaStatus() -> String {
        consume(core_ipa_status(), fallback: "ERR:無法取得 IPA 狀態")
    }

    static func ipaSelect(path: String) -> String {
        path.withCString { pPtr in
            consume(core_ipa_select(pPtr), fallback: "ERR:無法登記 IPA 路徑")
        }
    }

    static func ipaSignAndInstall(appGroup: String, customBundleId: String) -> String {
        appGroup.withCString { gPtr in
            customBundleId.withCString { bPtr in
                consume(core_ipa_sign_and_install(gPtr, bPtr), fallback: "ERR:無法執行重簽名與安裝")
            }
        }
    }
}
