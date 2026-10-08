//! Resolve saved component flags for installation and JSON export.

use serde_json::{json, Map, Value};
use std::collections::BTreeSet;
use std::fs;

const FLAG_FIELDS: [&str; 6] = [
    "favorite",
    "on",
    "startup",
    "sticky",
    "uninstall",
    "workspace",
];

enum Operation {
    Selected,
    Export,
}

struct Selection<'a> {
    operation: Operation,
    repo: &'a str,
    config_path: &'a str,
    defaults: Map<String, Value>,
}

/// Parse operation and manifest operands before reading configuration state.
/// Parameters: args - raw selection CLI operands.
/// Returns: parsed selection or diagnostic and public exit status.
fn parse(args: &[String]) -> Result<Selection<'_>, (String, i32)> {
    if args.len() < 4 {
        return Err((
            "expected operation, repo, config path, and defaults".into(),
            2,
        ));
    }
    let operation = match args[0].as_str() {
        "selected" => Operation::Selected,
        "export" => Operation::Export,
        other => return Err((format!("unknown operation {other}"), 2)),
    };
    let mut defaults = Map::new();
    for entry in &args[3..] {
        let (name, value) = entry
            .rsplit_once('=')
            .ok_or_else(|| (format!("default {entry} must be name=value"), 1))?;
        let flag = flag_value(value).map_err(|error| (error, 1))?;
        defaults.insert(name.to_string(), Value::from(flag));
    }
    Ok(Selection {
        operation,
        repo: &args[1],
        config_path: &args[2],
        defaults,
    })
}

/// Read and normalize known component values without mutating any state.
/// Parameters: config_path - optional JSON file; defaults - ordered manifest flags.
/// Returns: normalized component fields or validation/read failure.
fn resolve(config_path: &str, defaults: &Map<String, Value>) -> Result<Map<String, Value>, String> {
    let mut config = Map::new();
    if !config_path.is_empty() {
        let text = fs::read_to_string(config_path).map_err(|error| error.to_string())?;
        let document: Value = serde_json::from_str(&text).map_err(|error| error.to_string())?;
        let document = document
            .as_object()
            .ok_or_else(|| "installation config must be an object".to_string())?;
        config = match document.get("components") {
            None => Map::new(),
            Some(Value::Object(map)) => map.clone(),
            Some(_) => return Err("installation config 'components' must be an object".into()),
        };
        let known: BTreeSet<&str> = defaults.keys().map(String::as_str).collect();
        let mut unknown: Vec<&str> = config
            .keys()
            .map(String::as_str)
            .filter(|id| !known.contains(id))
            .collect();
        if !unknown.is_empty() {
            unknown.sort_unstable();
            return Err(format!("unknown component id(s): {}", unknown.join(", ")));
        }
    }
    let mut components = Map::new();
    for (component_id, default_on) in defaults {
        let values = config
            .get(component_id)
            .cloned()
            .unwrap_or_else(|| json!({}));
        let values = values
            .as_object()
            .ok_or_else(|| format!("installation config for {component_id:?} must be an object"))?;
        let mut normalized = Map::new();
        let text = values
            .get("config_value")
            .map(|value| python_text(value, false))
            .unwrap_or_default();
        normalized.insert("config_value".into(), json!(text));
        for field in FLAG_FIELDS {
            let fallback = if field == "on" && config_path.is_empty() {
                default_on.as_i64().unwrap_or(0)
            } else {
                0
            };
            let raw = values.get(field).cloned().unwrap_or(Value::from(fallback));
            let flag =
                flag_json(&raw).map_err(|error| format!("{component_id}.{field}: {error}"))?;
            normalized.insert(field.to_string(), Value::from(flag));
        }
        components.insert(component_id.clone(), Value::Object(normalized));
    }
    Ok(components)
}

/// Convert the original accepted textual flag forms.
/// Parameters: value - manifest or JSON string flag.
/// Returns: zero/one or unsupported flag diagnostic.
fn flag_value(value: &str) -> Result<i64, String> {
    match value {
        "1" | "true" | "on" => Ok(1),
        "0" | "false" | "off" | "" => Ok(0),
        other => Err(format!("unsupported flag value {other:?}; use 0 or 1")),
    }
}

/// Convert JSON flags including Python's numeric equality with zero/one.
/// Parameters: value - JSON flag value.
/// Returns: zero/one or unsupported flag diagnostic.
fn flag_json(value: &Value) -> Result<i64, String> {
    match value {
        Value::Number(number) if number.as_f64() == Some(1.0) => Ok(1),
        Value::Number(number) if number.as_f64() == Some(0.0) => Ok(0),
        Value::Bool(true) => Ok(1),
        Value::Bool(false) | Value::Null => Ok(0),
        Value::String(text) => flag_value(text),
        other => Err(format!("unsupported flag value {other}; use 0 or 1")),
    }
}

/// Preserve Python's number stringification when normalizing configuration text.
/// Parameters: number - parsed JSON integer or float.
/// Returns: decimal or signed scientific representation.
fn number_text(number: &serde_json::Number) -> String {
    let raw = number.to_string();
    if !raw.contains(['.', 'e', 'E']) {
        return raw;
    }
    let value = number.as_f64().unwrap_or(0.0);
    if value != 0.0 && (value.abs() < 1e-4 || value.abs() >= 1e16) {
        let scientific = format!("{value:e}");
        let (mantissa, exponent) = scientific.split_once('e').unwrap();
        let exponent: i32 = exponent.parse().unwrap();
        format!("{mantissa}e{exponent:+03}")
    } else {
        let text = value.to_string();
        if text.contains('.') {
            text
        } else {
            format!("{text}.0")
        }
    }
}

/// Quote a nested string using the original Python container representation.
/// Parameters: text - nested string value.
/// Returns: quoted text with escaped whitespace, controls and quote characters.
fn quoted_text(text: &str) -> String {
    let quote = if text.contains('\'') && !text.contains('"') {
        '"'
    } else {
        '\''
    };
    let mut result = String::new();
    result.push(quote);
    for ch in text.chars() {
        match ch {
            '\\' => result.push_str("\\\\"),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            ch if ch == quote => {
                result.push('\\');
                result.push(ch);
            }
            ch if ch.is_control() || (ch != ' ' && ch.is_whitespace()) => {
                let code = ch as u32;
                if code <= 0xff {
                    result.push_str(&format!("\\x{code:02x}"));
                } else if code <= 0xffff {
                    result.push_str(&format!("\\u{code:04x}"));
                } else {
                    result.push_str(&format!("\\U{code:08x}"));
                }
            }
            ch => result.push(ch),
        }
    }
    result.push(quote);
    result
}

/// Normalize JSON configuration values using str at the root and repr in containers.
/// Parameters: value - JSON value; nested - whether strings require representation quotes.
/// Returns: original Python-compatible configuration text.
fn python_text(value: &Value, nested: bool) -> String {
    match value {
        Value::Null => "None".into(),
        Value::Bool(true) => "True".into(),
        Value::Bool(false) => "False".into(),
        Value::Number(number) => number_text(number),
        Value::String(text) => {
            if nested {
                quoted_text(text)
            } else {
                text.clone()
            }
        }
        Value::Array(values) => format!(
            "[{}]",
            values
                .iter()
                .map(|value| python_text(value, true))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        Value::Object(values) => format!(
            "{{{}}}",
            values
                .iter()
                .map(|(key, value)| format!("{}: {}", quoted_text(key), python_text(value, true)))
                .collect::<Vec<_>>()
                .join(", ")
        ),
    }
}

/// Print selected component IDs in manifest order.
/// Parameters: selection - parsed manifest and configuration path.
/// Returns: success or configuration validation/read failure.
fn selected(selection: &Selection<'_>) -> Result<(), String> {
    for (id, values) in resolve(selection.config_path, &selection.defaults)? {
        if values.get("on").and_then(Value::as_i64) == Some(1) {
            println!("{id}");
        }
    }
    Ok(())
}

/// Export normalized standalone JSON with the original ASCII escaping.
/// Parameters: selection - parsed repository, manifest and configuration path.
/// Returns: success or configuration validation/read/serialization failure.
fn export(selection: &Selection<'_>) -> Result<(), String> {
    let components = resolve(selection.config_path, &selection.defaults)?;
    let mut root = Map::new();
    root.insert("components".into(), Value::Object(components));
    root.insert("repo".into(), json!(selection.repo));
    root.insert("schema_version".into(), json!(1));
    root.insert("scope".into(), json!("standalone"));
    let text =
        serde_json::to_string_pretty(&Value::Object(root)).map_err(|error| error.to_string())?;
    let mut ascii = String::new();
    for ch in text.chars() {
        if ch <= '\u{7e}' {
            ascii.push(ch);
        } else {
            for code in ch.encode_utf16(&mut [0; 2]) {
                ascii.push_str(&format!("\\u{code:04x}"));
            }
        }
    }
    println!("{ascii}");
    Ok(())
}

/// Dispatch parsed selection operations while preserving public output and status.
/// Parameters: args - raw selection CLI operands.
/// Returns: zero on success, two for command shape, one for invalid configuration.
pub fn run(args: &[String]) -> i32 {
    let selection = match parse(args) {
        Ok(selection) => selection,
        Err((error, status)) => {
            eprintln!("ERROR: invalid installation config: {error}");
            return status;
        }
    };
    let result = match selection.operation {
        Operation::Selected => selected(&selection),
        Operation::Export => export(&selection),
    };
    match result {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("ERROR: invalid installation config: {error}");
            1
        }
    }
}
