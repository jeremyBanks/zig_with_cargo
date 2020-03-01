#[cfg(all(target_arch = "x86_64", any(linux, unix)))]
use zig_build_bin_linux_x86_64::zig_bin;

#[cfg(all(target_arch = "x86_64", windows))]
use zig_build_bin_windows_x86_64::zig_bin;

#[cfg(all(target_arch = "x86_64", macos))]
use zig_build_bin_macos_x86_64::zig_bin;

use bindgen;

pub fn lib(path: &str, name: &str) {
    let out_dir = std::env::var("OUT_DIR").expect(
        "OUT_DIR expected (not called from build script?), see:\nhttps://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates");
    let project_dir = std::env::var("CARGO_MANIFEST_DIR").expect(
        "CARGO_MANIFEST_DIR expected (not called from build script?), see:\nhttps://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates");

    let lib_dir = out_dir + "/zig-lib-" + name;

    let src_path = project_dir.to_string() + "/" + path;

    let zig_bin: String = zig_bin();

    eprintln!("zig_bin = {:?}", zig_bin);

    let output = std::process::Command::new(&zig_bin)
        .args(&[
            "build-lib",
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
            panic!();
        }
        Ok(output) => {
            if !output.status.success() {
                eprintln!(
                    "zig compilation failed: {:?}",
                    std::str::from_utf8(&output.stderr).map_err(|_err| &output.stderr)
                );
                panic!();
            }
        }
    }

    let bindings = bindgen::Builder::default()
    .header(String::new() + &lib_dir + "/" + name + ".h")
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(src_path[..src_path.len() - 4].to_string() + ".rs")
        .expect("Couldn't write bindings!");

    println!("cargo:rustc-link-search=native={}", lib_dir);
    println!("cargo:rustc-link-lib=static={}", name);
    
}
