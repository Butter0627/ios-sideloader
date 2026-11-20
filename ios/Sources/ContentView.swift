import SwiftUI

struct ContentView: View {
    @State private var coreStatus: String = "尚未初始化"
    @State private var pairingStatus: String = "檢查中..."
    @State private var actionMessage: String?

    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section("核心引擎狀態 (Stage 1)") {
                        Text(coreStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Section("本機遠端配對 (iOS 27+ / LocalDevVPN)") {
                        Text(pairingStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button {
                            actionMessage = CoreBridge.startLocalPairing()
                            pairingStatus = CoreBridge.pairingStatus()
                        } label: {
                            Label("開始本機配對 (產生配對碼)", systemImage: "antenna.radiowaves.left.and.right")
                        }

                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("前往系統設定輸入配對碼", systemImage: "gear")
                        }

                        if let msg = actionMessage {
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                        }
                    }

                    Section("後續 Stage 2 項目") {
                        Label("Apple ID 登入與憑證管理 (含 7460 確認)", systemImage: "person.badge.key")
                        Label("IPA 重簽名 (含 App Group) 與安裝", systemImage: "square.and.arrow.down")
                    }
                }
                .navigationTitle("MySideloader")
                .onAppear {
                    coreStatus = CoreBridge.initializeCore()
                    pairingStatus = CoreBridge.pairingStatus()
                }
            }
            .tabItem {
                Label("首頁", systemImage: "house")
            }

            NavigationStack {
                Text("將於下一步實作選取 IPA 與安裝")
                    .foregroundStyle(.secondary)
                    .navigationTitle("安裝 IPA")
            }
            .tabItem {
                Label("安裝", systemImage: "plus.app")
            }
        }
    }
}
