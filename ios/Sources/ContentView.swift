import SwiftUI

struct ContentView: View {
    @State private var showAppleLogin = false
    @State private var showIPASigner = false

    @State private var coreStatus: String = "尚未初始化"
    @State private var pairingStatus: String = "檢查中..."
    @State private var actionMessage: String?

    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section("帳號與重簽名") {
                        Button {
                            showAppleLogin = true
                        } label: {
                            Label("Apple ID 登入 / 2FA / 7460", systemImage: "person.crop.circle.badge.checkmark")
                        }

                        Button {
                            showIPASigner = true
                        } label: {
                            Label("選取 IPA / App Group 重簽名與安裝", systemImage: "app.badge.checkmark")
                        }
                    }

                    Section("核心與配對狀態") {
                        LabeledContent("核心引擎", value: coreStatus)
                        LabeledContent("遠端配對", value: pairingStatus)

                        Button {
                            actionMessage = CoreBridge.startLocalPairing()
                            refreshStatuses()
                        } label: {
                            Label("啟動本機配對 (idevice remote_pairing)", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }

                    Section("iPhone 設定指引") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. 開啟 iPhone「設定」App")
                                .font(.subheadline.weight(.semibold))

                            Text("前往「設定 → 隱私權與安全性 → 開發者模式」，確認開關已開啟並依提示完成重新啟動。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text("若已開啟開發者模式，請在該頁面完成配對並確認配對碼。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    if let msg = actionMessage, !msg.isEmpty {
                        Section("最近操作訊息") {
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .navigationTitle("MySideloader")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            refreshStatuses()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("重新整理狀態")
                    }
                }
                .onAppear {
                    coreStatus = CoreBridge.initializeCore()
                    pairingStatus = CoreBridge.pairingStatus()
                }
            }
            .tabItem {
                Label("首頁", systemImage: "house")
            }

            NavigationStack {
                List {
                    Section("IPA 側載流程") {
                        Button {
                            showIPASigner = true
                        } label: {
                            Label("開啟 IPA 選取與重簽名", systemImage: "plus.app")
                        }
                    }

                    Section("目前環境摘要") {
                        LabeledContent("核心狀態", value: coreStatus)
                        LabeledContent("配對狀態", value: pairingStatus)
                    }
                }
                .navigationTitle("安裝")
            }
            .tabItem {
                Label("安裝", systemImage: "plus.app")
            }
        }
        .sheet(isPresented: $showAppleLogin) {
            AppleIDLoginView()
        }
        .sheet(isPresented: $showIPASigner) {
            IPASignerInstallView()
        }
    }

    private func refreshStatuses() {
        pairingStatus = CoreBridge.pairingStatus()
    }
}
