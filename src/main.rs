mod ziggy;

fn main() {
    println!("Hello, world from Rust!");
    unsafe {
        ziggy::ziggy();
    }
}
