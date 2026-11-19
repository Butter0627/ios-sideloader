import Foundation
import SideloaderCore

enum CoreBridge {
    static func initializeCore() -> String {
        guard let ptr = core_init() else {
            return "錯誤：core_init 回傳空指標"
        }
        defer { core_free_string(ptr) }
        return String(cString: ptr)
    }
}
