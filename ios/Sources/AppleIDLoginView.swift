import SwiftUI

enum AppleAuthPhase: Equatable {
    case loggedOut
    case awaiting2FA(prompt: String)
    case awaiting7460Confirm(message: String)
    case authenticated(summary: String)
}

@MainActor
final class AppleAuthViewModel: ObservableObject {
    @Published var appleId: String = ""
    @Published var password: String = ""
    @Published var twoFactorCode: String = ""
    @Published var statusMessage: String = "尚未登入 Apple ID"
    @Published var isBusy: Bool = false
    @Published var phase: AppleAuthPhase = .loggedOut
    @Published var show7460Alert: Bool = false
    @Published var certLimitMessage: String = ""

    func refreshStatus() {
        applyRawState(CoreBridge.appleStatus())
    }

    func login() {
        isBusy = true
        defer { isBusy = false }
        applyRawState(CoreBridge.appleLogin(email: appleId, password: password))
    }

    func submit2FA() {
        isBusy = true
        defer { isBusy = false }
        applyRawState(CoreBridge.appleSubmit2FA(code: twoFactorCode))
    }

    func confirm7460(allowCleanup: Bool) {
        show7460Alert = false
        isBusy = true
        defer { isBusy = false }
        applyRawState(CoreBridge.appleConfirm7460(allowCleanup: allowCleanup))
    }

    private func applyRawState(_ raw: String) {
        if let rest = raw.stripPrefix("CERT_LIMIT_7460:") {
            let text = String(rest)
            statusMessage = text
            certLimitMessage = text
            phase = .awaiting7460Confirm(message: text)
            show7460Alert = true
        } else if let rest = raw.stripPrefix("NEED_2FA:") {
            let text = String(rest)
            statusMessage = text
            phase = .awaiting2FA(prompt: text)
        } else if let rest = raw.stripPrefix("LOGGED_IN:") {
            let text = String(rest)
            statusMessage = text
            phase = .authenticated(summary: text)
        } else if let rest = raw.stripPrefix("CANCELLED_7460:") {
            let text = String(rest)
            statusMessage = text
            phase = .loggedOut
        } else if let rest = raw.stripPrefix("ERR:") {
            statusMessage = String(rest)
        } else {
            statusMessage = raw
        }
    }
}

struct AppleIDLoginView: View {
    @StateObject private var vm = AppleAuthViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple ID 帳號") {
                    TextField("Apple ID（Email）", text: $vm.appleId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)

                    SecureField("密碼", text: $vm.password)

                    Button {
                        vm.login()
                    } label: {
                        HStack {
                            if vm.isBusy { ProgressView() }
                            Text("登入 Apple ID")
                        }
                    }
                    .disabled(vm.isBusy)
                }

                if case .awaiting2FA(let prompt) = vm.phase {
                    Section("雙重認證（2FA）") {
                        Text(prompt)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextField("6 位數驗證碼", text: $vm.twoFactorCode)
                            .keyboardType(.numberPad)

                        Button("送出驗證碼") {
                            vm.submit2FA()
                        }
                        .disabled(vm.isBusy)
                    }
                }

                Section("目前狀態") {
                    Text(vm.statusMessage)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Apple ID 登入")
            .alert("憑證數量已達上限（7460）", isPresented: $vm.show7460Alert) {
                Button("清理舊憑證並繼續", role: .destructive) {
                    vm.confirm7460(allowCleanup: true)
                }
                Button("取消", role: .cancel) {
                    vm.confirm7460(allowCleanup: false)
                }
            } message: {
                Text(vm.certLimitMessage)
            }
            .onAppear {
                vm.refreshStatus()
            }
        }
    }
}
