pub mod ziggy {
    #[link(name = "ziggy")]
    extern "C" {
        pub fn ziggy() -> ();
    }
}

fn main() {
    unsafe {
        ziggy::ziggy();
    }
}
