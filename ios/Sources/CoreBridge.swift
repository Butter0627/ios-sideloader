import Foundation
import SideloaderCore

enum CoreBridge {
    static func initializeCore() -> String {
        configureSupportDirectory()
        guard let ptr = core_init() else {
            return "錯誤：core_init 回傳空指標"
        }
        defer { core_free_string(ptr) }
        return String(cString: ptr)
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
        guard let ptr = core_pairing_status() else {
            return "錯誤：無法取得配對狀態"
        }
        defer { core_free_string(ptr) }
        return String(cString: ptr)
    }

    static func startLocalPairing() -> String {
        configureSupportDirectory()
        guard let ptr = core_start_local_pairing() else {
            return "錯誤：無法啟動本機配對"
        }
        defer { core_free_string(ptr) }
        return String(cString: ptr)
    }
}
