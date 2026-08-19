use std::fmt;
use std::time::Duration;

#[derive(Debug, PartialEq)]
pub struct ParseError(String);

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "invalid duration {:?}: expected a value like 45s, 90m, 2h, or 1h30m",
            self.0
        )
    }
}

impl std::error::Error for ParseError {}

pub fn parse(input: &str) -> Result<Duration, ParseError> {
    let invalid = || ParseError(input.to_string());

    let mut total: u64 = 0;
    let mut value: u64 = 0;
    let mut digits = false;
    let mut units = false;

    for character in input.trim().chars() {
        if let Some(digit) = character.to_digit(10) {
            value = value
                .checked_mul(10)
                .and_then(|shifted| shifted.checked_add(digit.into()))
                .ok_or_else(invalid)?;
            digits = true;
            continue;
        }

        let multiplier = match character {
            's' | 'S' => 1,
            'm' | 'M' => 60,
            'h' | 'H' => 3_600,
            'd' | 'D' => 86_400,
            _ => return Err(invalid()),
        };

        if !digits {
            return Err(invalid());
        }

        total = value
            .checked_mul(multiplier)
            .and_then(|seconds| total.checked_add(seconds))
            .ok_or_else(invalid)?;
        value = 0;
        digits = false;
        units = true;
    }

    if digits {
        if units {
            return Err(invalid());
        }

        total = value;
    }

    if total == 0 {
        return Err(invalid());
    }

    Ok(Duration::from_secs(total))
}

pub fn format(duration: Duration) -> String {
    let total = duration.as_secs();
    let hours = total / 3_600;
    let minutes = (total % 3_600) / 60;
    let seconds = total % 60;

    let mut parts = Vec::new();
    if hours > 0 {
        parts.push(format!("{hours}h"));
    }
    if minutes > 0 {
        parts.push(format!("{minutes}m"));
    }
    if seconds > 0 || parts.is_empty() {
        parts.push(format!("{seconds}s"));
    }

    parts.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_single_unit() {
        assert_eq!(parse("45s"), Ok(Duration::from_secs(45)));
        assert_eq!(parse("90m"), Ok(Duration::from_secs(5_400)));
        assert_eq!(parse("2h"), Ok(Duration::from_secs(7_200)));
        assert_eq!(parse("1d"), Ok(Duration::from_secs(86_400)));
    }

    #[test]
    fn reads_combined_units() {
        assert_eq!(parse("1h30m"), Ok(Duration::from_secs(5_400)));
        assert_eq!(parse("1h30m15s"), Ok(Duration::from_secs(5_415)));
    }

    #[test]
    fn treats_a_bare_number_as_seconds() {
        assert_eq!(parse("120"), Ok(Duration::from_secs(120)));
    }

    #[test]
    fn rejects_input_a_user_can_realistically_mistype() {
        assert!(parse("").is_err());
        assert!(parse("abc").is_err());
        assert!(parse("10x").is_err());
        assert!(parse("1h30").is_err());
        assert!(parse("0s").is_err());
    }

    #[test]
    fn writes_a_readable_remaining_time() {
        assert_eq!(format(Duration::from_secs(0)), "0s");
        assert_eq!(format(Duration::from_secs(45)), "45s");
        assert_eq!(format(Duration::from_secs(5_400)), "1h 30m");
        assert_eq!(format(Duration::from_secs(3_661)), "1h 1m 1s");
    }
}
