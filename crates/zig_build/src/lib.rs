#[cfg(all(target_arch = "x86_64", any(linux, unix)))]
use zig_build_bin_linux_x86_64::zig_bin;

#[cfg(all(target_arch = "x86_64", windows))]
use zig_build_bin_windows_x86_64::zig_bin;

#[cfg(all(target_arch = "x86_64", macos))]
use zig_build_bin_macos_x86_64::zig_bin;

pub fn lib(path: &str, name: &str) {
    let out_dir = std::env::var("OUT_DIR").expect(
        "OUT_DIR expected (not called from build script?), see:\nhttps://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates");
    let project_dir = std::env::var("CARGO_MANIFEST_DIR").expect(
        "CARGO_MANIFEST_DIR expected (not called from build script?), see:\nhttps://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates");
    let lib_dir = out_dir + "/zig-lib-" + name;
    let src_path = project_dir.to_string() + "/" + path;
    let zig_bin: String = zig_bin();

    cbindgen::Builder::new()
        .with_crate(&project_dir)
        .with_language(cbindgen::Language::C)
        .generate()
        .expect("Unable to generate zig -> rust bindings")
        .write_to_file(String::new() + &project_dir + "/src/rust.h");

    let output = std::process::Command::new(&zig_bin)
        .args(&[
            "build-lib",
            "--library",
            "c",
            "-fPIC",
            "--bundle-compiler-rt",
            "--output-dir",
            &lib_dir,
            &src_path,
        ])
        .output();

    match output {
        Err(error) => {
            eprintln!("unable to execute zig: {:?}", error);
            std::process::exit(1);
        }
        Ok(output) => {
            if !output.status.success() {
                eprintln!(
                    "  process didn't exit successfully: `{}` (exit code: {})\n--- stderr\n{}",
                    zig_bin,
                    output.status.code().unwrap(),
                    std::str::from_utf8(&output.stderr)
                        .map(|s| s.to_string())
                        .unwrap_or_else(|_err| format!("{:?}", &output.stderr))
                );
                std::process::exit(1);
            }
        }
    }

    bindgen::Builder::default()
        .header(String::new() + &lib_dir + "/" + name + ".h")
        .generate()
        .expect("Unable to generate rust -> zig bindings")
        .write_to_file(src_path[..src_path.len() - 4].to_string() + ".rs")
        .expect("Couldn't write bindings!");

    println!("cargo:rustc-link-search=native={}", lib_dir);
    println!("cargo:rustc-link-lib=static={}", name);
}
