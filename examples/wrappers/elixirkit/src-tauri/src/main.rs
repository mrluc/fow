#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use tauri::Manager;
fn main() {
    let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("listen for ElixirKit");
    tauri::Builder::default().setup(move |app| {
        let handle = app.handle().clone();
        pubsub.subscribe("desktop", move |message| {
            let text = String::from_utf8_lossy(message);
            if let Some(url) = text.strip_prefix("ready:") {
                if handle.get_webview_window("main").is_some() { return; }
                let local: tauri::Url = url.parse().expect("public shell URL");
                assert_eq!(local.host_str(), Some("127.0.0.1"));
                let local_origin = local.origin().ascii_serialization();
                let live: tauri::Url = "http://127.0.0.1:47180/".parse().expect("configured live URL");
                let remote_origin = live.origin().ascii_serialization();
                tauri::WebviewWindowBuilder::new(&handle, "main", tauri::WebviewUrl::External(local))
                    .title("Counters").inner_size(1060.0, 760.0)
                    .initialization_script(include_str!("../../priv/fog_of_war_seed.js"))
                    .on_navigation(move |url| {
                        let origin = url.origin().ascii_serialization();
                        origin == local_origin || origin == remote_origin
                    })
                    .build().expect("create window");
            }
        });
        let handle = app.handle().clone();
        tauri::async_runtime::spawn_blocking(move || {
            let dir = handle.path().resource_dir().expect("resources").join("rel");
            let mut command = elixirkit::release(&dir, "counters_desktop");
            command.env("ELIXIRKIT_PUBSUB", pubsub.url());
            let status = command.status().expect("start bundled Elixir release");
            handle.exit(status.code().unwrap_or(1));
        });
        Ok(())
    }).run(tauri::generate_context!()).expect("run desktop wrapper");
}
