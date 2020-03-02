mod ziggy;

fn main() {
    println!("Hello, world from Rust!");

    unsafe {
        ziggy::ziggy();
    }
}

#[no_mangle]
pub extern "C" fn foo() {
    println!("hello from rust from what?");
}
