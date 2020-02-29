fn main() {
    let zig_bin = "./zig";
    let project_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let out_dir = std::env::var("OUT_DIR").unwrap();
    let lib_dir = out_dir + "/zig-lib";
    let lib_name = "ziggy";
    let src_path = project_dir + "/src/ziggy.zig";

    let output = std::process::Command::new(zig_bin)
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
            panic!("unable to execute zig: {:?}", error);
        }
        Ok(output) => {
            if !output.status.success() {
                panic!("zig compilation failed: {:?}", output.stderr);
            }
        }
    }

    println!("cargo:rerun-if-changed={}", src_path);
    println!("cargo:rustc-link-search=native={}", lib_dir);
    println!("cargo:rustc-link-lib=static={}", lib_name);
}
