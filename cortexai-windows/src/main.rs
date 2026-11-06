// Cortex AI for Windows — natív ablak a Cortex felülettel.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;

#[tauri::command]
fn open_url(u: String) -> bool {
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("rundll32")
            .args(["url.dll,FileProtocolHandler", &u])
            .spawn()
            .is_ok()
    }
    #[cfg(not(target_os = "windows"))]
    {
        std::process::Command::new("xdg-open")
            .arg(&u)
            .spawn()
            .is_ok()
    }
}

#[tauri::command]
fn win_minimize(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.minimize();
    }
}

#[tauri::command]
fn win_maximize(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.maximize();
    }
}

#[tauri::command]
fn win_close(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.close();
    }
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            open_url,
            win_minimize,
            win_maximize,
            win_close
        ])
        .run(tauri::generate_context!())
        .expect("error while running the Cortex AI app");
}
