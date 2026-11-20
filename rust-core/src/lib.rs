use std::ffi::{CStr, CString};
use std::fs;
use std::future::Future;
use std::os::raw::c_char;
use std::path::PathBuf;
use std::pin::Pin;
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

#[derive(Debug)]
struct LocalSocketProvider;

impl idevice::remote_pairing::RpPairingSocketProvider for LocalSocketProvider {
    fn send_plain(
        &mut self,
        _value: impl serde::Serialize,
        _tag: usize,
    ) -> Pin<Box<dyn Future<Output = Result<(), idevice::IdeviceError>> + Send>> {
        Box::pin(async move {
            Err(idevice::IdeviceError::InternalError(
                "LocalSocketProvider 尚未接上本機 Socket 傳送".to_string(),
            ))
        })
    }

    fn send_encrypted(
        &mut self,
        _data: Vec<u8>,
        _tag: usize,
    ) -> Pin<Box<dyn Future<Output = Result<(), idevice::IdeviceError>> + Send>> {
        Box::pin(async move {
            Err(idevice::IdeviceError::InternalError(
                "LocalSocketProvider 尚未接上加密 Socket 傳送".to_string(),
            ))
        })
    }

    fn recv_plain<'a>(
        &'a mut self,
    ) -> Pin<Box<dyn Future<Output = Result<plist::Value, idevice::IdeviceError>> + Send + 'a>> {
        Box::pin(async move {
            Err(idevice::IdeviceError::InternalError(
                "LocalSocketProvider 尚未接上 Socket 接收".to_string(),
            ))
        })
    }

    fn serialize_bytes(bytes: &[u8]) -> plist::Value {
        plist::Value::Data(bytes.to_vec())
    }

    fn deserialize_bytes(value: plist::Value) -> Option<Vec<u8>> {
        match value {
            plist::Value::Data(d) => Some(d),
            _ => None,
        }
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

async fn run_remote_pairing(target_plist: PathBuf) -> Result<String, String> {
    let _ = rustls::crypto::ring::default_provider().install_default();

    let mut client = idevice::remote_pairing::RemotePairingClient::new(
        LocalSocketProvider,
        "MySideloader-iPhone",
    );

    let mut pairing_file = idevice::remote_pairing::RpPairingFile::default();

    client
        .pair(&mut pairing_file, || async {
            Ok::<String, idevice::IdeviceError>("000000".to_string())
        })
        .await
        .map_err(|e| format!("RemotePairingClient::pair 失敗: {e:?}"))?;

    save_pairing_debug_info(&target_plist, &pairing_file)?;

    Ok(format!(
        "本機遠端配對完成，已寫入配對檔: {}",
        target_plist.display()
    ))
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

    set_pairing_state("配對流程執行中...");

    let res = rt.block_on(run_remote_pairing(target_plist));
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
