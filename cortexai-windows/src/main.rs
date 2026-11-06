// Cortex AI for Windows — natív ablak a Cortex felülettel.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running the Cortex AI app");
}
