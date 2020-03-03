mod generated;

use generated::zig_lib;

fn main() {
    println!("Hello, world from Rust!");

    unsafe {
        zig_lib::ziggy();
    }
}
