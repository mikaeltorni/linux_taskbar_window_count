//! GSettings string-array helpers for the installer (`wwc-tools` CLI).
//!
//! Matches the former Python helper: parse `gsettings get` output, append a
//! value without duplicating it, and print a `gsettings set`-ready literal.

use std::collections::HashSet;
use std::env;

use crate::logging;

/// Parse `gsettings get` string-array output into normalized values.
///
/// Unparseable input yields an empty list (the historical Python contract used
/// by `append_gsettings_list`, which then appends the requested UUID).
///
/// # Parameters
/// - `raw`: Optional `gsettings get` output (`@as [...]` or `[...]`). `None`
///   and empty strings yield an empty list.
pub fn parse_strv(raw: Option<&str>) -> Vec<String> {
    let mut value = raw.unwrap_or("").trim().to_string();
    if let Some(rest) = value.strip_prefix("@as ") {
        value = rest.trim().to_string();
    }
    if value.is_empty() {
        return Vec::new();
    }
    match string_list(&value) {
        Some(items) => items,
        None => {
            logging::warn("Unparsable GSettings string-array value; using []");
            Vec::new()
        }
    }
}

/// Parse a GVariant string list like `['a', "b"]` (UTF-8 safe).
fn string_list(value: &str) -> Option<Vec<String>> {
    let value = value.trim();
    if !value.starts_with('[') || !value.ends_with(']') {
        return None;
    }
    let inner = value[1..value.len() - 1].trim();
    if inner.is_empty() {
        return Some(Vec::new());
    }

    let mut items = Vec::new();
    let mut chars = inner.chars().peekable();
    while let Some(&ch) = chars.peek() {
        if ch.is_whitespace() || ch == ',' {
            chars.next();
            continue;
        }
        let quote = chars.next()?;
        if quote != '\'' && quote != '"' {
            return None;
        }
        let mut out = String::new();
        let mut closed = false;
        while let Some(c) = chars.next() {
            if c == '\\' {
                match chars.next()? {
                    'a' => out.push('\u{7}'),
                    'b' => out.push('\u{8}'),
                    'f' => out.push('\u{c}'),
                    'n' => out.push('\n'),
                    'r' => out.push('\r'),
                    't' => out.push('\t'),
                    'v' => out.push('\u{b}'),
                    escape @ ('u' | 'U') => {
                        let digits = if escape == 'u' { 4 } else { 8 };
                        let mut codepoint = 0;
                        for _ in 0..digits {
                            codepoint = (codepoint << 4) | chars.next()?.to_digit(16)?;
                        }
                        out.push(char::from_u32(codepoint)?);
                    }
                    '\n' => {}
                    escaped => out.push(escaped),
                }
                continue;
            }
            if c == quote {
                closed = true;
                break;
            }
            out.push(c);
        }
        if !closed {
            return None;
        }
        items.push(out);
    }
    Some(items)
}

/// De-duplicate while preserving first appearance.
///
/// # Parameters
/// - `values`: Input list that may contain duplicates.
pub fn unique_values(values: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for v in values {
        if seen.insert(v.clone()) {
            out.push(v);
        }
    }
    out
}

/// Append `value` when non-empty and not already present.
///
/// # Parameters
/// - `raw`: Current `gsettings get` string-array text (or `None`).
/// - `value`: Entry to append.
pub fn append_strv(raw: Option<&str>, value: &str) -> Vec<String> {
    let mut current = unique_values(parse_strv(raw));
    if !value.is_empty() && !current.iter().any(|item| item == value) {
        current.push(value.to_string());
        logging::info(format!(
            "Appended GSettings string-array value; entry count is {}",
            current.len()
        ));
    } else {
        logging::debug("GSettings string-array already contained requested value");
    }
    current
}

/// Serialize values for `gsettings set` with GVariant string escapes.
///
/// # Parameters
/// - `values`: Normalized string-array entries.
pub fn format_strv(values: &[String]) -> String {
    let parts: Vec<String> = values
        .iter()
        .map(|item| {
            let mut literal = String::from("'");
            for character in item.chars() {
                match character {
                    '\\' => literal.push_str("\\\\"),
                    '\'' => literal.push_str("\\'"),
                    '\u{7}' => literal.push_str("\\a"),
                    '\u{8}' => literal.push_str("\\b"),
                    '\u{c}' => literal.push_str("\\f"),
                    '\n' => literal.push_str("\\n"),
                    '\r' => literal.push_str("\\r"),
                    '\t' => literal.push_str("\\t"),
                    '\u{b}' => literal.push_str("\\v"),
                    control if control.is_control() => {
                        literal.push_str(&format!("\\u{:04x}", u32::from(control)));
                    }
                    printable => literal.push(printable),
                }
            }
            literal.push('\'');
            literal
        })
        .collect();
    format!("[{}]", parts.join(", "))
}

/// CLI entry: one positional value, existing array from `CURRENT`.
///
/// # Returns
/// `0` after printing the serialized array. `2` when the argument count is
/// wrong (usage written to stderr).
pub fn run_cli() -> i32 {
    let mut args = env::args().skip(1);
    let Some(value) = args.next() else {
        logging::error("Expected exactly one argument, got 0");
        eprintln!("Usage: wwc-tools <value>");
        return 2;
    };
    if args.next().is_some() {
        logging::error("Expected exactly one argument, got more");
        eprintln!("Usage: wwc-tools <value>");
        return 2;
    }
    let current = env::var("CURRENT").unwrap_or_default();
    logging::info("Ensuring extension UUID is present in enabled-extensions");
    println!("{}", format_strv(&append_strv(Some(&current), &value)));
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn append_handles_gsettings_prefix_and_deduplicates() {
        assert_eq!(
            append_strv(
                Some("@as ['workspace-window-count@local']"),
                "workspace-window-count@local"
            ),
            vec!["workspace-window-count@local".to_string()]
        );
        assert_eq!(
            append_strv(Some("@as ['one']"), "two"),
            vec!["one".to_string(), "two".to_string()]
        );
    }

    #[test]
    fn append_treats_invalid_existing_values_as_empty() {
        assert_eq!(
            append_strv(Some("not an array"), "workspace-window-count@local"),
            vec!["workspace-window-count@local".to_string()]
        );
    }

    #[test]
    fn format_matches_gsettings_literal() {
        assert_eq!(format_strv(&["one".into(), "two".into()]), "['one', 'two']");
    }

    #[test]
    fn empty_forms_parse() {
        assert_eq!(parse_strv(None), Vec::<String>::new());
        assert_eq!(parse_strv(Some("")), Vec::<String>::new());
        assert_eq!(parse_strv(Some("[]")), Vec::<String>::new());
        assert_eq!(parse_strv(Some("@as []")), Vec::<String>::new());
    }

    #[test]
    fn utf8_values_round_trip() {
        let parsed = parse_strv(Some("@as ['café']"));
        assert_eq!(parsed, vec!["café".to_string()]);
        assert_eq!(format_strv(&parsed), "['café']");
    }

    #[test]
    fn gvariant_escapes_preserve_their_values() {
        let parsed = parse_strv(Some(
            r"['line\nbreak', 'tab\tend', 'caf\u00e9', 'rocket\U0001f680', 'quote\'end', 'slash\\end']",
        ));
        assert_eq!(
            parsed,
            vec![
                "line\nbreak",
                "tab\tend",
                "café",
                "rocket🚀",
                "quote'end",
                "slash\\end"
            ]
        );
        assert_eq!(
            format_strv(&parsed),
            "['line\\nbreak', 'tab\\tend', 'café', 'rocket🚀', 'quote\\'end', 'slash\\\\end']"
        );
    }

    #[test]
    fn control_escapes_and_continuations_round_trip() {
        let parsed = parse_strv(Some("['\\a\\b\\f\\r\\v\\u0001', 'one\\\ntwo']"));
        assert_eq!(parsed, vec!["\u{7}\u{8}\u{c}\r\u{b}\u{1}", "onetwo"]);
        assert_eq!(format_strv(&parsed), "['\\a\\b\\f\\r\\v\\u0001', 'onetwo']");
    }
}
