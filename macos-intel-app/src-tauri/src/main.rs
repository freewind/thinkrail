//! Tauri shell that shows the ThinkRail web UI in a native window on Intel Macs.
//!
//! Electrobun publishes no macOS x64 core, so `apps/desktop` cannot be packaged for an
//! Intel Mac. This shell boots the ordinary `thinkrail` launcher shipped beside this
//! executable as a sidecar (with `--no-open`), waits for the loopback origin that
//! launcher prints, and navigates this window to it. The server, the wire, and the web
//! client are unchanged; Tauri only supplies the menu bar, the WKWebView, and the bundle.

use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, ChildStdout, Command, Stdio};
use std::sync::Mutex;

use tauri::{Manager, WebviewWindow};

/// The running engine, killed when the app exits so no orphan keeps serving its port.
struct Engine(Mutex<Option<Child>>);

fn main() {
	tauri::Builder::default()
		// The default macOS menu is what makes Cmd+C/V/X, Cmd+Q and Cmd+W work at all:
		// AppKit routes those key equivalents through the main menu, not the webview.
		.menu(|handle| tauri::menu::Menu::default(handle))
		.setup(|app| {
			let mut child = Command::new(engine_path())
				.arg("--no-open")
				.stdin(Stdio::null())
				.stdout(Stdio::piped())
				.stderr(Stdio::inherit())
				.spawn()?;
			let stdout = child.stdout.take().expect("engine stdout is piped");
			app.manage(Engine(Mutex::new(Some(child))));
			let window = app.get_webview_window("main").expect("main window exists");
			std::thread::spawn(move || follow_engine(stdout, window));
			Ok(())
		})
		.build(tauri::generate_context!())
		.expect("failed to build the ThinkRail shell")
		.run(|app, event| {
			if let tauri::RunEvent::Exit = event {
				if let Some(state) = app.try_state::<Engine>() {
					if let Some(mut child) = state.0.lock().expect("engine lock").take() {
						let _ = child.kill();
						let _ = child.wait();
					}
				}
			}
		});
}

/// `thinkrail` sits beside this executable inside the bundle, as `bundle.externalBin` places it.
fn engine_path() -> PathBuf {
	std::env::current_exe()
		.expect("current executable path")
		.parent()
		.expect("executable directory")
		.join("thinkrail")
}

/// What `apps/cli` prints once its host is listening, e.g. `thinkrail → http://localhost:24242`.
fn origin_from(line: &str) -> Option<String> {
	let (_, rest) = line.split_once('\u{2192}')?;
	let url = rest.trim();
	url.starts_with("http://").then(|| url.to_string())
}

fn follow_engine(stdout: ChildStdout, window: WebviewWindow) {
	// Reads to EOF rather than stopping at the origin: an undrained pipe would block the engine.
	for line in BufReader::new(stdout).lines().map_while(|line| line.ok()) {
		let Some(origin) = origin_from(&line) else {
			continue;
		};
		match origin.parse() {
			Ok(url) => {
				let _ = window.navigate(url);
				let _ = window.show();
			}
			Err(error) => eprintln!("unusable engine origin {origin:?}: {error}"),
		}
	}
}
