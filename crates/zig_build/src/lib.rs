pub fn lib(path: &str, name: &str) {
    let out_dir = std::env::var("OUT_DIR").expect(
        "OUT_DIR expected (not called from build script?), see:\nhttps://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates");
    let project_dir = std::env::var("CARGO_MANIFEST_DIR").expect(
        "CARGO_MANIFEST_DIR expected (not called from build script?), see:\nhttps://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates");

    let lib_dir = out_dir + "/zig-lib-" + name;

    let src_path = project_dir.to_string() + "/" + path;

    let zig_bin = zig_build_linux_x86_64::zig_bin();
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

    println!("cargo:rerun-if-changed={}", src_path);
    println!("cargo:rustc-link-search=native={}", lib_dir);
    println!("cargo:rustc-link-lib=static={}", name);
}
