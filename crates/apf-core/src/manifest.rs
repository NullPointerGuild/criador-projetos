use std::{
    error::Error,
    fmt, fs, io,
    path::{Path, PathBuf},
};

use serde::Deserialize;

use crate::{ProjectInitialization, ProjectRef, RefError, brain::sha256_hex};

const MANIFEST_MAX_BYTES: u64 = 64 * 1024;
const INTENT_MAX_BYTES: u64 = 1024 * 1024;

#[derive(Debug)]
pub enum ManifestError {
    Io(io::Error),
    Yaml(serde_yaml_ng::Error),
    Reference(RefError),
    TooLarge(&'static str),
    Invalid(&'static str),
}

impl fmt::Display for ManifestError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(error) => write!(formatter, "project manifest I/O failed: {error}"),
            Self::Yaml(error) => write!(formatter, "project manifest YAML is invalid: {error}"),
            Self::Reference(error) => {
                write!(formatter, "project manifest reference is invalid: {error}")
            }
            Self::TooLarge(label) => write!(formatter, "{label} exceeds the bounded input size"),
            Self::Invalid(message) => write!(formatter, "project manifest is invalid: {message}"),
        }
    }
}

impl Error for ManifestError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            Self::Yaml(error) => Some(error),
            Self::Reference(error) => Some(error),
            Self::TooLarge(_) | Self::Invalid(_) => None,
        }
    }
}

impl From<io::Error> for ManifestError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

impl From<serde_yaml_ng::Error> for ManifestError {
    fn from(error: serde_yaml_ng::Error) -> Self {
        Self::Yaml(error)
    }
}

impl From<RefError> for ManifestError {
    fn from(error: RefError) -> Self {
        Self::Reference(error)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoadedProjectManifest {
    pub workspace_root: PathBuf,
    pub project_ref: ProjectRef,
    pub name: String,
    pub slug: String,
    pub intent_revision: u32,
    pub recorded_intent_sha256: String,
    pub actual_intent_sha256: String,
    pub purpose_primary: String,
    pub purpose_secondary: Vec<String>,
    pub mode: String,
    pub autonomy: String,
}

impl LoadedProjectManifest {
    pub fn load(workspace_root: impl AsRef<Path>) -> Result<Self, ManifestError> {
        let workspace_root = fs::canonicalize(workspace_root)?;
        let manifest_path = workspace_root.join(".apf").join("project.yaml");
        let manifest_bytes = read_bounded(&manifest_path, MANIFEST_MAX_BYTES, "project.yaml")?;
        let raw: RawManifest = serde_yaml_ng::from_slice(&manifest_bytes)?;
        if raw.schema_version != 1 {
            return Err(ManifestError::Invalid("schema_version must be 1"));
        }
        if raw.intent.source != "../PROJECT.md" {
            return Err(ManifestError::Invalid(
                "intent source must be the workspace-root PROJECT.md",
            ));
        }
        if raw.intent.divergence_policy != "fail_on_semantic_difference" {
            return Err(ManifestError::Invalid("unsupported divergence policy"));
        }
        let intent_path = workspace_root.join("PROJECT.md");
        let intent_bytes = read_bounded(&intent_path, INTENT_MAX_BYTES, "PROJECT.md")?;
        let actual_intent_sha256 = sha256_hex(&intent_bytes);
        validate_sha256(&raw.intent.source_sha256)?;
        if raw.intent.revision == 0 {
            return Err(ManifestError::Invalid("intent revision must be positive"));
        }
        if !matches!(raw.autonomy.preset.as_str(), "CONTROLLED" | "SHARED") {
            return Err(ManifestError::Invalid(
                "autonomy must be CONTROLLED or SHARED",
            ));
        }
        let slug = raw.name.to_ascii_lowercase();
        if !valid_slug(&slug) {
            return Err(ManifestError::Invalid(
                "name must be a bounded slug containing only ASCII letters, digits and internal hyphens",
            ));
        }
        validate_text(&raw.display_name, 512, "display_name")?;
        validate_text(&raw.purpose.primary, 512, "primary purpose")?;
        validate_text(&raw.mode, 64, "mode")?;
        if raw.purpose.secondary.len() > 32 {
            return Err(ManifestError::Invalid(
                "purpose.secondary may contain at most 32 entries",
            ));
        }
        for purpose in &raw.purpose.secondary {
            validate_text(purpose, 512, "secondary purpose")?;
        }

        Ok(Self {
            workspace_root,
            project_ref: ProjectRef::parse(raw.project_id)?,
            name: raw.display_name,
            slug,
            intent_revision: raw.intent.revision,
            recorded_intent_sha256: raw.intent.source_sha256,
            actual_intent_sha256,
            purpose_primary: raw.purpose.primary,
            purpose_secondary: raw.purpose.secondary,
            mode: raw.mode,
            autonomy: raw.autonomy.preset,
        })
    }

    #[must_use]
    pub fn intent_matches(&self) -> bool {
        self.recorded_intent_sha256 == self.actual_intent_sha256
    }

    #[must_use]
    pub fn project_initialization(&self, occurred_at: impl Into<String>) -> ProjectInitialization {
        ProjectInitialization {
            project_ref: self.project_ref.clone(),
            name: self.name.clone(),
            slug: self.slug.clone(),
            root_path: self.workspace_root.clone(),
            intent_revision: self.intent_revision,
            intent_sha256: self.actual_intent_sha256.clone(),
            purpose_primary: self.purpose_primary.clone(),
            purpose_secondary: self.purpose_secondary.clone(),
            mode: self.mode.clone(),
            autonomy: self.autonomy.clone(),
            occurred_at: occurred_at.into(),
        }
    }
}

#[derive(Debug, Deserialize)]
struct RawManifest {
    schema_version: u32,
    project_id: String,
    name: String,
    display_name: String,
    intent: RawIntent,
    purpose: RawPurpose,
    mode: String,
    autonomy: RawAutonomy,
}

#[derive(Debug, Deserialize)]
struct RawIntent {
    source: String,
    revision: u32,
    source_sha256: String,
    divergence_policy: String,
}

#[derive(Debug, Deserialize)]
struct RawPurpose {
    primary: String,
    secondary: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct RawAutonomy {
    preset: String,
}

fn read_bounded(
    path: &Path,
    max_bytes: u64,
    label: &'static str,
) -> Result<Vec<u8>, ManifestError> {
    let metadata = fs::metadata(path)?;
    if metadata.len() > max_bytes {
        return Err(ManifestError::TooLarge(label));
    }
    fs::read(path).map_err(ManifestError::from)
}

fn validate_sha256(value: &str) -> Result<(), ManifestError> {
    if value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        Ok(())
    } else {
        Err(ManifestError::Invalid("intent SHA-256 is malformed"))
    }
}

fn valid_slug(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 80
        && !value.starts_with('-')
        && !value.ends_with('-')
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
}

fn validate_text(value: &str, max_bytes: usize, label: &'static str) -> Result<(), ManifestError> {
    if value.is_empty() || value.len() > max_bytes || value.chars().any(char::is_control) {
        Err(ManifestError::Invalid(label))
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use std::{
        sync::atomic::{AtomicU64, Ordering},
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::*;

    static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(1);

    struct TempWorkspace(PathBuf);

    impl TempWorkspace {
        fn new(intent: &str) -> Self {
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system time after epoch")
                .as_nanos();
            let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let root = std::env::temp_dir().join(format!(
                "apf-manifest-test-{}-{timestamp}-{sequence}",
                std::process::id()
            ));
            fs::create_dir(&root).expect("create workspace");
            fs::create_dir(root.join(".apf")).expect("create descriptor directory");
            fs::write(root.join("PROJECT.md"), intent).expect("write intent");
            let digest = sha256_hex(intent.as_bytes());
            let yaml = format!(
                "schema_version: 1\nproject_id: PRJ-TEST-0001\nname: test-project\ndisplay_name: Test Project\nintent:\n  source: ../PROJECT.md\n  revision: 1\n  source_sha256: {digest}\n  divergence_policy: fail_on_semantic_difference\npurpose:\n  primary: personal\n  secondary:\n    - experiment\nmode: experiment\nautonomy:\n  preset: CONTROLLED\n"
            );
            fs::write(root.join(".apf").join("project.yaml"), yaml).expect("write manifest");
            Self(root)
        }
    }

    impl Drop for TempWorkspace {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn loads_the_repository_manifest_and_matches_intent() {
        let workspace = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let manifest = LoadedProjectManifest::load(workspace).expect("load APF manifest");
        assert_eq!(manifest.project_ref.as_str(), "PRJ-APF-0001");
        assert!(manifest.intent_matches());
    }

    #[test]
    fn divergence_is_observed_without_being_silently_accepted() {
        let workspace = TempWorkspace::new("canonical intent");
        let matching = LoadedProjectManifest::load(&workspace.0).expect("matching manifest");
        assert!(matching.intent_matches());
        fs::write(workspace.0.join("PROJECT.md"), "changed intent").expect("change test intent");
        let diverged = LoadedProjectManifest::load(&workspace.0).expect("diverged manifest");
        assert!(!diverged.intent_matches());
        assert_ne!(
            diverged.recorded_intent_sha256,
            diverged.actual_intent_sha256
        );
    }

    #[test]
    fn rejects_manifest_name_before_it_can_become_a_path() {
        for hostile_name in ["..", "../escape", "C:/escape", "has\\separator", "-edge"] {
            let workspace = TempWorkspace::new("canonical intent");
            let manifest_path = workspace.0.join(".apf").join("project.yaml");
            let yaml = fs::read_to_string(&manifest_path).expect("read manifest");
            let hostile = yaml.replacen("name: test-project", &format!("name: {hostile_name}"), 1);
            fs::write(&manifest_path, hostile).expect("write hostile manifest");
            assert!(matches!(
                LoadedProjectManifest::load(&workspace.0),
                Err(ManifestError::Invalid(_))
            ));
        }
    }
}
