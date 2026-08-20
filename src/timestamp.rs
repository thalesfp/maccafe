/// Formats a unix timestamp as an RFC 3339 instant in UTC.
pub fn to_rfc3339(seconds: u64) -> String {
    let days = (seconds / 86_400) as i64;
    let time = seconds % 86_400;
    let (year, month, day) = civil_from_days(days);

    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        time / 3_600,
        (time % 3_600) / 60,
        time % 60
    )
}

/// Howard Hinnant's civil_from_days, with the era starting on 0000-03-01 so leap
/// days land at the end of a four-century cycle.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let shifted = days + 719_468;
    let era = shifted / 146_097;
    let day_of_era = shifted % 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let shifted_month = (5 * day_of_year + 2) / 153;
    let day = (day_of_year - (153 * shifted_month + 2) / 5 + 1) as u32;

    let month = if shifted_month < 10 {
        shifted_month + 3
    } else {
        shifted_month - 9
    } as u32;

    (if month <= 2 { year + 1 } else { year }, month, day)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_the_start_of_the_unix_epoch() {
        assert_eq!(to_rfc3339(0), "1970-01-01T00:00:00Z");
    }

    #[test]
    fn writes_a_time_a_hold_can_actually_start_at() {
        assert_eq!(to_rfc3339(1_787_184_892), "2026-08-20T00:14:52Z");
        assert_eq!(to_rfc3339(1_234_567_890), "2009-02-13T23:31:30Z");
    }

    #[test]
    fn writes_a_leap_day() {
        assert_eq!(to_rfc3339(951_782_400), "2000-02-29T00:00:00Z");
    }
}
