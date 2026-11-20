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

fn save_pairing_debug_info(
    target_plist: &PathBuf,
    pairing_file: &idevice::remote_pairing::RpPairingFile,
) -> Result<(), String> {
    if let Some(parent) = target_plist.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("建立目錄失敗: {e}"))?;
    }
    let debug_dump = format!("{pairing_file:#?}");
    fs::write(target_plist, debug_dump).map_err(|e| format!("寫入配對檔失敗: {e}"))?;
    Ok(())
}

async fn discover_and_pair(target_plist: PathBuf) -> Result<String, String> {
    let _ = rustls::crypto::ring::default_provider().install_default();

    let mdns_type = std::any::type_name::<idevice::mdns::MdnsService>();
    let _ = mdns_type;

    let discovered = idevice::mdns::discover_remote_pairing()
        .await
        .map_err(|e| format!("mDNS 探索失敗: {e:?}"))?;

    if discovered.is_empty() {
        return Err("mDNS 未找到任何 Remote Pairing 服務".to_string());
    }

    let mut attempt_errors = Vec::new();
    for target in discovered {
        let addr_str = target.to_string();
        match tokio::net::TcpStream::connect(&addr_str).await {
            Ok(stream) => {
                let mut client = idevice::remote_pairing::RemotePairingClient::new(
                    idevice::remote_pairing::RpPairingSocket::new(stream),
                    "MySideloader-iPhone",
                );
                let mut pairing_file =
                    idevice::remote_pairing::RpPairingFile::generate("MySideloader-iPhone");

                match client
                    .pair(&mut pairing_file, || async { "000000".to_string() })
                    .await
                {
                    Ok(()) => {
                        save_pairing_debug_info(&target_plist, &pairing_file)?;
                        return Ok(format!(
                            "透過 mDNS ({addr_str}) 配對完成，已寫入: {}",
                            target_plist.display()
                        ));
                    }
                    Err(e) => attempt_errors.push(format!("{addr_str} -> pair 失敗: {e:?}")),
                }
            }
            Err(e) => attempt_errors.push(format!("{addr_str} -> TCP 連線失敗: {e}")),
        }
    }

    Err(attempt_errors.join(" | "))
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

    set_pairing_state("正在透過 mDNS 尋找 Remote Pairing 服務...");

    let res = rt.block_on(discover_and_pair(target_plist));
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

#[no_mangle]
pub extern "C" fn core_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}
