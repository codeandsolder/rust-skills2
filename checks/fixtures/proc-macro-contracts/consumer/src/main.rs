use api::{Greet, Hello, MyTrait};

#[derive(api::Greet)]
struct Robot;

#[derive(api::Hello)]
struct Widget<T>(T);

#[derive(api::MyTrait)]
struct Record {
    value: u8,
}

fn main() {
    let robot = Robot;
    assert_eq!(robot.greet(), "hello, Robot");

    let widget = Widget(42u8);
    assert_eq!(widget.hello(), "Widget");

    assert_eq!(Record::first_field_name(), "value");
    let _ = Record { value: 7 };
}
