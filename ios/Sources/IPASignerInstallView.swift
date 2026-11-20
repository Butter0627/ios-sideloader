import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class IPASignerInstallViewModel: ObservableObject {
    @Published var selectedFileName: String = "尚未選取 .ipa 檔案"
    @Published var appGroupId: String = ""
    @Published var customBundleId: String = ""
    @Published var statusMessage: String = "尚未選取 IPA 檔案"
    @Published var showFilePicker: Bool = false
    @Published var isBusy: Bool = false

    func refreshStatus() {
        statusMessage = CoreBridge.ipaStatus()
    }

    func handlePickedFile(url: URL) {
        isBusy = true
        defer { isBusy = false }

        let gainedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if gainedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            statusMessage = "無法取得 Application Support 目錄"
            return
        }

        let inboxDir = base.appendingPathComponent("Sideloader/InboxIPA", isDirectory: true)
        try? fm.createDirectory(at: inboxDir, withIntermediateDirectories: true)

        let destURL = inboxDir.appendingPathComponent(url.lastPathComponent)
        do {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: url, to: destURL)
            selectedFileName = destURL.lastPathComponent
            statusMessage = CoreBridge.ipaSelect(path: destURL.path)
        } catch {
            statusMessage = "複製 IPA 失敗：\(error.localizedDescription)"
        }
    }

    func signAndInstall() {
        isBusy = true
        defer { isBusy = false }
        statusMessage = CoreBridge.ipaSignAndInstall(
            appGroup: appGroupId,
            customBundleId: customBundleId
        )
    }
}

struct IPASignerInstallView: View {
    @StateObject private var vm = IPASignerInstallViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("1. 選取 IPA 檔案") {
                    Text(vm.selectedFileName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("從「檔案」挑選 .ipa") {
                        vm.showFilePicker = true
                    }
                    .disabled(vm.isBusy)
                }

                Section("2. 重簽名設定（App Group / Bundle ID）") {
                    TextField("App Group（例如 group.com.example.app）", text: $vm.appGroupId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("自訂 Bundle ID（選填，留空維持原值）", text: $vm.customBundleId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        vm.signAndInstall()
                    } label: {
                        HStack {
                            if vm.isBusy { ProgressView() }
                            Text("重簽名（含 App Group）並安裝")
                        }
                    }
                    .disabled(vm.isBusy)
                }

                Section("執行狀態") {
                    Text(vm.statusMessage)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("IPA 重簽名與安裝")
            .fileImporter(
                isPresented: $vm.showFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let first = urls.first {
                    vm.handlePickedFile(url: first)
                } else if case .failure(let err) = result {
                    vm.statusMessage = "選取檔案取消或失敗：\(err.localizedDescription)"
                }
            }
            .onAppear {
                vm.refreshStatus()
            }
        }
    }
}
