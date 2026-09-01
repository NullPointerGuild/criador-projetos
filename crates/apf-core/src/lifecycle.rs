use std::{error::Error, fmt, num::NonZeroU32};

use jiff::Timestamp;

use crate::ActorRef;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskState {
    Proposed,
    Ready,
    Leased,
    Executing,
    InputRequired,
    Blocked,
    Review,
    ChangesRequested,
    Completed,
    Failed,
    Cancelled,
    Interrupted,
}

impl TaskState {
    #[must_use]
    pub const fn as_brain_str(self) -> &'static str {
        match self {
            Self::Proposed => "PROPOSED",
            Self::Ready => "READY",
            Self::Leased => "LEASED",
            Self::Executing => "EXECUTING",
            Self::InputRequired => "INPUT_REQUIRED",
            Self::Blocked => "BLOCKED",
            Self::Review => "REVIEW",
            Self::ChangesRequested => "CHANGES_REQUESTED",
            Self::Completed => "COMPLETED",
            Self::Failed => "FAILED",
            Self::Cancelled => "CANCELLED",
            Self::Interrupted => "INTERRUPTED",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum EffectKnowledge {
    NoExternalEffect,
    KnownExternalEffect,
    #[default]
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct CompletionEvidence {
    pub acceptance_passed: bool,
    pub checks_passed: bool,
    pub review_passed: bool,
}

impl CompletionEvidence {
    #[must_use]
    pub const fn verified() -> Self {
        Self {
            acceptance_passed: true,
            checks_passed: true,
            review_passed: true,
        }
    }

    const fn is_verified(self) -> bool {
        self.acceptance_passed && self.checks_passed && self.review_passed
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Lease {
    owner: ActorRef,
    expires_at: String,
}

impl Lease {
    pub fn new(owner: ActorRef, expires_at: impl Into<String>) -> Result<Self, LeaseError> {
        let expires_at = expires_at.into();
        let valid = valid_utc_timestamp(&expires_at);
        if !valid {
            return Err(LeaseError);
        }
        Ok(Self { owner, expires_at })
    }

    #[must_use]
    pub fn owner(&self) -> &ActorRef {
        &self.owner
    }

    #[must_use]
    pub fn expires_at(&self) -> &str {
        &self.expires_at
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LeaseError;

impl fmt::Display for LeaseError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("lease expiration must be a bounded UTC timestamp")
    }
}

impl Error for LeaseError {}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct TaskTransitionEvidence {
    pub lease: Option<Lease>,
    pub lease_expired: bool,
    pub effects: EffectKnowledge,
    pub completion: CompletionEvidence,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TaskLifecycle {
    state: TaskState,
    lease: Option<Lease>,
}

impl TaskLifecycle {
    #[must_use]
    pub const fn proposed() -> Self {
        Self {
            state: TaskState::Proposed,
            lease: None,
        }
    }

    pub fn restore(state: TaskState, lease: Option<Lease>) -> Result<Self, TaskTransitionError> {
        let requires_lease = matches!(state, TaskState::Leased | TaskState::Executing);
        if requires_lease != lease.is_some() {
            return Err(TaskTransitionError::LeaseInvariant);
        }
        Ok(Self { state, lease })
    }

    #[must_use]
    pub const fn state(&self) -> TaskState {
        self.state
    }

    #[must_use]
    pub fn lease(&self) -> Option<&Lease> {
        self.lease.as_ref()
    }

    pub fn transition(
        &mut self,
        target: TaskState,
        mut evidence: TaskTransitionEvidence,
    ) -> Result<(), TaskTransitionError> {
        if !allowed_task_transition(self.state, target) {
            return Err(TaskTransitionError::Illegal {
                from: self.state,
                to: target,
            });
        }

        match (self.state, target) {
            (TaskState::Ready, TaskState::Leased) => {
                self.lease = Some(
                    evidence
                        .lease
                        .take()
                        .ok_or(TaskTransitionError::LeaseRequired)?,
                );
            }
            (TaskState::Leased, TaskState::Executing) => {
                if self.lease.is_none() {
                    return Err(TaskTransitionError::LeaseInvariant);
                }
            }
            (TaskState::Leased, TaskState::Ready) => {
                if !evidence.lease_expired {
                    return Err(TaskTransitionError::ExpiredLeaseRequired);
                }
                if evidence.effects != EffectKnowledge::NoExternalEffect {
                    return Err(TaskTransitionError::NoEffectProofRequired);
                }
                self.lease = None;
            }
            (TaskState::Leased, TaskState::Interrupted) => {
                if !evidence.lease_expired {
                    return Err(TaskTransitionError::ExpiredLeaseRequired);
                }
                self.lease = None;
            }
            (TaskState::Review, TaskState::Completed) => {
                if !evidence.completion.is_verified() {
                    return Err(TaskTransitionError::CompletionEvidenceRequired);
                }
            }
            _ => {
                if !matches!(target, TaskState::Leased | TaskState::Executing) {
                    self.lease = None;
                }
            }
        }

        self.state = target;
        Ok(())
    }
}

const fn allowed_task_transition(from: TaskState, to: TaskState) -> bool {
    matches!(
        (from, to),
        (TaskState::Proposed, TaskState::Ready)
            | (TaskState::Ready, TaskState::Leased)
            | (
                TaskState::Leased,
                TaskState::Executing | TaskState::Ready | TaskState::Interrupted
            )
            | (
                TaskState::Executing,
                TaskState::Review
                    | TaskState::InputRequired
                    | TaskState::Blocked
                    | TaskState::Failed
                    | TaskState::Cancelled
                    | TaskState::Interrupted
            )
            | (
                TaskState::InputRequired | TaskState::Blocked,
                TaskState::Ready
            )
            | (
                TaskState::Review,
                TaskState::Completed | TaskState::ChangesRequested
            )
            | (TaskState::ChangesRequested, TaskState::Ready)
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskTransitionError {
    Illegal { from: TaskState, to: TaskState },
    LeaseRequired,
    LeaseInvariant,
    ExpiredLeaseRequired,
    NoEffectProofRequired,
    CompletionEvidenceRequired,
}

impl fmt::Display for TaskTransitionError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Illegal { from, to } => {
                write!(formatter, "illegal task transition: {from:?} -> {to:?}")
            }
            Self::LeaseRequired => formatter.write_str("READY -> LEASED requires a complete lease"),
            Self::LeaseInvariant => {
                formatter.write_str("LEASED and EXECUTING require exactly one complete lease")
            }
            Self::ExpiredLeaseRequired => {
                formatter.write_str("lease recovery requires expiration evidence")
            }
            Self::NoEffectProofRequired => {
                formatter.write_str("return to READY requires proof of no external effect")
            }
            Self::CompletionEvidenceRequired => {
                formatter.write_str("COMPLETED requires acceptance, checks and review")
            }
        }
    }
}

impl Error for TaskTransitionError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunStatus {
    Created,
    Starting,
    Running,
    InputRequired,
    Blocked,
    Review,
    Succeeded,
    Failed,
    Cancelled,
    Interrupted,
}

impl RunStatus {
    #[must_use]
    pub const fn as_brain_str(self) -> &'static str {
        match self {
            Self::Created => "CREATED",
            Self::Starting => "STARTING",
            Self::Running => "RUNNING",
            Self::InputRequired => "INPUT_REQUIRED",
            Self::Blocked => "BLOCKED",
            Self::Review => "REVIEW",
            Self::Succeeded => "SUCCEEDED",
            Self::Failed => "FAILED",
            Self::Cancelled => "CANCELLED",
            Self::Interrupted => "INTERRUPTED",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessIdentity {
    process_id: NonZeroU32,
    started_at: String,
    image_sha256: String,
    host_boot_id: String,
    supervisor_token: String,
}

impl ProcessIdentity {
    pub fn new(
        process_id: NonZeroU32,
        started_at: impl Into<String>,
        image_sha256: impl Into<String>,
        host_boot_id: impl Into<String>,
        supervisor_token: impl Into<String>,
    ) -> Result<Self, ProcessIdentityError> {
        let started_at = started_at.into();
        let image_sha256 = image_sha256.into();
        let host_boot_id = host_boot_id.into();
        let supervisor_token = supervisor_token.into();
        let valid_timestamp = valid_utc_timestamp(&started_at);
        let valid_hash = image_sha256.len() == 64
            && image_sha256
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte));
        let valid_opaque_fields = [host_boot_id.as_str(), supervisor_token.as_str()]
            .into_iter()
            .all(|value| {
                !value.is_empty() && value.len() <= 256 && !value.chars().any(char::is_control)
            });
        if !(valid_timestamp && valid_hash && valid_opaque_fields) {
            return Err(ProcessIdentityError);
        }
        Ok(Self {
            process_id,
            started_at,
            image_sha256,
            host_boot_id,
            supervisor_token,
        })
    }

    #[must_use]
    pub const fn process_id(&self) -> NonZeroU32 {
        self.process_id
    }

    #[must_use]
    pub fn started_at(&self) -> &str {
        &self.started_at
    }

    #[must_use]
    pub fn image_sha256(&self) -> &str {
        &self.image_sha256
    }

    #[must_use]
    pub fn host_boot_id(&self) -> &str {
        &self.host_boot_id
    }

    #[must_use]
    pub fn supervisor_token(&self) -> &str {
        &self.supervisor_token
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProcessIdentityError;

impl fmt::Display for ProcessIdentityError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .write_str("process identity must be complete and contain a lowercase SHA-256 digest")
    }
}

impl Error for ProcessIdentityError {}

fn valid_utc_timestamp(value: &str) -> bool {
    value.len() <= 64 && value.ends_with('Z') && value.parse::<Timestamp>().is_ok()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunLifecycle {
    status: RunStatus,
    process: Option<ProcessIdentity>,
}

impl RunLifecycle {
    #[must_use]
    pub const fn created() -> Self {
        Self {
            status: RunStatus::Created,
            process: None,
        }
    }

    pub fn restore(
        status: RunStatus,
        process: Option<ProcessIdentity>,
    ) -> Result<Self, RunTransitionError> {
        if status == RunStatus::Running && process.is_none() {
            return Err(RunTransitionError::ProcessIdentityRequired);
        }
        Ok(Self { status, process })
    }

    #[must_use]
    pub const fn status(&self) -> RunStatus {
        self.status
    }

    #[must_use]
    pub fn process(&self) -> Option<&ProcessIdentity> {
        self.process.as_ref()
    }

    pub fn transition(
        &mut self,
        target: RunStatus,
        process: Option<ProcessIdentity>,
    ) -> Result<(), RunTransitionError> {
        if !allowed_run_transition(self.status, target) {
            return Err(RunTransitionError::Illegal {
                from: self.status,
                to: target,
            });
        }
        if target == RunStatus::Running {
            self.process = process.or_else(|| self.process.take());
            if self.process.is_none() {
                return Err(RunTransitionError::ProcessIdentityRequired);
            }
        } else if process.is_some() {
            return Err(RunTransitionError::UnexpectedProcessIdentity);
        }
        self.status = target;
        Ok(())
    }
}

const fn allowed_run_transition(from: RunStatus, to: RunStatus) -> bool {
    matches!(
        (from, to),
        (RunStatus::Created, RunStatus::Starting)
            | (
                RunStatus::Starting,
                RunStatus::Running | RunStatus::Failed | RunStatus::Interrupted
            )
            | (
                RunStatus::Running,
                RunStatus::InputRequired
                    | RunStatus::Blocked
                    | RunStatus::Review
                    | RunStatus::Failed
                    | RunStatus::Cancelled
                    | RunStatus::Interrupted
            )
            | (
                RunStatus::InputRequired | RunStatus::Blocked,
                RunStatus::Running | RunStatus::Interrupted
            )
            | (
                RunStatus::Review,
                RunStatus::Succeeded | RunStatus::Failed | RunStatus::Interrupted
            )
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunTransitionError {
    Illegal { from: RunStatus, to: RunStatus },
    ProcessIdentityRequired,
    UnexpectedProcessIdentity,
}

impl fmt::Display for RunTransitionError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Illegal { from, to } => {
                write!(formatter, "illegal run transition: {from:?} -> {to:?}")
            }
            Self::ProcessIdentityRequired => {
                formatter.write_str("RUNNING requires a complete process identity")
            }
            Self::UnexpectedProcessIdentity => {
                formatter.write_str("process identity may only be attached when entering RUNNING")
            }
        }
    }
}

impl Error for RunTransitionError {}

#[cfg(test)]
mod tests {
    use super::*;

    fn lease() -> Lease {
        Lease::new(
            ActorRef::parse("ACT-WORKER-001").expect("valid actor"),
            "2026-08-31T16:00:00Z",
        )
        .expect("valid lease")
    }

    fn process() -> ProcessIdentity {
        ProcessIdentity::new(
            NonZeroU32::new(42).expect("non-zero"),
            "2026-08-31T15:00:00Z",
            "a".repeat(64),
            "boot-001",
            "opaque-supervisor-token",
        )
        .expect("valid process identity")
    }

    #[test]
    fn task_happy_path_requires_lease_and_completion_evidence() {
        let mut task = TaskLifecycle::proposed();
        task.transition(TaskState::Ready, TaskTransitionEvidence::default())
            .expect("proposed to ready");
        task.transition(
            TaskState::Leased,
            TaskTransitionEvidence {
                lease: Some(lease()),
                ..TaskTransitionEvidence::default()
            },
        )
        .expect("ready to leased");
        task.transition(TaskState::Executing, TaskTransitionEvidence::default())
            .expect("leased to executing");
        task.transition(TaskState::Review, TaskTransitionEvidence::default())
            .expect("executing to review");
        task.transition(
            TaskState::Completed,
            TaskTransitionEvidence {
                completion: CompletionEvidence::verified(),
                ..TaskTransitionEvidence::default()
            },
        )
        .expect("review to completed");
        assert_eq!(task.state(), TaskState::Completed);
        assert!(task.lease().is_none());
    }

    #[test]
    fn task_rejects_missing_lease_illegal_skip_and_incomplete_review() {
        let mut task = TaskLifecycle::restore(TaskState::Ready, None).expect("valid ready state");
        assert_eq!(
            task.transition(TaskState::Leased, TaskTransitionEvidence::default()),
            Err(TaskTransitionError::LeaseRequired)
        );
        assert!(matches!(
            task.transition(TaskState::Completed, TaskTransitionEvidence::default()),
            Err(TaskTransitionError::Illegal { .. })
        ));
        let mut review =
            TaskLifecycle::restore(TaskState::Review, None).expect("valid review state");
        assert_eq!(
            review.transition(TaskState::Completed, TaskTransitionEvidence::default()),
            Err(TaskTransitionError::CompletionEvidenceRequired)
        );
    }

    #[test]
    fn expired_lease_returns_to_ready_only_when_no_effect_is_proven() {
        let mut task =
            TaskLifecycle::restore(TaskState::Leased, Some(lease())).expect("valid leased state");
        assert_eq!(
            task.transition(
                TaskState::Ready,
                TaskTransitionEvidence {
                    lease_expired: true,
                    effects: EffectKnowledge::Unknown,
                    ..TaskTransitionEvidence::default()
                }
            ),
            Err(TaskTransitionError::NoEffectProofRequired)
        );
        task.transition(
            TaskState::Ready,
            TaskTransitionEvidence {
                lease_expired: true,
                effects: EffectKnowledge::NoExternalEffect,
                ..TaskTransitionEvidence::default()
            },
        )
        .expect("proven no effect may return to ready");
        assert!(task.lease().is_none());
    }

    #[test]
    fn unknown_expired_lease_can_only_be_interrupted() {
        let mut task =
            TaskLifecycle::restore(TaskState::Leased, Some(lease())).expect("valid leased state");
        task.transition(
            TaskState::Interrupted,
            TaskTransitionEvidence {
                lease_expired: true,
                effects: EffectKnowledge::Unknown,
                ..TaskTransitionEvidence::default()
            },
        )
        .expect("unknown effect is interrupted");
        assert_eq!(task.state(), TaskState::Interrupted);
        assert!(task.lease().is_none());
    }

    #[test]
    fn restore_rejects_lease_state_mismatch() {
        assert_eq!(
            TaskLifecycle::restore(TaskState::Executing, None),
            Err(TaskTransitionError::LeaseInvariant)
        );
        assert_eq!(
            TaskLifecycle::restore(TaskState::Ready, Some(lease())),
            Err(TaskTransitionError::LeaseInvariant)
        );
    }

    #[test]
    fn running_requires_atomic_process_identity() {
        let mut run = RunLifecycle::created();
        run.transition(RunStatus::Starting, None)
            .expect("created to starting");
        assert_eq!(
            run.transition(RunStatus::Running, None),
            Err(RunTransitionError::ProcessIdentityRequired)
        );
        run.transition(RunStatus::Running, Some(process()))
            .expect("complete process identity starts run");
        assert_eq!(run.status(), RunStatus::Running);
        assert_eq!(run.process().expect("process").process_id().get(), 42);
    }

    #[test]
    fn recovered_running_process_becomes_interrupted_not_succeeded() {
        let mut run = RunLifecycle::restore(RunStatus::Running, Some(process()))
            .expect("valid running state");
        assert!(matches!(
            run.transition(RunStatus::Succeeded, None),
            Err(RunTransitionError::Illegal { .. })
        ));
        run.transition(RunStatus::Interrupted, None)
            .expect("recovery interruption");
        assert_eq!(run.status(), RunStatus::Interrupted);
    }

    #[test]
    fn process_identity_rejects_partial_or_invalid_material() {
        assert!(
            ProcessIdentity::new(
                NonZeroU32::new(1).expect("non-zero"),
                "not-utc",
                "A".repeat(64),
                "",
                "token"
            )
            .is_err()
        );
        assert!(Lease::new(ActorRef::parse("ACT-001").expect("valid actor"), "not-utc").is_err());
        assert!(
            Lease::new(
                ActorRef::parse("ACT-001").expect("valid actor"),
                "not-a-dateZ"
            )
            .is_err()
        );
    }

    #[test]
    fn state_strings_match_the_brain_vocabulary() {
        assert_eq!(TaskState::InputRequired.as_brain_str(), "INPUT_REQUIRED");
        assert_eq!(
            TaskState::ChangesRequested.as_brain_str(),
            "CHANGES_REQUESTED"
        );
        assert_eq!(RunStatus::Succeeded.as_brain_str(), "SUCCEEDED");
    }
}
