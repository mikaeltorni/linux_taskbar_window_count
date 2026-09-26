//! CLI contract formerly covered by tests/test_gsettings_strv.py.

use std::env;
use std::path::PathBuf;
use std::process::Command;

fn bin() -> Command {
    Command::new(env!("CARGO_BIN_EXE_wwc-tools"))
}

#[test]
fn cli_formats_updated_array_from_current_environment() {
    let output = bin()
        .arg("two")
        .env("CURRENT", "@as ['one']")
        .output()
        .expect("run wwc-tools");
    assert!(
        output.status.success(),
        "stderr={}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        "['one', 'two']"
    );
}

#[test]
fn cli_rejects_wrong_argument_count() {
    let none = bin().output().expect("run wwc-tools");
    assert_eq!(none.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&none.stderr).contains("Usage: wwc-tools <value>"));

    let extra = bin().args(["one", "two"]).output().expect("run wwc-tools");
    assert_eq!(extra.status.code(), Some(2));
}

#[test]
fn cli_writes_log_under_configured_dir() {
    let dir = TemporaryLogDir::new();
    let output = bin()
        .arg("workspace-window-count@local")
        .env("CURRENT", "[]")
        .env("TASKBAR_WINDOW_COUNT_LOG_DIR", &dir.0)
        .output()
        .expect("run wwc-tools");
    assert!(output.status.success());
    let log = std::fs::read_to_string(dir.0.join("gsettings_strv.log")).expect("log file");
    assert!(log.contains("Ensuring extension UUID is present in enabled-extensions"));
}

struct TemporaryLogDir(PathBuf);

impl TemporaryLogDir {
    fn new() -> Self {
        let path = env::temp_dir().join(format!("wwc-tools-cli-{}", std::process::id()));
        std::fs::create_dir_all(&path).expect("temp log dir");
        Self(path)
    }
}

impl Drop for TemporaryLogDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
