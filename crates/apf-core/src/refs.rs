use std::{error::Error, fmt, str::FromStr};

const MAX_REF_LENGTH: usize = 128;

/// A malformed stable APF entity reference.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RefError {
    expected_prefix: &'static str,
    value: String,
}

impl RefError {
    #[must_use]
    pub fn expected_prefix(&self) -> &'static str {
        self.expected_prefix
    }

    #[must_use]
    pub fn value(&self) -> &str {
        &self.value
    }
}

impl fmt::Display for RefError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "invalid APF reference; expected prefix {} and an uppercase alphanumeric suffix",
            self.expected_prefix
        )
    }
}

impl Error for RefError {}

fn validate_ref(value: &str, prefix: &'static str) -> Result<(), RefError> {
    let suffix = value.strip_prefix(prefix).ok_or_else(|| RefError {
        expected_prefix: prefix,
        value: value.to_owned(),
    })?;
    let valid_length = !suffix.is_empty() && value.len() <= MAX_REF_LENGTH;
    let valid_edges = !suffix.starts_with('-') && !suffix.ends_with('-');
    let valid_characters = suffix
        .bytes()
        .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit() || byte == b'-');

    if valid_length && valid_edges && valid_characters {
        Ok(())
    } else {
        Err(RefError {
            expected_prefix: prefix,
            value: value.to_owned(),
        })
    }
}

macro_rules! define_ref {
    ($name:ident, $prefix:literal) => {
        #[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
        pub struct $name(String);

        impl $name {
            pub const PREFIX: &'static str = $prefix;

            pub fn parse(value: impl Into<String>) -> Result<Self, RefError> {
                let value = value.into();
                validate_ref(&value, Self::PREFIX)?;
                Ok(Self(value))
            }

            #[must_use]
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl FromStr for $name {
            type Err = RefError;

            fn from_str(value: &str) -> Result<Self, Self::Err> {
                Self::parse(value)
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str(&self.0)
            }
        }
    };
}

define_ref!(ProjectRef, "PRJ-");
define_ref!(ActorRef, "ACT-");
define_ref!(TaskRef, "TASK-");
define_ref!(WorkOrderRef, "WO-");
define_ref!(RunRef, "RUN-");
define_ref!(EventRef, "EVT-");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_canonical_references() {
        let task: TaskRef = "TASK-GATE0-001".parse().expect("valid task ref");
        assert_eq!(task.as_str(), "TASK-GATE0-001");
        assert_eq!(task.to_string(), "TASK-GATE0-001");
    }

    #[test]
    fn rejects_wrong_prefix_lowercase_and_empty_suffix() {
        for value in ["RUN-0001", "TASK-lower", "TASK-"] {
            let error = TaskRef::parse(value).expect_err("invalid task ref");
            assert_eq!(error.expected_prefix(), "TASK-");
            assert_eq!(error.value(), value);
        }
    }

    #[test]
    fn rejects_ambiguous_hyphen_edges_and_oversized_refs() {
        assert!(TaskRef::parse("TASK--BAD").is_err());
        assert!(TaskRef::parse("TASK-BAD-").is_err());
        assert!(TaskRef::parse(format!("TASK-{}", "A".repeat(124))).is_err());
    }
}
