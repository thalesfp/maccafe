use std::process::{Command, Output};

/// Only arguments that fail before any command runs, so these never touch the
/// state directory of the machine running the tests.
fn run(arguments: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_maccafe"))
        .args(arguments)
        .output()
        .expect("the maccafe binary should run")
}

#[test]
fn reports_a_mistyped_duration_as_json() {
    let refused = run(&["--json", "on", "--duration", "nope"]);

    let reported: serde_json::Value =
        serde_json::from_slice(&refused.stdout).expect("stdout should be json");

    assert_eq!(refused.status.code(), Some(2));
    assert!(
        reported["error"]
            .as_str()
            .unwrap()
            .contains("invalid duration"),
        "unexpected message: {reported}"
    );
}

#[test]
fn reports_a_forbidden_json_combination_as_json() {
    let refused = run(&["--json", "run", "--", "echo", "hello"]);

    let reported: serde_json::Value =
        serde_json::from_slice(&refused.stdout).expect("stdout should be json");

    assert_eq!(refused.status.code(), Some(2));
    assert!(
        reported["error"]
            .as_str()
            .unwrap()
            .contains("no --json form"),
        "unexpected message: {reported}"
    );
}

#[test]
fn keeps_prose_on_stderr_for_the_same_mistake_without_the_flag() {
    let refused = run(&["on", "--duration", "nope"]);

    assert_eq!(refused.status.code(), Some(2));
    assert!(refused.stdout.is_empty());
    assert!(String::from_utf8_lossy(&refused.stderr).contains("invalid duration"));
}

#[test]
fn leaves_a_child_commands_own_json_flag_alone() {
    let refused = run(&["run", "--duration", "nope", "--", "echo", "--json"]);

    assert_eq!(refused.status.code(), Some(2));
    assert!(refused.stdout.is_empty());
    assert!(String::from_utf8_lossy(&refused.stderr).contains("invalid duration"));
}

#[test]
fn keeps_help_on_stdout_even_with_the_flag() {
    let helped = run(&["--json", "--help"]);

    assert_eq!(helped.status.code(), Some(0));
    assert!(String::from_utf8_lossy(&helped.stdout).contains("Keep this Mac awake"));
}
