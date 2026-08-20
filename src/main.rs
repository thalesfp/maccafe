mod assertion;
mod cli;
mod control;
mod duration;
mod holder;
mod lock;
mod process;
mod report;
mod state;
mod timestamp;

use anyhow::Result;

use cli::{Cli, CommandChoice};
use holder::Until;

fn main() {
    let cli = cli::parse();
    let json = cli.json;

    if let Err(error) = run(cli) {
        let message = report::failure(json, &error);

        if json {
            println!("{message}");
        } else {
            eprintln!("{message}");
        }

        std::process::exit(1);
    }
}

fn run(cli: Cli) -> Result<()> {
    let paths = state::paths()?;

    match cli.command {
        CommandChoice::On { options } => {
            let status = control::turn_on(&paths, options.kind(), options.duration)?;

            println!("{}", report::status(cli.json, &status));
        }

        CommandChoice::Off => {
            let action = control::turn_off(&paths)?;

            println!("{}", report::off(cli.json, &action));
        }

        CommandChoice::Status => {
            let status = control::read_status(&paths)?;

            println!("{}", report::status(cli.json, &status));
        }

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
