//! C ABI for Swift/Objective-C. All returned strings are JSON (or an
//! `{"error": ...}` object) and must be released with `rustcord_free_string`.

use crate::{gateway, HttpClient};
use std::ffi::{c_char, CStr, CString};
use std::sync::OnceLock;
use tokio::runtime::Runtime;

fn rt() -> &'static Runtime {
    static RT: OnceLock<Runtime> = OnceLock::new();
    RT.get_or_init(|| Runtime::new().expect("tokio runtime"))
}

fn out(s: String) -> *mut c_char {
    CString::new(s.replace('\0', "")).unwrap().into_raw()
}

fn arg(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
}

fn json_result<T: serde::Serialize>(r: Result<T, crate::Error>) -> *mut c_char {
    out(match r {
        Ok(v) => serde_json::to_string(&v).unwrap_or_else(|e| format!("{{\"error\":\"{e}\"}}")),
        Err(e) => serde_json::json!({ "error": e.to_string() }).to_string(),
    })
}

/// Opaque client handle.
pub struct RustcordClient(HttpClient);

#[no_mangle]
pub extern "C" fn rustcord_client_new(token: *const c_char) -> *mut RustcordClient {
    Box::into_raw(Box::new(RustcordClient(HttpClient::new(arg(token)))))
}

#[no_mangle]
pub extern "C" fn rustcord_client_free(c: *mut RustcordClient) {
    if !c.is_null() {
        drop(unsafe { Box::from_raw(c) });
    }
}

#[no_mangle]
pub extern "C" fn rustcord_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(unsafe { CString::from_raw(s) });
    }
}

#[no_mangle]
pub extern "C" fn rustcord_current_user(c: *const RustcordClient) -> *mut c_char {
    let c = unsafe { &*c };
    json_result(rt().block_on(c.0.current_user()))
}

#[no_mangle]
pub extern "C" fn rustcord_guilds(c: *const RustcordClient) -> *mut c_char {
    let c = unsafe { &*c };
    json_result(rt().block_on(c.0.guilds()))
}

#[no_mangle]
pub extern "C" fn rustcord_guild_channels(
    c: *const RustcordClient,
    guild_id: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*c };
    json_result(rt().block_on(c.0.guild_channels(&arg(guild_id))))
}

#[no_mangle]
pub extern "C" fn rustcord_create_dm(
    c: *const RustcordClient,
    recipient_id: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*c };
    json_result(rt().block_on(c.0.create_dm(&arg(recipient_id))))
}

#[no_mangle]
pub extern "C" fn rustcord_messages(
    c: *const RustcordClient,
    channel_id: *const c_char,
    limit: u8,
) -> *mut c_char {
    let c = unsafe { &*c };
    json_result(rt().block_on(c.0.messages(&arg(channel_id), limit)))
}

#[no_mangle]
pub extern "C" fn rustcord_send_message(
    c: *const RustcordClient,
    channel_id: *const c_char,
    content: *const c_char,
) -> *mut c_char {
    let c = unsafe { &*c };
    json_result(rt().block_on(c.0.send_message(&arg(channel_id), &arg(content))))
}

pub type EventCallback =
    extern "C" fn(user_data: *mut std::ffi::c_void, name: *const c_char, json: *const c_char);

struct SendPtr(*mut std::ffi::c_void);
unsafe impl Send for SendPtr {}

/// Starts the gateway in the background; `cb` is invoked on a Rust thread for
/// every dispatch event. The name/json pointers are only valid during the call.
#[no_mangle]
pub extern "C" fn rustcord_gateway_start(
    token: *const c_char,
    cb: EventCallback,
    user_data: *mut std::ffi::c_void,
) {
    let token = arg(token);
    let ud = SendPtr(user_data);
    rt().spawn(async move {
        let ud = ud;
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let t = token.clone();
        tokio::spawn(async move {
            let _ = gateway::run(&t, gateway::DEFAULT_INTENTS, tx).await;
        });
        while let Some(ev) = rx.recv().await {
            if let (Ok(n), Ok(d)) = (CString::new(ev.name), CString::new(ev.data.to_string())) {
                cb(ud.0, n.as_ptr(), d.as_ptr());
            }
        }
    });
}
