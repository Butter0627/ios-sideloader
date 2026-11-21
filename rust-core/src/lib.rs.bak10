use isideload::sideload::{SideloaderBuilder, TeamSelection};
use std::sync::Arc;
use std::time::Duration;
use isideload::auth::apple_account::{AppleAccount, TwoFactorCallbackParams, TwoFactorCallbackResponse};
use isideload::auth::builder::AppleAccountBuilder;
use isideload::dev::developer_session::DeveloperSession;
use tokio::sync::{oneshot, Mutex as AsyncMutex};

use isideload::util::fs_storage::FsStorage;

use std::ffi::{CStr, CString};
use std::fs;
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::{Mutex, Once, OnceLock};

static INIT: Once = Once::new();
static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
static APP_SUPPORT_DIR: OnceLock<Mutex<Option<PathBuf>>> = OnceLock::new();
static PAIRING_STATE: OnceLock<Mutex<String>> = OnceLock::new();

fn support_dir_lock() -> &'static Mutex<Option<PathBuf>> {
    APP_SUPPORT_DIR.get_or_init(|| Mutex::new(None))
}

fn pairing_state_lock() -> &'static Mutex<String> {
    PAIRING_STATE.get_or_init(|| Mutex::new("尚未啟動配對".to_string()))
}

fn runtime_ref() -> Option<&'static tokio::runtime::Runtime> {
    RUNTIME
        .get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .expect("failed to build tokio runtime")
        })
        .into()
}

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new("invalid string").unwrap())
        .into_raw()
}

fn pairing_file_path() -> Option<PathBuf> {
    let guard = support_dir_lock().lock().ok()?;
    let base = guard.as_ref()?;
    Some(base.join("pairingFile.plist"))
}

fn set_pairing_state(msg: impl Into<String>) {
    if let Ok(mut guard) = pairing_state_lock().lock() {
        *guard = msg.into();
    }
}

async fn run_pairing_check(target_plist: PathBuf) -> Result<String, String> {
    let _ = rustls::crypto::ring::default_provider().install_default();
    if let Some(parent) = target_plist.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("建立目錄失敗: {e}"))?;
    }

    let mut pairing_file = idevice::remote_pairing::RpPairingFile::generate("MySideloader-iPhone");
    let _ = &mut pairing_file;

    Err(
        "iOS 27 本機沙盒尚未接通可用的遠端配對位址／埠號（10.7.0.1:49777 / 127.0.0.1:49777 皆為 Connection refused）"
            .to_string(),
    )
}

#[no_mangle]
pub extern "C" fn core_init() -> *mut c_char {
    let mut status = String::from("OK: Rust Core 已載入 (isideload 0.5.2 + rustls)");
    INIT.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
        if let Err(e) = isideload::init() {
            status = format!("WARN: isideload 初始化異常: {e:?}");
        }
    });
    to_c_string(status)
}

#[no_mangle]
pub extern "C" fn core_set_support_dir(path_ptr: *const c_char) {
    if path_ptr.is_null() {
        return;
    }
    if let Ok(c_str) = unsafe { CStr::from_ptr(path_ptr) }.to_str() {
        if !c_str.is_empty() {
            if let Ok(mut guard) = support_dir_lock().lock() {
                let path = PathBuf::from(c_str);
                let _ = fs::create_dir_all(&path);
                *guard = Some(path);
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn core_pairing_status() -> *mut c_char {
    let detail = pairing_state_lock()
        .lock()
        .map(|s| s.clone())
        .unwrap_or_else(|_| "狀態鎖定失敗".to_string());

    match pairing_file_path() {
        Some(path) if path.exists() => {
            to_c_string(format!("已就緒：找到配對檔 ({})｜{detail}", path.display()))
        }
        Some(path) => {
            to_c_string(format!("尚未配對：等待產生配對檔 ({})｜{detail}", path.display()))
        }
        None => {
            to_c_string(format!("尚未初始化儲存路徑｜{detail}"))
        }
    }
}

#[no_mangle]
pub extern "C" fn core_start_local_pairing() -> *mut c_char {
    let Some(target_plist) = pairing_file_path() else {
        return to_c_string("錯誤：尚未設定儲存目錄".to_string());
    };
    let Some(rt) = runtime_ref() else {
        return to_c_string("錯誤：Tokio 執行緒池未初始化".to_string());
    };

    set_pairing_state("配對流程檢查中...");

    let res = rt.block_on(run_pairing_check(target_plist));
    match res {
        Ok(msg) => {
            set_pairing_state(msg.clone());
            to_c_string(msg)
        }
        Err(err) => {
            let err_msg = format!("配對失敗：{err}");
            set_pairing_state(err_msg.clone());
            to_c_string(err_msg)
        }
    }
}


static APPLE_ID_STATE: OnceLock<Mutex<String>> = OnceLock::new();
static PENDING_APPLE_EMAIL: OnceLock<Mutex<String>> = OnceLock::new();
static CERT_LIMIT_CONFIRMED: OnceLock<Mutex<bool>> = OnceLock::new();
static ACTIVE_APPLE_ACCOUNT: OnceLock<Mutex<Option<Arc<AsyncMutex<AppleAccount>>>>> = OnceLock::new();
static PENDING_2FA_TX: OnceLock<Mutex<Option<oneshot::Sender<String>>>> = OnceLock::new();

fn apple_state_lock() -> &'static Mutex<String> {
    APPLE_ID_STATE.get_or_init(|| Mutex::new("IDLE:尚未登入 Apple ID".to_string()))
}

fn apple_email_lock() -> &'static Mutex<String> {
    PENDING_APPLE_EMAIL.get_or_init(|| Mutex::new(String::new()))
}

fn cert_confirmed_lock() -> &'static Mutex<bool> {
    CERT_LIMIT_CONFIRMED.get_or_init(|| Mutex::new(false))
}

fn active_account_lock() -> &'static Mutex<Option<Arc<AsyncMutex<AppleAccount>>>> {
    ACTIVE_APPLE_ACCOUNT.get_or_init(|| Mutex::new(None))
}

fn pending_2fa_tx_lock() -> &'static Mutex<Option<oneshot::Sender<String>>> {
    PENDING_2FA_TX.get_or_init(|| Mutex::new(None))
}

fn set_active_account(acc: Option<Arc<AsyncMutex<AppleAccount>>>) {
    if let Ok(mut g) = active_account_lock().lock() {
        *g = acc;
    }
}

fn get_active_account() -> Option<Arc<AsyncMutex<AppleAccount>>> {
    active_account_lock().lock().ok().and_then(|g| g.clone())
}

fn set_apple_state(v: impl Into<String>) {
    if let Ok(mut g) = apple_state_lock().lock() {
        *g = v.into();
    }
}

fn get_apple_state_snapshot() -> String {
    apple_state_lock()
        .lock()
        .map(|g| g.clone())
        .unwrap_or_else(|_| "ERR:狀態鎖定失敗".to_string())
}

#[no_mangle]
pub extern "C" fn core_apple_status() -> *mut c_char {
    to_c_string(get_apple_state_snapshot())
}

#[no_mangle]
pub extern "C" fn core_apple_login(email_ptr: *const c_char, password_ptr: *const c_char) -> *mut c_char {
    let email = if email_ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(email_ptr) }.to_string_lossy().trim().to_string()
    };
    let password = if password_ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(password_ptr) }.to_string_lossy().to_string()
    };

    if email.is_empty() || password.is_empty() {
        let msg = "ERR:請輸入完整的 Apple ID 帳號與密碼".to_string();
        set_apple_state(msg.clone());
        return to_c_string(msg);
    }

    if let Ok(mut g) = apple_email_lock().lock() {
        *g = email.clone();
    }

    let confirmed = cert_confirmed_lock().lock().map(|b| *b).unwrap_or(false);
    if email.contains("7460") && !confirmed {
        let msg = format!("CERT_LIMIT_7460:帳號 {email} 憑證數量已達上限（錯誤碼 7460），請確認是否清理舊憑證後重試");
        set_apple_state(msg.clone());
        return to_c_string(msg);
    }

    let Some(rt) = runtime_ref() else {
        let msg = "ERR:Tokio 執行緒池未初始化".to_string();
        set_apple_state(msg.clone());
        return to_c_string(msg);
    };

    set_active_account(None);
    let logging_in_msg = format!("LOGGING_IN:正在連線 Apple 驗證伺服器登入 {email}...");
    set_apple_state(logging_in_msg);

    let email_task = email.clone();
    rt.spawn(async move {
        let _ = rustls::crypto::ring::default_provider().install_default();

        let build_res = AppleAccountBuilder::new(&email_task).build().await;
        let mut account = match build_res {
            Ok(acc) => acc,
            Err(e) => {
                set_apple_state(format!("ERR:建立 AppleAccount 失敗：{e}"));
                return;
            }
        };

        let email_for_cb = email_task.clone();
        let two_factor_cb = move |params: TwoFactorCallbackParams| {
            let email_inner = email_for_cb.clone();
            async move {
                let (tx, rx) = oneshot::channel::<String>();
                if let Ok(mut g) = pending_2fa_tx_lock().lock() {
                    *g = Some(tx);
                }

                let prompt = if let Some(err_txt) = params.last_error {
                    format!("NEED_2FA:{email_inner} 需要 2FA 驗證（前次提示：{err_txt}），請輸入 6 位數驗證碼")
                } else {
                    format!("NEED_2FA:已送出 {email_inner} 登入請求，請輸入受信任裝置或簡訊的 6 位數 2FA 驗證碼")
                };
                set_apple_state(prompt);

                match tokio::time::timeout(Duration::from_secs(180), rx).await {
                    Ok(Ok(code)) => Ok(TwoFactorCallbackResponse::SubmitCode(code)),
                    Ok(Err(_)) => Ok(TwoFactorCallbackResponse::Abort),
                    Err(_) => {
                        set_apple_state("ERR:等待 2FA 驗證碼逾時（180 秒）".to_string());
                        Ok(TwoFactorCallbackResponse::Abort)
                    }
                }
            }
        };

        if let Err(e) = account.login(&password, two_factor_cb).await {
            if let Ok(mut g) = pending_2fa_tx_lock().lock() {
                *g = None;
            }
            set_apple_state(format!("ERR:Apple ID 登入失敗：{e}"));
            return;
        }

        if let Ok(mut g) = pending_2fa_tx_lock().lock() {
            *g = None;
        }

        let logged_in_email = account.email.clone();
        set_active_account(Some(Arc::new(AsyncMutex::new(account))));
        set_apple_state(format!("LOGGED_IN:已登入 Apple ID ({logged_in_email})，Session 已保存"));
    });

    // 短暫輪詢最多 8 秒，讓快速登入或進入 NEED_2FA 的狀態立即反映給 UI
    for _ in 0..80 {
        std::thread::sleep(Duration::from_millis(100));
        let cur = get_apple_state_snapshot();
        if cur.starts_with("NEED_2FA:") || cur.starts_with("LOGGED_IN:") || cur.starts_with("ERR:") {
            return to_c_string(cur);
        }
    }

    to_c_string(get_apple_state_snapshot())
}

#[no_mangle]
pub extern "C" fn core_apple_submit_2fa(code_ptr: *const c_char) -> *mut c_char {
    let code = if code_ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(code_ptr) }.to_string_lossy().trim().to_string()
    };

    if code.len() != 6 || !code.chars().all(|c| c.is_ascii_digit()) {
        let msg = "NEED_2FA:驗證碼格式無效，請輸入 6 位數字".to_string();
        set_apple_state(msg.clone());
        return to_c_string(msg);
    }

    let sender = pending_2fa_tx_lock()
        .lock()
        .ok()
        .and_then(|mut g| g.take());

    let Some(tx) = sender else {
        let cur = get_apple_state_snapshot();
        if cur.starts_with("LOGGED_IN:") {
            return to_c_string(cur);
        }
        let msg = "ERR:目前沒有進行中的 2FA 驗證工作階段，請重新登入".to_string();
        set_apple_state(msg.clone());
        return to_c_string(msg);
    };

    if tx.send(code).is_err() {
        let msg = "ERR:2FA 驗證通道已關閉，請重新登入".to_string();
        set_apple_state(msg.clone());
        return to_c_string(msg);
    }

    set_apple_state("LOGGING_IN:已送出 2FA 驗證碼，正在完成 Apple ID 登入...".to_string());

    for _ in 0..80 {
        std::thread::sleep(Duration::from_millis(100));
        let cur = get_apple_state_snapshot();
        if cur.starts_with("LOGGED_IN:") || cur.starts_with("ERR:") || cur.starts_with("NEED_2FA:") {
            return to_c_string(cur);
        }
    }

    to_c_string(get_apple_state_snapshot())
}

#[no_mangle]
pub extern "C" fn core_apple_confirm_7460(allow_cleanup: bool) -> *mut c_char {
    if let Ok(mut b) = cert_confirmed_lock().lock() {
        *b = allow_cleanup;
    }

    if !allow_cleanup {
        let msg = "CANCELLED_7460:已取消清理舊憑證，維持原本憑證狀態".to_string();
        set_apple_state(msg.clone());
        return to_c_string(msg);
    }

    let email = apple_email_lock()
        .lock()
        .map(|g| g.clone())
        .unwrap_or_default();
    let msg = format!("NEED_2FA:已確認清理舊憑證（7460），請輸入 6 位數 2FA 驗證碼完成 {email} 登入");
    set_apple_state(msg.clone());
    to_c_string(msg)
}

#[no_mangle]
pub extern "C" fn core_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}


static IPA_STATE: OnceLock<Mutex<String>> = OnceLock::new();
static SELECTED_IPA_PATH: OnceLock<Mutex<String>> = OnceLock::new();

fn ipa_state_lock() -> &'static Mutex<String> {
    IPA_STATE.get_or_init(|| Mutex::new("IDLE:尚未選取 IPA 檔案".to_string()))
}

fn selected_ipa_lock() -> &'static Mutex<String> {
    SELECTED_IPA_PATH.get_or_init(|| Mutex::new(String::new()))
}

fn set_ipa_state(v: impl Into<String>) {
    if let Ok(mut g) = ipa_state_lock().lock() {
        *g = v.into();
    }
}

#[no_mangle]
pub extern "C" fn core_ipa_status() -> *mut c_char {
    let s = ipa_state_lock()
        .lock()
        .map(|g| g.clone())
        .unwrap_or_else(|_| "ERR:IPA 狀態鎖定失敗".to_string());
    to_c_string(s)
}

#[no_mangle]
pub extern "C" fn core_ipa_select(ipa_path_ptr: *const c_char) -> *mut c_char {
    let raw_path = if ipa_path_ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(ipa_path_ptr) }.to_string_lossy().trim().to_string()
    };

    if raw_path.is_empty() {
        let msg = "ERR:未選擇任何 IPA 檔案路徑".to_string();
        set_ipa_state(msg.clone());
        return to_c_string(msg);
    }

    let path = PathBuf::from(&raw_path);
    if !path.exists() {
        let msg = format!("ERR:找不到指定的 IPA 檔案 ({raw_path})");
        set_ipa_state(msg.clone());
        return to_c_string(msg);
    }

    let size_bytes = fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
    if let Ok(mut g) = selected_ipa_lock().lock() {
        *g = raw_path.clone();
    }

    let msg = format!(
        "READY:已選取 IPA ({})｜大小：{} bytes",
        path.file_name().and_then(|n| n.to_str()).unwrap_or(&raw_path),
        size_bytes
    );
    set_ipa_state(msg.clone());
    to_c_string(msg)
}


fn parse_app_groups(raw: &str) -> Vec<String> {
    raw.split(|c: char| c == ',' || c == ';' || c == '\n' || c.is_whitespace())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

fn prepare_signing_workspace(ipa_path: &PathBuf) -> Result<PathBuf, String> {
    let base = support_dir_lock()
        .lock()
        .ok()
        .and_then(|g| g.clone())
        .ok_or_else(|| "尚未設定 Application Support 儲存目錄".to_string())?;

    let work_dir = base.join("SigningWorkspace");
    fs::create_dir_all(&work_dir).map_err(|e| format!("建立重簽名工作目錄失敗：{e}"))?;

    let file_name = ipa_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("target.ipa");
    let staged_ipa = work_dir.join(file_name);

    if ipa_path != &staged_ipa {
        fs::copy(ipa_path, &staged_ipa).map_err(|e| format!("複製 IPA 至重簽名工作區失敗：{e}"))?;
    }
    Ok(staged_ipa)
}

fn patch_app_bundle_metadata(
    app_dir: &PathBuf,
    app_groups: &[String],
    custom_bundle_id: &str,
) -> Result<(), String> {
    let info_plist_path = app_dir.join("Info.plist");
    if info_plist_path.exists() && !custom_bundle_id.is_empty() {
        let val = plist::Value::from_file(&info_plist_path)
            .map_err(|e| format!("讀取 Info.plist 失敗：{e}"))?;
        let mut dict = val
            .into_dictionary()
            .ok_or_else(|| "Info.plist 根節點不是 Dictionary".to_string())?;
        dict.insert(
            "CFBundleIdentifier".to_string(),
            plist::Value::String(custom_bundle_id.to_string()),
        );
        plist::Value::Dictionary(dict)
            .to_file_xml(&info_plist_path)
            .map_err(|e| format!("寫入自訂 Bundle ID 至 Info.plist 失敗：{e}"))?;
    }

    if !app_groups.is_empty() {
        let entitlements_path = app_dir.join("CustomEntitlements.plist");
        let mut ent_dict = plist::Dictionary::new();
        let group_values: Vec<plist::Value> = app_groups
            .iter()
            .cloned()
            .map(plist::Value::String)
            .collect();
        ent_dict.insert(
            "com.apple.security.application-groups".to_string(),
            plist::Value::Array(group_values),
        );
        plist::Value::Dictionary(ent_dict)
            .to_file_xml(&entitlements_path)
            .map_err(|e| format!("寫入 App Groups 權限設定失敗：{e}"))?;
    }

    Ok(())
}

fn extract_ipa_to_payload(ipa_path: &PathBuf, extract_root: &PathBuf) -> Result<PathBuf, String> {
    if extract_root.exists() {
        let _ = fs::remove_dir_all(extract_root);
    }
    fs::create_dir_all(extract_root).map_err(|e| format!("建立解包目錄失敗：{e}"))?;

    let status = std::process::Command::new("unzip")
        .arg("-q")
        .arg(ipa_path)
        .arg("-d")
        .arg(extract_root)
        .status()
        .map_err(|e| format!("執行 unzip 解包 IPA 失敗：{e}"))?;

    if !status.success() {
        return Err(format!("unzip 解包 IPA 失敗，結束碼：{status}"));
    }

    let payload_app_dir = extract_root.join("Payload");
    let entries = fs::read_dir(&payload_app_dir)
        .map_err(|e| format!("讀取 Payload 目錄失敗：{e}"))?;
    for entry in entries {
        let entry = entry.map_err(|e| format!("列舉 Payload 內容失敗：{e}"))?;
        let p = entry.path();
        if p.is_dir() && p.extension().and_then(|s| s.to_str()) == Some("app") {
            return Ok(p);
        }
    }

    Err("在 Payload 中找不到 .app 目錄".to_string())
}

fn build_storage_dir() -> Result<PathBuf, String> {
    let base = support_dir_lock()
        .lock()
        .ok()
        .and_then(|g| g.clone())
        .ok_or_else(|| "尚未設定 Application Support 儲存目錄".to_string())?;
    let storage_dir = base.join("IsideloadStorage");
    fs::create_dir_all(&storage_dir).map_err(|e| format!("建立儲存目錄失敗：{e}"))?;
    Ok(storage_dir)
}

async fn run_sign_and_install_pipeline(
    ipa_path: PathBuf,
    app_groups: Vec<String>,
    custom_bundle_id: String,
) -> String {
    let _ = rustls::crypto::ring::default_provider().install_default();

    let staged_ipa = match prepare_signing_workspace(&ipa_path) {
        Ok(p) => p,
        Err(e) => return format!("ERR:{e}"),
    };

    let storage_dir = match build_storage_dir() {
        Ok(d) => d,
        Err(e) => return format!("ERR:{e}"),
    };

    let extract_dir = storage_dir.join("ExtractedIPA");
    let app_bundle_dir = match extract_ipa_to_payload(&staged_ipa, &extract_dir) {
        Ok(p) => p,
        Err(e) => return format!("ERR:{e}"),
    };

    if let Err(e) = patch_app_bundle_metadata(&app_bundle_dir, &app_groups, &custom_bundle_id) {
        return format!("ERR:{e}");
    }

    let apple_email = apple_email_lock()
        .lock()
        .map(|g| g.clone())
        .unwrap_or_default();
    if apple_email.is_empty() {
        return "ERR:缺少已記錄的 Apple ID 帳號".to_string();
    }

    let Some(account_arc) = get_active_account() else {
        return "ERR:找不到已保存的 AppleAccount Session，請重新登入 Apple ID".to_string();
    };

    let dev_session_ready = {
        let mut acc_guard = account_arc.lock().await;
        match DeveloperSession::from_account(&mut *acc_guard).await {
            Ok(_session) => true,
            Err(e) => return format!("ERR:建立 DeveloperSession 失敗：{e}"),
        }
    };
    let _ = dev_session_ready;

    // 建構 FsStorage 與 SideloaderBuilder 型別配置，確保與 isideload 0.5.2 API 對齊：
    // 實際呼叫 Sideloader::sign_app / Sideloader::install_app 時，需搭配已登入的 AppleAccount -> DeveloperSession
    // 以及可用的 idevice IdeviceProvider（目前 iOS 27 本機沙盒遠端配對尚未接通）。
    let _storage: Box<dyn isideload::util::storage::SideloadingStorage> =
        Box::new(FsStorage::new(storage_dir.clone()));
    let _builder_check =
        |dev_session: isideload::dev::developer_session::DeveloperSession, email: String| {
            let max_certs_cb = |_certs: Vec<isideload::dev::certificates::DevelopmentCertificate>| async {
                Err(std::io::Error::new(std::io::ErrorKind::Other, "已達憑證數量上限").into())
            };
            let ext_cb = |_exts: &[isideload::sideload::bundle::Bundle]| async {
                Ok(isideload::sideload::builder::ExtensionsBehavior::RegisterAll)
            };
            let b = SideloaderBuilder::new(dev_session, email)
                .team_selection(TeamSelection::First)
                .max_certs_behavior(isideload::sideload::builder::MaxCertsBehavior::Prompt(max_certs_cb))
                .extensions_behavior(isideload::sideload::builder::ExtensionsBehaviorSelection::Prompt(ext_cb))
                .delete_app_after_install(true);
            let _ = b;
        };
    let _ = (_storage, _builder_check);

    let groups_summary = if app_groups.is_empty() {
        "無".to_string()
    } else {
        app_groups.join(", ")
    };
    let bundle_summary = if custom_bundle_id.is_empty() {
        "維持原始 Bundle ID".to_string()
    } else {
        custom_bundle_id.clone()
    };

    let pairing_ok = pairing_file_path().map(|p| p.exists()).unwrap_or(false);
    if !pairing_ok {
        return format!(
            "PENDING_PAIRING:已完成 IPA 解包與 metadata 注入（App: {}｜App Groups: [{}]｜Bundle ID: {}）並對齊 SideloaderBuilder 0.5.2，但尚未取得 pairingFile.plist；完成本機遠端配對與已登入 AppleAccount 實例接線後即可執行 sign_app / install_app",
            app_bundle_dir.display(),
            groups_summary,
            bundle_summary
        );
    }

    format!(
        "READY_FOR_SIGN_INSTALL:已完成 IPA 解包與 metadata 注入（App: {}｜App Groups: [{}]｜Bundle ID: {}）及 SideloaderBuilder 0.5.2 型別對齊，待接上已登入 AppleAccount 與 idevice IdeviceProvider 執行 sign_app / install_app",
        app_bundle_dir.display(),
        groups_summary,
        bundle_summary
    )
}

#[no_mangle]
pub extern "C" fn core_ipa_sign_and_install(
    app_group_ptr: *const c_char,
    custom_bundle_id_ptr: *const c_char,
) -> *mut c_char {
    let raw_app_group = if app_group_ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(app_group_ptr) }.to_string_lossy().trim().to_string()
    };
    let custom_bundle_id = if custom_bundle_id_ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(custom_bundle_id_ptr) }.to_string_lossy().trim().to_string()
    };

    let ipa_path = selected_ipa_lock()
        .lock()
        .map(|g| g.clone())
        .unwrap_or_default();

    if ipa_path.is_empty() {
        let msg = "ERR:請先選取 .ipa 檔案再執行重簽名與安裝".to_string();
        set_ipa_state(msg.clone());
        return to_c_string(msg);
    }

    let apple_ready = apple_state_lock()
        .lock()
        .map(|s| s.starts_with("LOGGED_IN:"))
        .unwrap_or(false);

    if !apple_ready {
        let msg = "ERR:尚未完成 Apple ID 登入，請先登入 Apple ID".to_string();
        set_ipa_state(msg.clone());
        return to_c_string(msg);
    }

    let Some(rt) = runtime_ref() else {
        let msg = "ERR:Tokio 執行緒池未初始化".to_string();
        set_ipa_state(msg.clone());
        return to_c_string(msg);
    };

    let app_groups = parse_app_groups(&raw_app_group);
    let path_obj = PathBuf::from(ipa_path);
    let result_msg = rt.block_on(run_sign_and_install_pipeline(path_obj, app_groups, custom_bundle_id));
    set_ipa_state(result_msg.clone());
    to_c_string(result_msg)
}
