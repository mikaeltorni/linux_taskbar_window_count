//! Resolve saved component flags for installation and JSON export.

use serde_json::{json, Map, Value};
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

const FLAG_FIELDS: [&str; 6] = ["favorite", "on", "startup", "sticky", "uninstall", "workspace"];

pub fn run(args: &[String]) -> i32 {
    if args.len() < 3 {
        eprintln!("ERROR: invalid installation config: expected operation, repo, and config path");
        return 1;
    }
    let operation = &args[0];
    let repo = &args[1];
    let config_path = &args[2];
    let mut defaults = Map::new();
    for entry in &args[3..] {
        let Some((name, value)) = entry.rsplit_once('=') else {
            eprintln!("ERROR: invalid installation config: default {entry} must be name=value");
            return 1;
        };
        match flag_value(value) {
            Ok(flag) => { defaults.insert(name.to_string(), Value::from(flag)); }
            Err(error) => {
                eprintln!("ERROR: invalid installation config: {error}");
                return 1;
            }
        }
    }
    match resolve(config_path, &defaults) {
        Ok(components) if operation == "selected" => {
            for (id, values) in &components {
                if values.get("on").and_then(Value::as_i64) == Some(1) {
                    println!("{id}");
                }
            }
            0
        }
        Ok(components) if operation == "export" => {
            let mut root = Map::new();
            root.insert("components".into(), Value::Object(components));
            root.insert("repo".into(), json!(repo));
            root.insert("schema_version".into(), json!(1));
            root.insert("scope".into(), json!("standalone"));
            println!("{}", serde_json::to_string_pretty(&Value::Object(root)).unwrap_or_else(|_| "{}".into()));
            0
        }
        Ok(_) => {
            eprintln!("ERROR: invalid installation config: unknown operation {operation}");
            1
        }
        Err(error) => {
            eprintln!("ERROR: invalid installation config: {error}");
            1
        }
    }
}

fn resolve(config_path: &str, defaults: &Map<String, Value>) -> Result<Map<String, Value>, String> {
    let mut config = Map::new();
    if !config_path.is_empty() {
        let text = fs::read_to_string(config_path).map_err(|error| error.to_string())?;
        let document: Value = serde_json::from_str(&text).map_err(|error| error.to_string())?;
        let document = document.as_object().ok_or_else(|| "installation config must be an object".to_string())?;
        config = document.get("components").cloned().and_then(|value| match value { Value::Object(map) => Some(map), _ => None }).ok_or_else(|| "installation config 'components' must be an object".to_string())?;
        let known: BTreeSet<&str> = defaults.keys().map(String::as_str).collect();
        let unknown: Vec<&str> = config.keys().map(String::as_str).filter(|id| !known.contains(id)).collect();
        if !unknown.is_empty() {
            let mut names = unknown;
            names.sort_unstable();
            return Err(format!("unknown component id(s): {}", names.join(", ")));
        }
    }
    let mut components = Map::new();
    for (component_id, default_on) in defaults {
        let values = config.get(component_id).cloned().unwrap_or_else(|| json!({}));
        let values = values.as_object().ok_or_else(|| format!("installation config for {component_id:?} must be an object"))?;
        let mut normalized = Map::new();
        normalized.insert("config_value".into(), json!(values.get("config_value").and_then(Value::as_str).unwrap_or("")));
        for field in FLAG_FIELDS {
            let fallback = if field == "on" && config_path.is_empty() { default_on.as_i64().unwrap_or(0) } else { 0 };
            let raw = values.get(field).cloned().unwrap_or(Value::from(fallback));
            let flag = flag_json(&raw).map_err(|error| format!("{component_id}.{field}: {error}"))?;
            normalized.insert((*field).to_string(), Value::from(flag));
        }
        components.insert(component_id.clone(), Value::Object(normalized));
    }
    let _ = Path::new(config_path);
    Ok(components)
}

fn flag_value(value: &str) -> Result<i64, String> {
    match value {
        "1" | "true" | "on" => Ok(1),
        "0" | "false" | "off" | "" => Ok(0),
        other => Err(format!("unsupported flag value {other:?}; use 0 or 1")),
    }
}

fn flag_json(value: &Value) -> Result<i64, String> {
    match value {
        Value::Number(number) if number.as_i64() == Some(1) => Ok(1),
        Value::Number(number) if number.as_i64() == Some(0) => Ok(0),
        Value::Bool(true) => Ok(1),
        Value::Bool(false) | Value::Null => Ok(0),
        Value::String(text) => flag_value(text),
        other => Err(format!("unsupported flag value {other}; use 0 or 1")),
    }
}
