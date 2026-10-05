fn main() {
    println!("strict gate binary fixture");
}

#[cfg(test)]
mod tests {
    #[test]
    fn panic_style_test_assertions_are_allowed_by_opt_in() {
        let parsed = "11".parse::<usize>().expect("literal integer parses");
        assert_eq!(parsed, 11);
    }
}
