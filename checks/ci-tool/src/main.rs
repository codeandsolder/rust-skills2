use std::{env, error::Error, path::PathBuf, process::ExitCode};

fn run() -> Result<(), Box<dyn Error>> {
    let mut args = env::args().skip(1);
    let root = PathBuf::from(
        args.next()
            .ok_or("usage: rust-skills-ci ROOT validate|index|inventory|pins [--check]")?,
    );
    let action = args
        .next()
        .ok_or("usage: rust-skills-ci ROOT validate|index|inventory|pins [--check]")?;
    match action.as_str() {
        "validate" if args.next().is_none() => rust_skills_ci::validate(&root),
        "inventory" if args.next().is_none() => rust_skills_ci::inventory(&root),
        "pins" if args.next().is_none() => rust_skills_ci::pins::pins(&root),
        "index" => {
            let check = match args.next().as_deref() {
                None => false,
                Some("--check") if args.next().is_none() => true,
                _ => return Err("usage: rust-skills-ci ROOT index [--check]".into()),
            };
            rust_skills_ci::index(&root, check)
        }
        _ => Err("usage: rust-skills-ci ROOT validate|index|inventory|pins [--check]".into()),
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
