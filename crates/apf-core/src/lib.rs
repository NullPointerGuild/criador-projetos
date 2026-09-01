//! Deterministic APF control-plane primitives.

mod brain;
mod lifecycle;
mod manifest;
mod refs;

pub use brain::{
    Brain, BrainError, BrainStatus, FOUNDATION_SCHEMA_SHA256, MigrationRecord,
    ProjectInitialization, ProjectRecord,
};
pub use lifecycle::{
    CompletionEvidence, EffectKnowledge, Lease, LeaseError, ProcessIdentity, ProcessIdentityError,
    RunLifecycle, RunStatus, RunTransitionError, TaskLifecycle, TaskState, TaskTransitionError,
    TaskTransitionEvidence,
};
pub use manifest::{LoadedProjectManifest, ManifestError};
pub use refs::{ActorRef, EventRef, ProjectRef, RefError, RunRef, TaskRef, WorkOrderRef};

/// The current Project Brain schema version.
pub const BRAIN_USER_VERSION: u32 = 2;
