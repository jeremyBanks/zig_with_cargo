use std::fs::File;
use std::path::Path;
use tar::Archive;
use xz2::read::XzDecoder;

static RELEASE: &str = "linux-x86_64-0.5.0";

pub fn zig_bin() -> String {
    let out_dir = std::env::var("OUT_DIR").expect(
        "OUT_DIR expected (not called from build script?), see:\nhttps://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates");

    let bin_path = String::new() + &out_dir + "/zig-" + RELEASE + "/zig";

    if !Path::new(&bin_path).exists() {
        let tar_xz = File::open(
            Path::new(file!())
                .parent()
                .unwrap()
                .parent()
                .unwrap()
                .join(format!("zig-{}.tar.xz", RELEASE)),
        )
        .expect("failed to open zig tarball");
        let tar = XzDecoder::new(tar_xz);
        let mut archive = Archive::new(tar);
        archive.unpack(&out_dir).expect("failed to untar zig");
    }

    return bin_path;
}
