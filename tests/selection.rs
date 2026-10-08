//! Public checks for wwc-tools selection export.

use std::process::Command;

fn bin() -> Command {
    Command::new(env!("CARGO_BIN_EXE_wwc-tools"))
}

#[test]
fn default_export_and_selected_match_the_python_contract() {
    let args = ["--selection", "export", "linux_taskbar_window_count", "", "badge_position=1", "count_threshold=1", "workspace_scope=1", "badge_appearance=1"];
    let mut runs = Vec::new();
    for _ in 0..2 {
        let output = bin().args(args).output().unwrap();
        assert_eq!(output.status.code(), Some(0), "{}", String::from_utf8_lossy(&output.stderr));
        runs.push(String::from_utf8_lossy(&output.stdout).to_string());
    }
    assert_eq!(runs[0], runs[1]);
    assert_eq!(runs[0], "{\n  \"components\": {\n    \"badge_position\": {\n      \"config_value\": \"\",\n      \"favorite\": 0,\n      \"on\": 1,\n      \"startup\": 0,\n      \"sticky\": 0,\n      \"uninstall\": 0,\n      \"workspace\": 0\n    },\n    \"count_threshold\": {\n      \"config_value\": \"\",\n      \"favorite\": 0,\n      \"on\": 1,\n      \"startup\": 0,\n      \"sticky\": 0,\n      \"uninstall\": 0,\n      \"workspace\": 0\n    },\n    \"workspace_scope\": {\n      \"config_value\": \"\",\n      \"favorite\": 0,\n      \"on\": 1,\n      \"startup\": 0,\n      \"sticky\": 0,\n      \"uninstall\": 0,\n      \"workspace\": 0\n    },\n    \"badge_appearance\": {\n      \"config_value\": \"\",\n      \"favorite\": 0,\n      \"on\": 1,\n      \"startup\": 0,\n      \"sticky\": 0,\n      \"uninstall\": 0,\n      \"workspace\": 0\n    }\n  },\n  \"repo\": \"linux_taskbar_window_count\",\n  \"schema_version\": 1,\n  \"scope\": \"standalone\"\n}\n");
    let selected = bin().args(["--selection", "selected", "linux_taskbar_window_count", "", "badge_position=1", "count_threshold=1", "workspace_scope=1", "badge_appearance=1"]).output().unwrap();
    assert_eq!(String::from_utf8_lossy(&selected.stdout), "badge_position\ncount_threshold\nworkspace_scope\nbadge_appearance\n");
}
