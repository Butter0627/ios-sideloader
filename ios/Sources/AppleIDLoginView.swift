import SwiftUI

@_silgen_name("core_apple_status")
private func core_apple_status() -> UnsafeMutablePointer<CChar>?

@_silgen_name("core_apple_login")
private func core_apple_login(
    _ emailPtr: UnsafePointer<CChar>?,
    _ passwordPtr: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("core_apple_submit_2fa")
private func core_apple_submit_2fa(
    _ codePtr: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("core_apple_confirm_7460")
private func core_apple_confirm_7460(
    _ allowCleanup: Bool
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("core_free_string")
private func core_free_string(_ ptr: UnsafeMutablePointer<CChar>?)

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

    private func consumeCString(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr else { return "ERR:空字串指標" }
        defer { core_free_string(ptr) }
        return String(cString: ptr)
    }

    func refreshStatus() {
        let raw = consumeCString(core_apple_status())
        applyRawState(raw)
    }

    func login() {
        isBusy = true
        defer { isBusy = false }

        let raw = appleId.withCString { idPtr in
            password.withCString { pwPtr in
                consumeCString(core_apple_login(idPtr, pwPtr))
            }
        }
        applyRawState(raw)
    }

    func submit2FA() {
        isBusy = true
        defer { isBusy = false }

        let raw = twoFactorCode.withCString { codePtr in
            consumeCString(core_apple_submit_2fa(codePtr))
        }
        applyRawState(raw)
    }

    func confirm7460(allowCleanup: Bool) {
        show7460Alert = false
        isBusy = true
        defer { isBusy = false }

        let raw = consumeCString(core_apple_confirm_7460(allowCleanup))
        applyRawState(raw)
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
