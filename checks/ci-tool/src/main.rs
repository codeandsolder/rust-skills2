use std::{env, error::Error, path::PathBuf, process::ExitCode};

fn run() -> Result<(), Box<dyn Error>> {
    let mut args = env::args().skip(1);
    let root = PathBuf::from(
        args.next()
            .ok_or("usage: rust-skills-ci ROOT validate|index|inventory|pins|generate|ambient|cancellation|analyze [--check]")?,
    );
    let action = args
        .next()
        .ok_or("usage: rust-skills-ci ROOT validate|index|inventory|pins|generate|ambient|cancellation|analyze [--check]")?;
    match action.as_str() {
        "validate" if args.next().is_none() => rust_skills_ci::validate(&root),
        "inventory" if args.next().is_none() => rust_skills_ci::inventory(&root),
        "pins" if args.next().is_none() => rust_skills_ci::pins::pins(&root),
        "analyze" => rust_skills_ci::analyzer::run(&root, &args.collect::<Vec<_>>()),
        "ambient" if args.next().is_none() => rust_skills_ci::ambient::verify(&root, std::io::stdin().lock()),
        "cancellation" => {
            let file = PathBuf::from(args.next().ok_or("usage: rust-skills-ci ROOT cancellation OUTPUT")?);
            if args.next().is_some() { return Err("unexpected cancellation arguments".into()); }
            rust_skills_ci::cancellation::generate(&root, &file)
        },
        "generate" => {
            let output = match args.next().as_deref() {
                None => root.join("checks"),
                Some("--output") => PathBuf::from(args.next().ok_or("missing --output directory")?),
                _ => return Err("usage: rust-skills-ci ROOT generate [--output DIRECTORY]".into()),
            };
            if args.next().is_some() {
                return Err("unexpected generator arguments".into());
            }
            rust_skills_ci::generator::generate(
                &root.join("rules"),
                &root.join("checks/fixtures"),
                &output,
            )
        }
        "index" => {
            let check = match args.next().as_deref() {
                None => false,
                Some("--check") if args.next().is_none() => true,
                _ => return Err("usage: rust-skills-ci ROOT index [--check]".into()),
            };
            rust_skills_ci::index(&root, check)
        }
        _ => Err(
            "usage: rust-skills-ci ROOT validate|index|inventory|pins|generate|ambient|cancellation|analyze [--check]".into(),
        ),
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
