pub mod ziggy {
    #[link(name = "ziggy")]
    extern "C" {
        pub fn ziggy() -> ();
    }
}

fn main() {
    println!("Hello, world from Rust!");
    unsafe {
        ziggy::ziggy();
    }
}
