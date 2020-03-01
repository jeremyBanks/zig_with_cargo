use tar::Archive;
use xz2::read::XzDecoder;

// TODO: does Path::new(file!()).parent() work for us instead?
pub static TAR_XZ: &[u8] = include_bytes!("zig-linux-x86_64-0.5.0.tar.xz");

pub fn zig_bin() -> String {
    let out_dir = std::env::var("OUT_DIR").expect(
        "OUT_DIR expected (not called from build script?), see:\nhttps://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates");

    let zig_dist_dir = out_dir.to_string() + "/zig_build_linux_x86_64";

    let tar = XzDecoder::new(TAR_XZ);
    let mut archive = Archive::new(tar);
    archive.unpack(&zig_dist_dir).expect("failed to untar zig");

    zig_dist_dir + "/zig-linux-x86_64-0.5.0/zig"
}
