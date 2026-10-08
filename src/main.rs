//! `wwc-tools` — installer-facing helpers for workspace-window-count.
//!
//! Usage (matches the former `lib/gsettings_strv.py` contract):
//!
//! ```text
//! CURRENT="@as ['one']" wwc-tools two
//! # -> ['one', 'two']
//! ```

mod gsettings_strv;
mod logging;
mod selection;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--selection") {
        std::process::exit(selection::run(&args[1..]));
    }
    std::process::exit(gsettings_strv::run_cli());
}
