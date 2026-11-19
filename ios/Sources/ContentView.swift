import SwiftUI

struct ContentView: View {
    @State private var coreStatus: String = "尚未初始化"

    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section("核心引擎狀態 (Stage 1)") {
                        Text(coreStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Section("下一步預告 (Stage 2)") {
                        Label("LocalDevVPN 本機遠端配對", systemImage: "link.badge.plus")
                        Label("Apple ID 登入與憑證管理", systemImage: "person.badge.key")
                        Label("IPA 重簽名 (含 App Group) 與安裝", systemImage: "square.and.arrow.down")
                    }
                }
                .navigationTitle("MySideloader")
                .onAppear {
                    coreStatus = CoreBridge.initializeCore()
                }
            }
            .tabItem {
                Label("首頁", systemImage: "house")
            }

            NavigationStack {
                Text("將於 Stage 2 實作選取 IPA 與安裝")
                    .foregroundStyle(.secondary)
                    .navigationTitle("安裝 IPA")
            }
            .tabItem {
                Label("安裝", systemImage: "plus.app")
            }
        }
    }
}
