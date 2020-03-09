pub mod ziggy {
    #[link(name = "ziggy")]
    extern "C" {
        pub fn rust_main() -> ();
    }
}

fn main() {
    unsafe {
        ziggy::rust_main();
    }
}
