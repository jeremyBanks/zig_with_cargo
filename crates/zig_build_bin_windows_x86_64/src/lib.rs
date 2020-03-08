use std::path::Path;

static RELEASE: &str = "windows-x86_64-0.5.0+80ff549e2";

pub fn zig_bin() -> String {
    Path::new(file!())
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join(String::new() + "zig-" + RELEASE)
        .join("zig.exe")
    .to_str().unwrap().to_string()
}
