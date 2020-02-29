fn main() {
    let zig_bin = "./zig";
    let project_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let out_dir = std::env::var("OUT_DIR").unwrap();
    let lib_dir = out_dir + "/zig-lib";
    let lib_name = "ziggy";
    let src_path = project_dir.to_string() + "/src/ziggy.zig";

    let output = std::process::Command::new(zig_bin)
        .args(&[
            "build-lib",
            "-fPIC",
            "--bundle-compiler-rt",
            "--output-dir",
            // "--disable-gen-h",
            // if you start encountering https://github.com/ziglang/zig/issues/2173
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

    let bindings = bindgen::Builder::default()
        .header(lib_dir + "/" + lib_name + ".h")
        .generate()
        .expect("Unable to generate bindings");

    bindings
        .write_to_file(project_dir + "/src/ziggy.rs")
        .expect("Couldn't write bindings!");
}
