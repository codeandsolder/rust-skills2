use source_policy::{
    check::{Input, check},
    lint_attributes,
};
use std::{env, error::Error, fs, io, path::PathBuf, process::ExitCode};

fn scan() -> Result<(), Box<dyn Error>> {
    let paths: Vec<PathBuf> = serde_json::from_reader(io::stdin().lock())?;
    let results = paths
        .iter()
        .map(|path| {
            let source = fs::read_to_string(path)?;
            Ok((path, lint_attributes(&source)))
        })
        .collect::<Result<Vec<_>, io::Error>>()?;
    serde_json::to_writer(io::stdout().lock(), &results)?;
    Ok(())
}

fn run() -> Result<(), Box<dyn Error>> {
    match env::args().nth(1).as_deref() {
        Some("scan") => scan(),
        Some("check") => {
            let input: Input = serde_json::from_reader(io::stdin().lock())?;
            let report = check(input)?;
            serde_json::to_writer(io::stdout().lock(), &report)?;
            Ok(())
        }
        _ => Err("usage: source-policy scan|check".into()),
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("rust-skills2: {error}");
            ExitCode::from(2)
        }
    }
}
