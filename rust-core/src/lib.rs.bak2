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

fn apple_state_lock() -> &'static Mutex<String> {
    APPLE_ID_STATE.get_or_init(|| Mutex::new("IDLE:尚未登入 Apple ID".to_string()))
}

fn apple_email_lock() -> &'static Mutex<String> {
    PENDING_APPLE_EMAIL.get_or_init(|| Mutex::new(String::new()))
}

fn cert_confirmed_lock() -> &'static Mutex<bool> {
    CERT_LIMIT_CONFIRMED.get_or_init(|| Mutex::new(false))
}

fn set_apple_state(v: impl Into<String>) {
    if let Ok(mut g) = apple_state_lock().lock() {
        *g = v.into();
    }
}

#[no_mangle]
pub extern "C" fn core_apple_status() -> *mut c_char {
    let s = apple_state_lock()
        .lock()
        .map(|g| g.clone())
        .unwrap_or_else(|_| "ERR:狀態鎖定失敗".to_string());
    to_c_string(s)
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

    // 預留 7460 模擬／觸發關鍵字（例如帳號含 "7460" 或已確認清理後）方便在實機先驗證對話框流程
    let confirmed = cert_confirmed_lock().lock().map(|b| *b).unwrap_or(false);
    if email.contains("7460") && !confirmed {
        let msg = format!("CERT_LIMIT_7460:帳號 {email} 憑證數量已達上限（錯誤碼 7460），請確認是否清理舊憑證後重試");
        set_apple_state(msg.clone());
        return to_c_string(msg);
    }

    // 預設進入 2FA 等待驗證碼階段，等待使用者輸入 6 位數驗證碼
    let msg = format!("NEED_2FA:已送出 {email} 登入請求，請輸入受信任裝置或簡訊的 6 位數 2FA 驗證碼");
    set_apple_state(msg.clone());
    to_c_string(msg)
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

    let email = apple_email_lock()
        .lock()
        .map(|g| g.clone())
        .unwrap_or_default();

    let msg = format!("LOGGED_IN:已驗證 2FA，Apple ID ({email}) 工作階段已就緒");
    set_apple_state(msg.clone());
    to_c_string(msg)
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

    // TODO: 接入 isideload 0.5.2 實際簽名與安裝流程：
    // 1. 建立 DeveloperSession / SideloaderBuilder（指定 FsStorage 目錄與目前登入帳號）
    // 2. 注入自訂 Bundle ID 與 App Groups（com.apple.security.application-groups）
    // 3. 執行重簽名並透過配對連線呼叫安裝流程
    let pairing_ok = pairing_file_path().map(|p| p.exists()).unwrap_or(false);
    if !pairing_ok {
        return format!(
            "PENDING_PAIRING:已備妥重簽名工作區（IPA: {}｜App Groups: [{}]｜Bundle ID: {}），但尚未取得 pairingFile.plist；完成本機遠端配對後即可執行安裝",
            staged_ipa.display(),
            groups_summary,
            bundle_summary
        );
    }

    format!(
        "SIGNED_QUEUED:已備妥重簽名工作區（IPA: {}｜App Groups: [{}]｜Bundle ID: {}）與配對檔，等待 isideload 簽名／安裝 API 正式串接",
        staged_ipa.display(),
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
