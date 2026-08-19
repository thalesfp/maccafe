use std::time::Duration;

use clap::{Args, Parser, Subcommand, ValueEnum};

use crate::duration;
use crate::state::AssertionKind;

#[derive(Parser)]
#[command(name = "maccafe", version, about = "Keep this Mac awake")]
pub struct Cli {
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

    #[command(hide = true)]
    Hold {
        #[arg(long)]
        kind: AssertionKind,

        #[arg(long, value_parser = parse_duration)]
        duration: Option<Duration>,
    },
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
        if self.system_only {
            AssertionKind::System
        } else {
            AssertionKind::Display
        }
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
