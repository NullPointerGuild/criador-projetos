use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

use apf_core::Brain;

static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(1);

struct Fixture {
    root: PathBuf,
    workspace: PathBuf,
    brain: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time after epoch")
            .as_nanos();
        let sequence = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let root = std::env::temp_dir().join(format!(
            "apf-cli-test-{}-{timestamp}-{sequence}",
            std::process::id()
        ));
        let workspace = root.join("workspace");
        let state = root.join("state");
        fs::create_dir_all(workspace.join(".apf")).expect("create test workspace");
        fs::create_dir(&state).expect("create test state directory");
        let repository = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        fs::copy(repository.join("PROJECT.md"), workspace.join("PROJECT.md"))
            .expect("copy canonical intent");
        fs::copy(
            repository.join(".apf").join("project.yaml"),
            workspace.join(".apf").join("project.yaml"),
        )
        .expect("copy project manifest");
        Self {
            brain: state.join("brain.db"),
            root,
            workspace,
        }
    }

    fn command(&self, command: &str) -> Output {
        self.command_with_brain(command, &self.brain)
    }

    fn command_with_brain(&self, command: &str, brain: &Path) -> Output {
        Command::new(env!("CARGO_BIN_EXE_apf"))
            .arg(command)
            .arg("--workspace")
            .arg(&self.workspace)
            .arg("--brain")
            .arg(brain)
            .output()
            .expect("run APF CLI")
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).expect("UTF-8 stdout")
}

fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).expect("UTF-8 stderr")
}

#[test]
fn init_status_restart_and_intent_divergence_are_deterministic() {
    let fixture = Fixture::new();
    let initialized = fixture.command("init");
    assert!(initialized.status.success(), "{}", stderr(&initialized));
    assert!(stdout(&initialized).contains("intent=MATCH"));
    assert!(stdout(&initialized).contains("tasks=1"));
    assert!(stdout(&initialized).contains("events=2"));

    let brain = Brain::open(&fixture.brain, &fixture.workspace).expect("open initialized Brain");
    let brain_status = brain.status().expect("Brain status");
    assert_eq!(brain_status.project_count, 1);
    assert_eq!(brain_status.task_count, 1);
    assert_eq!(brain_status.event_count, 2);
    drop(brain);

    let restarted = fixture.command("status");
    assert!(restarted.status.success(), "{}", stderr(&restarted));
    assert!(stdout(&restarted).contains("intent=MATCH"));
    assert!(stdout(&restarted).contains("binding=MATCH"));
    assert!(stdout(&restarted).contains("integrity=ok"));

    let mut intent = fs::read_to_string(fixture.workspace.join("PROJECT.md")).expect("read intent");
    intent.push_str("\nmaterial divergence\n");
    fs::write(fixture.workspace.join("PROJECT.md"), intent).expect("write divergent intent");
    let diverged = fixture.command("status");
    assert_eq!(diverged.status.code(), Some(2), "{}", stderr(&diverged));
    assert!(stdout(&diverged).contains("intent=DIVERGED"));
}

#[test]
fn status_rejects_a_brain_bound_to_another_project() {
    let owner = Fixture::new();
    let initialized = owner.command("init");
    assert!(initialized.status.success(), "{}", stderr(&initialized));

    let other = Fixture::new();
    let manifest_path = other.workspace.join(".apf").join("project.yaml");
    let manifest = fs::read_to_string(&manifest_path).expect("read other manifest");
    let manifest = manifest.replacen("PRJ-APF-0001", "PRJ-OTHER-0001", 1);
    fs::write(&manifest_path, manifest).expect("write distinct project identity");

    let status = other.command_with_brain("status", &owner.brain);
    assert_eq!(status.status.code(), Some(2), "{}", stderr(&status));
    assert!(stdout(&status).contains("binding=DIVERGED"));
    assert!(!stdout(&status).contains("tasks="));
}

#[test]
fn hostile_manifest_name_is_rejected_before_brain_creation() {
    let fixture = Fixture::new();
    let manifest_path = fixture.workspace.join(".apf").join("project.yaml");
    let manifest = fs::read_to_string(&manifest_path).expect("read manifest");
    let hostile = manifest.replacen("name: APF", "name: ../escape", 1);
    fs::write(&manifest_path, hostile).expect("write hostile manifest");

    let initialized = fixture.command("init");
    assert!(!initialized.status.success());
    assert!(!fixture.brain.exists());
}

#[test]
fn doctor_reports_the_gate_without_creating_default_state() {
    let fixture = Fixture::new();
    let local_app_data = fixture.root.join("doctor-local-app-data");
    let output = Command::new(env!("CARGO_BIN_EXE_apf"))
        .arg("doctor")
        .arg("--workspace")
        .arg(&fixture.workspace)
        .env("LOCALAPPDATA", &local_app_data)
        .output()
        .expect("run doctor");

    assert!(output.status.success(), "{}", stderr(&output));
    assert!(stdout(&output).contains("provider_runtime=DISABLED_BY_T0.8A"));
    assert!(stdout(&output).contains("provider_writes=DENY"));
    assert!(!local_app_data.exists());
}
