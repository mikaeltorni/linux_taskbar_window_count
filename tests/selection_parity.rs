//! Public regressions for remaining native selection parity gaps.
use std::fs;
use std::process::{Command, Output};

/// Invoke selection through the actual native public entrypoint.
/// Parameters: operation - selector; path - config path; defaults - manifest operands.
/// Returns: captured native status/output.
fn run(operation: &str, path: &str, defaults: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_wwc-tools"))
        .args(["--selection", operation, "fixture", path])
        .args(defaults)
        .output()
        .unwrap()
}

#[test]
/// Preserve Python's empty component object and numeric/string conversion rules.
/// Parameters: none.
/// Returns: None.
fn empty_config_and_nonstring_values_match_original() {
    let root = std::env::temp_dir().join(format!("wwc-parity-{}", std::process::id()));
    fs::create_dir_all(&root).unwrap();
    let path = root.join("config.json");
    for document in [
        "{}",
        r#"{"components":{"first":{"on":1.0,"config_value":42},"second":{"on":0.0,"config_value":true}}}"#,
    ] {
        fs::write(&path, document).unwrap();
        for _ in 0..2 {
            let result = run("export", path.to_str().unwrap(), &["first=1", "second=1"]);
            assert_eq!(
                result.status.code(),
                Some(0),
                "{}",
                String::from_utf8_lossy(&result.stderr)
            );
            let doc: serde_json::Value = serde_json::from_slice(&result.stdout).unwrap();
            if document == "{}" {
                assert_eq!(doc["components"]["first"]["on"], 0);
                assert_eq!(doc["components"]["second"]["on"], 0);
            } else {
                assert_eq!(doc["components"]["first"]["on"], 1);
                assert_eq!(doc["components"]["first"]["config_value"], "42");
                assert_eq!(doc["components"]["second"]["config_value"], "True");
                assert_eq!(
                    run("selected", path.to_str().unwrap(), &["first=1", "second=1"]).stdout,
                    b"first\n"
                );
            }
            assert_eq!(fs::read_to_string(&path).unwrap(), document);
        }
    }
    fs::remove_dir_all(root).unwrap();
}

#[test]
/// Reject malformed token/config rules and immediately reread populated flags/values.
/// Parameters: none.
/// Returns: None.
fn rejection_statuses_and_state_match_original_contract() {
    let root = std::env::temp_dir().join(format!("wwc-reject-{}", std::process::id()));
    fs::create_dir_all(&root).unwrap();
    let path = root.join("config.json");
    let original = r#"{"components":{"first":{"on":1,"config_value":"preserve"}}}"#;
    fs::write(&path, original).unwrap();
    for (operation, defaults, status) in [
        ("unknown", vec!["first=1"], 2),
        ("export", vec![], 2),
        ("export", vec!["first=maybe"], 1),
        ("selected", vec!["broken"], 1),
    ] {
        assert_eq!(
            run(operation, path.to_str().unwrap(), &defaults)
                .status
                .code(),
            Some(status)
        );
        let observation = run("export", path.to_str().unwrap(), &["first=1"]);
        assert_eq!(observation.status.code(), Some(0));
        let doc: serde_json::Value = serde_json::from_slice(&observation.stdout).unwrap();
        assert_eq!(doc["components"]["first"]["on"], 1);
        assert_eq!(doc["components"]["first"]["config_value"], "preserve");
        assert_eq!(fs::read_to_string(&path).unwrap(), original);
    }
    fs::remove_dir_all(root).unwrap();
}

#[test]
/// Preserve nontext configuration representations and ASCII JSON escaping.
/// Parameters: none.
/// Returns: None.
fn structured_values_and_unicode_match_original() {
    let root = std::env::temp_dir().join(format!("wwc-structured-{}", std::process::id()));
    fs::create_dir_all(&root).unwrap();
    let path = root.join("config.json");
    for (value, expected) in [
        ("null", "None"),
        ("12345678901234567890123", "12345678901234567890123"),
        (r#""\u007f""#, "\u{7f}"),
        ("false", "False"),
        (
            r#"[null, true, "ä", "it's", "a\nb"]"#,
            "[None, True, 'ä', \"it's\", 'a\\nb']",
        ),
        (r#"{"name":"ä", "count":2}"#, "{'name': 'ä', 'count': 2}"),
        ("1e20", "1e+20"),
        ("0.000001", "1e-06"),
    ] {
        let document = format!(r#"{{"components":{{"first":{{"config_value":{value}}}}}}}"#);
        fs::write(&path, &document).unwrap();
        let output = run("export", path.to_str().unwrap(), &["first=1"]);
        assert_eq!(output.status.code(), Some(0));
        assert!(output.stdout.is_ascii());
        assert!(!output.stdout.contains(&0x7f));
        let decoded: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(decoded["components"]["first"]["config_value"], expected);
        assert_eq!(fs::read_to_string(&path).unwrap(), document);
    }
    fs::remove_dir_all(root).unwrap();
}

#[test]
/// Reject incomplete command shapes before inspecting or modifying populated files.
/// Parameters: none.
/// Returns: None.
fn missing_selection_operands_preserve_state() {
    let root = std::env::temp_dir().join(format!("wwc-shape-{}", std::process::id()));
    fs::create_dir_all(&root).unwrap();
    let path = root.join("config.json");
    let original = r#"{"components":{"first":{"on":1,"config_value":"preserve"}}}"#;
    fs::write(&path, original).unwrap();
    for operands in [
        vec![],
        vec!["export"],
        vec!["export", "fixture"],
        vec!["export", "fixture", path.to_str().unwrap()],
    ] {
        let rejected = Command::new(env!("CARGO_BIN_EXE_wwc-tools"))
            .arg("--selection")
            .args(operands)
            .output()
            .unwrap();
        assert_eq!(rejected.status.code(), Some(2));
        let observed = run("export", path.to_str().unwrap(), &["first=1"]);
        assert_eq!(observed.status.code(), Some(0));
        let doc: serde_json::Value = serde_json::from_slice(&observed.stdout).unwrap();
        assert_eq!(doc["components"]["first"]["on"], 1);
        assert_eq!(doc["components"]["first"]["config_value"], "preserve");
        assert_eq!(fs::read_to_string(&path).unwrap(), original);
    }
    fs::remove_dir_all(root).unwrap();
}
