mod assertion;
mod cli;
mod control;
mod duration;
mod holder;
mod lock;
mod state;

use anyhow::Result;
use clap::Parser;

use cli::{Cli, CommandChoice};
use holder::Until;

fn main() {
    if let Err(error) = run() {
        eprintln!("maccafe: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    let paths = state::paths()?;

    match cli.command {
        CommandChoice::On { options } => {
            println!(
                "{}",
                control::turn_on(&paths, options.kind(), options.duration)?
            );
        }

        CommandChoice::Off => println!("{}", control::turn_off(&paths)?),

        CommandChoice::Status => println!("{}", control::read_status(&paths)?),

        CommandChoice::Run { options, command } => {
            let until = Until::for_request(command, options.duration);
            let code = holder::hold(&paths, options.kind(), until)?;

            std::process::exit(code);
        }

        CommandChoice::Hold { kind, duration } => {
            holder::hold(&paths, kind, Until::for_request(Vec::new(), duration))?;
        }
    }

    Ok(())
}
