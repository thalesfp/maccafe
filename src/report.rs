use anyhow::Error;
use serde_json::{Value, json};

use crate::control::{OffAction, StatusReport};
use crate::timestamp;

pub fn status(json: bool, report: &StatusReport) -> String {
    if json {
        status_value(report).to_string()
    } else {
        report.to_string()
    }
}

pub fn off(json: bool, action: &OffAction) -> String {
    if json {
        off_value(action).to_string()
    } else {
        action.to_string()
    }
}

pub fn failure(json: bool, error: &Error) -> String {
    if json {
        json!({ "error": format!("{error:#}") }).to_string()
    } else {
        format!("maccafe: {error:#}")
    }
}

pub(crate) fn status_value(report: &StatusReport) -> Value {
    let StatusReport::On(hold) = report else {
        return json!({ "held": false });
    };

    json!({
        "held": true,
        "kind": hold.state.kind,
        "pid": hold.state.pid,
        "started_at": timestamp::to_rfc3339(hold.state.started_at),
        "expires_at": hold.state.expires_at.map(timestamp::to_rfc3339),
        "elapsed_seconds": hold.elapsed().as_secs(),
        "remaining_seconds": hold.remaining().map(|left| left.as_secs()),
    })
}

pub(crate) fn off_value(action: &OffAction) -> Value {
    json!({
        "held": false,
        "stopped": matches!(action, OffAction::Stop),
    })
}

#[cfg(test)]
mod tests {
    use crate::control::Hold;
    use crate::state::{AssertionKind, State};

    use super::*;

    fn a_hold(expires_at: Option<u64>) -> StatusReport {
        StatusReport::On(Hold {
            state: State {
                pid: 321,
                kind: AssertionKind::Display,
                started_at: 1_787_184_892,
                expires_at,
            },
            now: 1_787_185_132,
        })
    }

    #[test]
    fn reports_a_hold_that_runs_out() {
        let held = status_value(&a_hold(Some(1_787_188_492)));

        assert_eq!(
            held,
            json!({
                "held": true,
                "kind": "display",
                "pid": 321,
                "started_at": "2026-08-20T00:14:52Z",
                "expires_at": "2026-08-20T01:14:52Z",
                "elapsed_seconds": 240,
                "remaining_seconds": 3_360,
            })
        );
    }

    #[test]
    fn leaves_the_end_of_an_open_ended_hold_empty() {
        let held = status_value(&a_hold(None));

        assert_eq!(held["expires_at"], Value::Null);
        assert_eq!(held["remaining_seconds"], Value::Null);
    }

    #[test]
    fn reports_a_mac_that_is_free_to_sleep() {
        assert_eq!(status_value(&StatusReport::Off), json!({ "held": false }));
    }

    #[test]
    fn tells_a_stopped_hold_apart_from_one_that_was_never_running() {
        assert_eq!(off_value(&OffAction::Stop)["stopped"], Value::Bool(true));
        assert_eq!(
            off_value(&OffAction::NothingToDo)["stopped"],
            Value::Bool(false)
        );
        assert_eq!(
            off_value(&OffAction::ClearStale)["stopped"],
            Value::Bool(false)
        );
    }

    #[test]
    fn reports_a_failure_with_its_cause() {
        let error = Error::msg("cannot open the lock").context("cannot stop the hold");

        assert_eq!(
            failure(true, &error),
            r#"{"error":"cannot stop the hold: cannot open the lock"}"#
        );
        assert_eq!(
            failure(false, &error),
            "maccafe: cannot stop the hold: cannot open the lock"
        );
    }
}
