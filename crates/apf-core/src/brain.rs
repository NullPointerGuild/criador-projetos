use std::{
    error::Error,
    fmt,
    fmt::Write as _,
    fs, io,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

use jiff::Timestamp;
use rusqlite::{Connection, OpenFlags, params};
use sha2::{Digest, Sha256};

use crate::{BRAIN_USER_VERSION, ProjectRef};

const BRAIN_SCHEMA: &str = include_str!("../../../spec/project-brain/v1/schema.sql");
const APPLICATION_ID: u32 = 1_095_783_985;
const MIGRATION_NAME: &str = "foundation_v2";
const MIN_SQLITE_VERSION: [u32; 3] = [3, 53, 4];
static STAGING_SEQUENCE: AtomicU64 = AtomicU64::new(1);

pub const FOUNDATION_SCHEMA_SHA256: &str =
    "87625d55c5cd1fed179b21f029b5d8785839d0ebd9d883eac6af1efba65b96b3";

#[derive(Debug)]
pub enum BrainError {
    Io(io::Error),
    Sqlite(rusqlite::Error),
    PathHasNoFileName,
    PathInsideWorkspace,
    DestinationExists,
    SchemaDigestMismatch,
    InvalidProject(&'static str),
    Verification(&'static str),
}

impl fmt::Display for BrainError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(error) => write!(formatter, "Project Brain I/O failed: {error}"),
            Self::Sqlite(error) => {
                write!(formatter, "Project Brain SQLite operation failed: {error}")
            }
            Self::PathHasNoFileName => formatter.write_str("Project Brain path must name a file"),
            Self::PathInsideWorkspace => formatter
                .write_str("Project Brain and backups must remain outside the agent workspace"),
            Self::DestinationExists => {
                formatter.write_str("Project Brain creation refuses an existing destination")
            }
            Self::SchemaDigestMismatch => formatter.write_str(
                "embedded Project Brain schema changed without a migration digest update",
            ),
            Self::InvalidProject(message) => {
                write!(formatter, "invalid project initialization: {message}")
            }
            Self::Verification(message) => {
                write!(formatter, "Project Brain verification failed: {message}")
            }
        }
    }
}

impl Error for BrainError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            Self::Sqlite(error) => Some(error),
            _ => None,
        }
    }
}

impl From<io::Error> for BrainError {
    fn from(error: io::Error) -> Self {
        if error.kind() == io::ErrorKind::AlreadyExists {
            Self::DestinationExists
        } else {
            Self::Io(error)
        }
    }
}

impl From<rusqlite::Error> for BrainError {
    fn from(error: rusqlite::Error) -> Self {
        Self::Sqlite(error)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MigrationRecord {
    pub version: u32,
    pub name: String,
    pub checksum_sha256: String,
    pub applied_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BrainStatus {
    pub sqlite_version: String,
    pub user_version: u32,
    pub application_id: u32,
    pub journal_mode: String,
    pub integrity: String,
    pub foreign_key_violations: u32,
    pub fts5_enabled: bool,
    pub project_count: u32,
    pub task_count: u32,
    pub run_count: u32,
    pub event_count: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectInitialization {
    pub project_ref: ProjectRef,
    pub name: String,
    pub slug: String,
    pub root_path: PathBuf,
    pub intent_revision: u32,
    pub intent_sha256: String,
    pub purpose_primary: String,
    pub purpose_secondary: Vec<String>,
    pub mode: String,
    pub autonomy: String,
    pub occurred_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectRecord {
    pub project_ref: String,
    pub name: String,
    pub slug: String,
    pub root_path: PathBuf,
    pub intent_revision: u32,
    pub intent_sha256: String,
    pub mode: String,
    pub autonomy: String,
}

pub struct Brain {
    connection: Connection,
    path: PathBuf,
    workspace_root: PathBuf,
}

impl fmt::Debug for Brain {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("Brain")
            .field("path", &self.path)
            .field("workspace_root", &self.workspace_root)
            .finish_non_exhaustive()
    }
}

impl Brain {
    pub fn create(
        path: impl AsRef<Path>,
        workspace_root: impl AsRef<Path>,
        migration_applied_at: &str,
    ) -> Result<Self, BrainError> {
        Self::create_staged(
            path.as_ref(),
            workspace_root.as_ref(),
            migration_applied_at,
            None,
        )
    }

    pub fn create_initialized(
        path: impl AsRef<Path>,
        workspace_root: impl AsRef<Path>,
        migration_applied_at: &str,
        project: &ProjectInitialization,
    ) -> Result<Self, BrainError> {
        validate_project(project)?;
        Self::create_staged(
            path.as_ref(),
            workspace_root.as_ref(),
            migration_applied_at,
            Some(project),
        )
    }

    fn create_staged(
        path: &Path,
        workspace_root: &Path,
        migration_applied_at: &str,
        project: Option<&ProjectInitialization>,
    ) -> Result<Self, BrainError> {
        if !is_rfc3339_utc(migration_applied_at) {
            return Err(BrainError::InvalidProject("migration timestamp"));
        }
        let workspace_root = fs::canonicalize(workspace_root)?;
        let path = resolve_outside_workspace(path, &workspace_root)?;
        if path.try_exists()? {
            return Err(BrainError::DestinationExists);
        }
        let staging_path = staging_sibling(&path)?;
        let result = (|| {
            let mut brain = Self::create_unpublished(
                &staging_path,
                workspace_root.clone(),
                migration_applied_at,
            )?;
            if let Some(project) = project {
                brain.initialize_project(project)?;
            }
            brain
                .connection
                .execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
            brain.verify()?;
            drop(brain);

            fs::hard_link(&staging_path, &path)?;
            cleanup_sqlite_files(&staging_path);
            Self::open(&path, &workspace_root)
        })();
        if result.is_err() {
            cleanup_sqlite_files(&staging_path);
        }
        result
    }

    fn create_unpublished(
        path: &Path,
        workspace_root: PathBuf,
        migration_applied_at: &str,
    ) -> Result<Self, BrainError> {
        let schema_digest = sha256_hex(BRAIN_SCHEMA.as_bytes());
        if schema_digest != FOUNDATION_SCHEMA_SHA256 {
            return Err(BrainError::SchemaDigestMismatch);
        }

        fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)?;
        let connection = open_connection(path)?;
        connection.execute_batch(BRAIN_SCHEMA)?;
        connection.execute(
            "INSERT INTO schema_migrations(version,name,checksum_sha256,applied_at) VALUES(?1,?2,?3,?4)",
            params![
                BRAIN_USER_VERSION,
                MIGRATION_NAME,
                FOUNDATION_SCHEMA_SHA256,
                migration_applied_at
            ],
        )?;

        let brain = Self {
            connection,
            path: path.to_path_buf(),
            workspace_root,
        };
        brain.verify()?;
        Ok(brain)
    }

    pub fn open(
        path: impl AsRef<Path>,
        workspace_root: impl AsRef<Path>,
    ) -> Result<Self, BrainError> {
        let workspace_root = fs::canonicalize(workspace_root)?;
        let path = resolve_existing_outside_workspace(path.as_ref(), &workspace_root)?;
        let brain = Self {
            connection: open_connection(&path)?,
            path,
            workspace_root,
        };
        brain.verify()?;
        Ok(brain)
    }

    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn migration(&self) -> Result<MigrationRecord, BrainError> {
        self.connection
            .query_row(
                "SELECT version,name,checksum_sha256,applied_at FROM schema_migrations WHERE version=?1",
                [BRAIN_USER_VERSION],
                |row| {
                    Ok(MigrationRecord {
                        version: row.get(0)?,
                        name: row.get(1)?,
                        checksum_sha256: row.get(2)?,
                        applied_at: row.get(3)?,
                    })
                },
            )
            .map_err(BrainError::from)
    }

    pub fn initialize_project(
        &mut self,
        project: &ProjectInitialization,
    ) -> Result<(), BrainError> {
        validate_project(project)?;
        let purpose_secondary = serde_json::to_string(&project.purpose_secondary)
            .map_err(|_| BrainError::InvalidProject("purpose list is not serializable"))?;
        let root_path = project.root_path.to_string_lossy();
        let policy_json = serde_json::json!({
            "autonomy": project.autonomy,
            "production": "DENY",
            "financial_spending": "DENY",
            "external_communication": "DENY",
            "secrets": "DENY",
            "cloud": "DENY"
        })
        .to_string();
        let policy_sha256 = sha256_hex(policy_json.as_bytes());
        let transaction = self.connection.transaction()?;
        transaction.execute(
            "INSERT INTO projects(id,ref,name,slug,root_path,intent_revision,intent_sha256,purpose_primary,purpose_secondary_json,mode,autonomy,created_at,updated_at) VALUES(1,?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?11)",
            params![
                project.project_ref.as_str(),
                project.name,
                project.slug,
                root_path,
                project.intent_revision,
                project.intent_sha256,
                project.purpose_primary,
                purpose_secondary,
                project.mode,
                project.autonomy,
                project.occurred_at
            ],
        )?;
        transaction.execute(
            "INSERT INTO actors(project_id,ref,kind,name,capabilities_json,created_at) VALUES(1,'ACT-CORE-0001','SYSTEM','APF Core','{\"control_plane\":true}',?1)",
            [&project.occurred_at],
        )?;
        transaction.execute(
            "INSERT INTO actors(project_id,ref,kind,name,capabilities_json,created_at) VALUES(1,'ACT-HUMAN-0001','HUMAN','Local project owner','{}',?1)",
            [&project.occurred_at],
        )?;
        transaction.execute(
            "INSERT INTO policy_snapshots(project_id,ref,autonomy,content_json,sha256,ratified_by_actor_id,created_at) VALUES(1,'POL-INIT-0001',?1,?2,?3,2,?4)",
            params![project.autonomy, policy_json, policy_sha256, project.occurred_at],
        )?;
        transaction.execute(
            "INSERT INTO tasks(project_id,ref,title,objective,state,priority,acceptance_json,created_at,updated_at) VALUES(1,'TASK-INIT-0001','Initialize APF project','Create the Project Brain and bind it to the canonical project intent.','COMPLETED',100,'[\"schema verified\",\"intent digest matched\",\"Brain stored outside workspace\"]',?1,?1)",
            [&project.occurred_at],
        )?;
        transaction.execute(
            "INSERT INTO audit_events(project_id,event_id,occurred_at,actor_ref,event_type,subject_ref,data_json) VALUES(1,'EVT-INIT-0001',?1,'ACT-CORE-0001','project.initialized',?2,'{}')",
            params![project.occurred_at, project.project_ref.as_str()],
        )?;
        transaction.execute(
            "INSERT INTO audit_events(project_id,event_id,occurred_at,actor_ref,event_type,subject_ref,data_json) VALUES(1,'EVT-INIT-0002',?1,'ACT-CORE-0001','task.completed','TASK-INIT-0001','{\"outcome\":\"COMPLETED\",\"completion_evidence\":{\"acceptance\":{\"passed\":true,\"source\":\"intent and placement checks\"},\"checks\":{\"passed\":true,\"source\":\"Brain::verify\"},\"review\":{\"passed\":true,\"source\":\"deterministic bootstrap verification\"}}}')",
            [&project.occurred_at],
        )?;
        transaction.commit()?;
        Ok(())
    }

    pub fn project(&self) -> Result<ProjectRecord, BrainError> {
        self.connection
            .query_row(
                "SELECT ref,name,slug,root_path,intent_revision,intent_sha256,mode,autonomy FROM projects WHERE id=1",
                [],
                |row| {
                    Ok(ProjectRecord {
                        project_ref: row.get(0)?,
                        name: row.get(1)?,
                        slug: row.get(2)?,
                        root_path: PathBuf::from(row.get::<_, String>(3)?),
                        intent_revision: row.get(4)?,
                        intent_sha256: row.get(5)?,
                        mode: row.get(6)?,
                        autonomy: row.get(7)?,
                    })
                },
            )
            .map_err(BrainError::from)
    }

    pub fn status(&self) -> Result<BrainStatus, BrainError> {
        Ok(BrainStatus {
            sqlite_version: self.scalar("SELECT sqlite_version()")?,
            user_version: self.pragma_u32("user_version")?,
            application_id: self.pragma_u32("application_id")?,
            journal_mode: self.pragma_string("journal_mode")?,
            integrity: self.scalar("PRAGMA integrity_check")?,
            foreign_key_violations: self.scalar("SELECT count(*) FROM pragma_foreign_key_check")?,
            fts5_enabled: self.scalar::<u32>("SELECT sqlite_compileoption_used('ENABLE_FTS5')")?
                == 1,
            project_count: self.table_count("projects")?,
            task_count: self.table_count("tasks")?,
            run_count: self.table_count("runs")?,
            event_count: self.table_count("audit_events")?,
        })
    }

    pub fn backup_to(&self, path: impl AsRef<Path>) -> Result<PathBuf, BrainError> {
        let path = resolve_outside_workspace(path.as_ref(), &self.workspace_root)?;
        if path.try_exists()? {
            return Err(BrainError::DestinationExists);
        }
        let staging_path = staging_sibling(&path)?;
        let result = (|| {
            self.connection.backup(
                "main",
                &staging_path,
                None::<fn(rusqlite::backup::Progress)>,
            )?;
            let staged = Self::open(&staging_path, &self.workspace_root)?;
            staged.verify()?;
            drop(staged);
            fs::hard_link(&staging_path, &path)?;
            cleanup_sqlite_files(&staging_path);
            Ok(path)
        })();
        if result.is_err() {
            cleanup_sqlite_files(&staging_path);
        }
        result
    }

    fn verify(&self) -> Result<(), BrainError> {
        self.connection.pragma_update(None, "foreign_keys", true)?;
        self.connection
            .execute_batch("PRAGMA recursive_triggers=ON;")?;
        let status = self.status()?;
        if !sqlite_version_at_least(&status.sqlite_version, MIN_SQLITE_VERSION) {
            return Err(BrainError::Verification(
                "SQLite runtime is below the contracted minimum 3.53.4",
            ));
        }
        if status.user_version != BRAIN_USER_VERSION {
            return Err(BrainError::Verification("unexpected user_version"));
        }
        if status.application_id != APPLICATION_ID {
            return Err(BrainError::Verification("unexpected application_id"));
        }
        if status.journal_mode != "wal" {
            return Err(BrainError::Verification("WAL is not active"));
        }
        if status.integrity != "ok" || status.foreign_key_violations != 0 {
            return Err(BrainError::Verification(
                "integrity or foreign-key check failed",
            ));
        }
        if !status.fts5_enabled {
            return Err(BrainError::Verification("SQLite FTS5 support is absent"));
        }
        let migration = self.migration()?;
        if migration.name != MIGRATION_NAME || migration.checksum_sha256 != FOUNDATION_SCHEMA_SHA256
        {
            return Err(BrainError::Verification(
                "migration lineage differs from the embedded schema",
            ));
        }
        Ok(())
    }

    fn table_count(&self, table: &str) -> Result<u32, BrainError> {
        let sql = match table {
            "projects" => "SELECT count(*) FROM projects",
            "tasks" => "SELECT count(*) FROM tasks",
            "runs" => "SELECT count(*) FROM runs",
            "audit_events" => "SELECT count(*) FROM audit_events",
            _ => return Err(BrainError::Verification("unrecognized status table")),
        };
        self.scalar(sql)
    }

    fn pragma_u32(&self, name: &str) -> Result<u32, BrainError> {
        self.connection
            .pragma_query_value(None, name, |row| row.get(0))
            .map_err(BrainError::from)
    }

    fn pragma_string(&self, name: &str) -> Result<String, BrainError> {
        self.connection
            .pragma_query_value(None, name, |row| row.get(0))
            .map_err(BrainError::from)
    }

    fn scalar<T: rusqlite::types::FromSql>(&self, sql: &str) -> Result<T, BrainError> {
        self.connection
            .query_row(sql, [], |row| row.get(0))
            .map_err(BrainError::from)
    }
}

fn open_connection(path: &Path) -> Result<Connection, BrainError> {
    Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(BrainError::from)
}

fn resolve_outside_workspace(path: &Path, workspace_root: &Path) -> Result<PathBuf, BrainError> {
    let file_name = path.file_name().ok_or(BrainError::PathHasNoFileName)?;
    let parent = path.parent().ok_or(BrainError::PathHasNoFileName)?;
    let resolved = fs::canonicalize(parent)?.join(file_name);
    if resolved.starts_with(workspace_root) {
        return Err(BrainError::PathInsideWorkspace);
    }
    Ok(resolved)
}

fn resolve_existing_outside_workspace(
    path: &Path,
    workspace_root: &Path,
) -> Result<PathBuf, BrainError> {
    let resolved = fs::canonicalize(path)?;
    if resolved.starts_with(workspace_root) {
        return Err(BrainError::PathInsideWorkspace);
    }
    Ok(resolved)
}

fn staging_sibling(destination: &Path) -> Result<PathBuf, BrainError> {
    let parent = destination.parent().ok_or(BrainError::PathHasNoFileName)?;
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_nanos();
    let sequence = STAGING_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    Ok(parent.join(format!(
        ".apf-stage-{}-{timestamp}-{sequence}.db",
        std::process::id()
    )))
}

fn cleanup_sqlite_files(path: &Path) {
    for candidate in [
        path.to_path_buf(),
        PathBuf::from(format!("{}-wal", path.to_string_lossy())),
        PathBuf::from(format!("{}-shm", path.to_string_lossy())),
    ] {
        let _ = fs::remove_file(candidate);
    }
}

fn sqlite_version_at_least(value: &str, minimum: [u32; 3]) -> bool {
    let mut components = value.split('.').map(str::parse::<u32>);
    let parsed = match (components.next(), components.next(), components.next()) {
        (Some(Ok(major)), Some(Ok(minor)), Some(Ok(patch))) if components.next().is_none() => {
            [major, minor, patch]
        }
        _ => return false,
    };
    parsed >= minimum
}

fn is_rfc3339_utc(value: &str) -> bool {
    value.len() <= 64 && value.ends_with('Z') && value.parse::<Timestamp>().is_ok()
}

pub(crate) fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut output = String::with_capacity(64);
    for byte in digest {
        write!(&mut output, "{byte:02x}").expect("writing into a String is infallible");
    }
    output
}

fn validate_project(project: &ProjectInitialization) -> Result<(), BrainError> {
    for (value, label) in [
        (project.name.as_str(), "name"),
        (project.purpose_primary.as_str(), "primary purpose"),
        (project.mode.as_str(), "mode"),
        (project.occurred_at.as_str(), "timestamp"),
    ] {
        if value.is_empty() || value.len() > 512 || value.chars().any(char::is_control) {
            return Err(BrainError::InvalidProject(label));
        }
    }
    let valid_slug = !project.slug.is_empty()
        && project.slug.len() <= 80
        && !project.slug.starts_with('-')
        && !project.slug.ends_with('-')
        && project
            .slug
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-');
    if !valid_slug {
        return Err(BrainError::InvalidProject("slug"));
    }
    if project.intent_revision == 0
        || project.intent_sha256.len() != 64
        || !project
            .intent_sha256
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(BrainError::InvalidProject("intent revision or digest"));
    }
    if !matches!(project.autonomy.as_str(), "CONTROLLED" | "SHARED") {
        return Err(BrainError::InvalidProject("autonomy"));
    }
    if !is_rfc3339_utc(&project.occurred_at) {
        return Err(BrainError::InvalidProject("timestamp"));
    }
    if !project.root_path.is_absolute() {
        return Err(BrainError::InvalidProject("root path"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{
        sync::atomic::{AtomicU64, Ordering},
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::*;

    const BRAIN_SEED: &str = include_str!("../../../spec/project-brain/v1/seed.sql");
    static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(1);

    struct TempRoot(PathBuf);

    impl TempRoot {
        fn new() -> Self {
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system time after epoch")
                .as_nanos();
            let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let root = std::env::temp_dir().join(format!(
                "apf-brain-test-{}-{timestamp}-{sequence}",
                std::process::id()
            ));
            fs::create_dir(&root).expect("create isolated test directory");
            Self(root)
        }

        fn join(&self, name: &str) -> PathBuf {
            self.0.join(name)
        }
    }

    impl Drop for TempRoot {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn workspace_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .canonicalize()
            .expect("workspace root")
    }

    fn create_brain(temp: &TempRoot) -> Brain {
        Brain::create(
            temp.join("brain.db"),
            workspace_root(),
            "2026-08-31T16:00:00Z",
        )
        .expect("create Project Brain")
    }

    #[test]
    fn bootstrap_records_schema_lineage_and_runtime_capabilities() {
        let temp = TempRoot::new();
        let brain = create_brain(&temp);
        let migration = brain.migration().expect("migration record");
        assert_eq!(migration.version, BRAIN_USER_VERSION);
        assert_eq!(migration.name, MIGRATION_NAME);
        assert_eq!(migration.checksum_sha256, FOUNDATION_SCHEMA_SHA256);

        let status = brain.status().expect("brain status");
        assert_eq!(status.sqlite_version, "3.53.4");
        assert_eq!(status.user_version, BRAIN_USER_VERSION);
        assert_eq!(status.application_id, APPLICATION_ID);
        assert_eq!(status.journal_mode, "wal");
        assert_eq!(status.integrity, "ok");
        assert_eq!(status.foreign_key_violations, 0);
        assert!(status.fts5_enabled);
        assert_eq!(status.project_count, 0);
    }

    #[test]
    fn foundation_seed_and_immutable_audit_hold_in_the_runtime() {
        let temp = TempRoot::new();
        let brain = create_brain(&temp);
        brain
            .connection
            .execute_batch(BRAIN_SEED)
            .expect("apply foundation fixture seed");

        let status = brain.status().expect("seeded status");
        assert_eq!(status.project_count, 1);
        assert_eq!(status.task_count, 1);
        assert_eq!(status.run_count, 1);
        assert_eq!(status.event_count, 3);
        let decision: String = brain
            .connection
            .query_row(
                "SELECT entity_ref FROM brain_fts WHERE brain_fts MATCH 'deterministic'",
                [],
                |row| row.get(0),
            )
            .expect("FTS decision");
        assert_eq!(decision, "DEC-0001");
        let mutation = brain.connection.execute(
            "UPDATE audit_events SET event_type='tampered' WHERE event_id='EVT-0001'",
            [],
        );
        assert!(mutation.is_err());
    }

    #[test]
    fn backup_restores_seeded_brain_without_crossing_the_workspace() {
        let temp = TempRoot::new();
        let brain = create_brain(&temp);
        brain
            .connection
            .execute_batch(BRAIN_SEED)
            .expect("apply foundation fixture seed");
        let backup_path = brain
            .backup_to(temp.join("brain-backup.db"))
            .expect("backup");
        drop(brain);

        let restored = Brain::open(backup_path, workspace_root()).expect("open restored backup");
        let status = restored.status().expect("restored status");
        assert_eq!(status.integrity, "ok");
        assert_eq!(status.project_count, 1);
        assert_eq!(status.event_count, 3);
    }

    #[test]
    fn creation_refuses_the_agent_workspace_and_existing_destinations() {
        let workspace = workspace_root();
        let forbidden = workspace.join("brain-must-not-exist.db");
        assert!(matches!(
            Brain::create(&forbidden, &workspace, "2026-08-31T16:00:00Z"),
            Err(BrainError::PathInsideWorkspace)
        ));
        assert!(!forbidden.exists());

        let temp = TempRoot::new();
        let path = temp.join("brain.db");
        drop(Brain::create(&path, &workspace, "2026-08-31T16:00:00Z").expect("first creation"));
        assert!(matches!(
            Brain::create(&path, &workspace, "2026-08-31T16:01:00Z"),
            Err(BrainError::DestinationExists)
        ));
    }

    #[test]
    fn initialized_creation_publishes_only_a_complete_brain() {
        let temp = TempRoot::new();
        let workspace = workspace_root();
        let path = temp.join("initialized.db");
        let project = ProjectInitialization {
            project_ref: ProjectRef::parse("PRJ-ATOMIC-0001").expect("project ref"),
            name: "Atomic Project".to_owned(),
            slug: "atomic-project".to_owned(),
            root_path: workspace.clone(),
            intent_revision: 1,
            intent_sha256: "a".repeat(64),
            purpose_primary: "test atomic publication".to_owned(),
            purpose_secondary: Vec::new(),
            mode: "experiment".to_owned(),
            autonomy: "CONTROLLED".to_owned(),
            occurred_at: "2026-08-31T16:00:00Z".to_owned(),
        };
        let brain = Brain::create_initialized(&path, &workspace, "2026-08-31T16:00:00Z", &project)
            .expect("publish initialized Brain");
        let status = brain.status().expect("status");
        assert_eq!(status.project_count, 1);
        assert_eq!(status.task_count, 1);
        assert_eq!(status.event_count, 2);
        let completion: String = brain
            .connection
            .query_row(
                "SELECT data_json FROM audit_events WHERE event_id='EVT-INIT-0002'",
                [],
                |row| row.get(0),
            )
            .expect("completion evidence");
        assert!(completion.contains("completion_evidence"));
        assert!(!temp.0.read_dir().expect("list temp root").any(|entry| {
            entry
                .expect("directory entry")
                .file_name()
                .to_string_lossy()
                .starts_with(".apf-stage-")
        }));
    }

    #[test]
    fn invalid_project_and_timestamp_leave_no_destination() {
        let temp = TempRoot::new();
        let workspace = workspace_root();
        let path = temp.join("must-not-exist.db");
        let invalid = ProjectInitialization {
            project_ref: ProjectRef::parse("PRJ-INVALID-0001").expect("project ref"),
            name: "Invalid Project".to_owned(),
            slug: "../escape".to_owned(),
            root_path: workspace.clone(),
            intent_revision: 1,
            intent_sha256: "a".repeat(64),
            purpose_primary: "negative test".to_owned(),
            purpose_secondary: Vec::new(),
            mode: "experiment".to_owned(),
            autonomy: "CONTROLLED".to_owned(),
            occurred_at: "not-a-dateZ".to_owned(),
        };
        assert!(
            Brain::create_initialized(&path, &workspace, "2026-08-31T16:00:00Z", &invalid,)
                .is_err()
        );
        assert!(!path.exists());
        assert!(Brain::create(&path, &workspace, "not-a-dateZ").is_err());
        assert!(!path.exists());
    }

    #[test]
    fn sqlite_version_comparison_enforces_the_contract_floor() {
        assert!(!sqlite_version_at_least("3.53.2", MIN_SQLITE_VERSION));
        assert!(sqlite_version_at_least("3.53.4", MIN_SQLITE_VERSION));
        assert!(sqlite_version_at_least("3.54.0", MIN_SQLITE_VERSION));
        assert!(!sqlite_version_at_least(
            "not-a-version",
            MIN_SQLITE_VERSION
        ));
    }
}
