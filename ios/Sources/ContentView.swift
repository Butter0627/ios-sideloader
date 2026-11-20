import SwiftUI

struct ContentView: View {
    @State private var showAppleLogin = false

    @State private var coreStatus: String = "尚未初始化"
    @State private var pairingStatus: String = "檢查中..."
    @State private var actionMessage: String?

    var body: some View {
        TabView {
            NavigationStack {
                List {

            Button {
                showAppleLogin = true
            } label: {
                Label("Apple ID 登入 / 2FA / 7460", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

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
                            Label("1. 啟動本機配對 (idevice remote_pairing)", systemImage: "antenna.radiowaves.left.and.right")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("2. 請直接點開 iPhone 桌面上的「設定」App")
                                .font(.subheadline.bold())

                            Text("• 依序前往：設定 → 隱私權與安全性 → 開發者模式。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text("• 如果「開發者模式」還沒開啟，請先打開開關並依提示重新啟動 iPhone，再回來繼續。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text("• 如果已經開啟「開發者模式」，請在該頁面進行配對並輸入配對碼。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

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
    
        .sheet(isPresented: $showAppleLogin) {
            AppleIDLoginView()
        }
    }
}
