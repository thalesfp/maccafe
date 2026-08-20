use std::time::Duration;

use clap::error::ErrorKind;
use clap::{Args, CommandFactory, Parser, Subcommand, ValueEnum};

use crate::duration;
use crate::report;
use crate::state::AssertionKind;

/// Rejects `--json` for the subcommands that own stdout, so no other module has
/// to know the combination is impossible.
pub fn parse() -> Cli {
    let wants_json = std::env::args()
        .take_while(|argument| argument != "--")
        .any(|argument| argument == "--json");
    let cli = Cli::try_parse().unwrap_or_else(|error| refuse(error, wants_json));

    if cli.json
        && let Some(reason) = cli.command.owns_stdout()
    {
        refuse(
            Cli::command().error(
                ErrorKind::ArgumentConflict,
                format!("{reason}, so it has no --json form"),
            ),
            true,
        );
    }

    cli
}

/// clap prints its own message and exits, which would leave `--json` callers with
/// prose on the failure they meet most often: a mistyped argument.
fn refuse(error: clap::Error, wants_json: bool) -> ! {
    if !wants_json || !error.use_stderr() {
        error.exit();
    }

    let message = error
        .to_string()
        .lines()
        .next()
        .unwrap_or_default()
        .trim_start_matches("error: ")
        .to_string();

    println!("{}", report::failure(true, &anyhow::Error::msg(message)));
    std::process::exit(error.exit_code());
}

#[derive(Parser)]
#[command(name = "maccafe", version, about = "Keep this Mac awake")]
pub struct Cli {
    /// Print machine-readable output; not supported by `run`
    #[arg(long, global = true)]
    pub json: bool,

    #[command(subcommand)]
    pub command: CommandChoice,
}

#[derive(Subcommand)]
pub enum CommandChoice {
    /// Keep this Mac awake in the background until `maccafe off`
    On {
        #[command(flatten)]
        options: HoldOptions,
    },

    /// Let this Mac sleep normally again
    Off,

    /// Show whether this Mac is being kept awake
    Status,

    /// Keep this Mac awake while this command runs in the foreground
    Run {
        #[command(flatten)]
        options: HoldOptions,

        /// Command to run; the Mac stays awake until it exits
        #[arg(last = true, conflicts_with = "duration")]
        command: Vec<String>,
    },

    /// Serve the maccafe tools over MCP on stdio
    Mcp,

    #[command(hide = true)]
    Hold {
        #[arg(long)]
        kind: AssertionKind,

        #[arg(long, value_parser = parse_duration)]
        duration: Option<Duration>,
    },
}

impl CommandChoice {
    /// Why this subcommand cannot also print a report, if it cannot.
    fn owns_stdout(&self) -> Option<&'static str> {
        match self {
            Self::Run { .. } => Some("run streams the output of the command it holds for"),
            Self::Mcp => Some("mcp speaks the protocol on stdio"),
            Self::On { .. } | Self::Off | Self::Status | Self::Hold { .. } => None,
        }
    }
}

#[derive(Args)]
pub struct HoldOptions {
    /// Stop after this long, for example 45s, 90m, 2h, or 1h30m
    #[arg(long, value_parser = parse_duration)]
    pub duration: Option<Duration>,

    /// Let the display sleep, and only keep the system awake
    #[arg(long)]
    pub system_only: bool,
}

impl HoldOptions {
    pub fn kind(&self) -> AssertionKind {
        AssertionKind::for_system_only(self.system_only)
    }
}

pub fn hold_arguments(kind: AssertionKind, limit: Option<Duration>) -> Vec<String> {
    let name = kind
        .to_possible_value()
        .expect("every assertion kind is a clap value")
        .get_name()
        .to_string();

    let mut arguments = vec!["hold".to_string(), "--kind".to_string(), name];

    if let Some(limit) = limit {
        arguments.push("--duration".to_string());
        arguments.push(format!("{}s", limit.as_secs()));
    }

    arguments
}

fn parse_duration(input: &str) -> Result<Duration, String> {
    duration::parse(input).map_err(|error| error.to_string())
}
