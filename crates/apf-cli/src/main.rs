use std::{
    env,
    ffi::OsString,
    fs,
    path::{Path, PathBuf},
    process::ExitCode,
};

use apf_core::{Brain, LoadedProjectManifest};
use jiff::Timestamp;

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("error: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<u8, String> {
    let mut arguments = env::args_os();
    let _program = arguments.next();
    let command = arguments
        .next()
        .and_then(|value| value.into_string().ok())
        .ok_or_else(usage)?;
    let options = Options::parse(arguments.collect())?;
    match command.as_str() {
        "init" => init(&options),
        "status" => status(&options),
        "doctor" => doctor(&options),
        "--help" | "-h" | "help" => {
            println!("{}", usage());
            Ok(0)
        }
        _ => Err(format!("unknown command {command:?}\n{}", usage())),
    }
}

#[derive(Debug)]
struct Options {
    workspace: PathBuf,
    brain: Option<PathBuf>,
}

impl Options {
    fn parse(arguments: Vec<OsString>) -> Result<Self, String> {
        let mut workspace = None;
        let mut brain = None;
        let mut index = 0;
        while index < arguments.len() {
            let option = arguments[index]
                .to_str()
                .ok_or_else(|| "option names must be valid UTF-8".to_owned())?;
            let target = match option {
                "--workspace" => &mut workspace,
                "--brain" => &mut brain,
                _ => return Err(format!("unknown option {option:?}")),
            };
            index += 1;
            let value = arguments
                .get(index)
                .ok_or_else(|| format!("{option} requires a path"))?;
            if target.is_some() {
                return Err(format!("{option} may only be provided once"));
            }
            *target = Some(PathBuf::from(value));
            index += 1;
        }
        let workspace = workspace
            .map_or_else(env::current_dir, Ok)
            .map_err(|error| format!("cannot determine workspace: {error}"))?;
        Ok(Self { workspace, brain })
    }

    fn brain_path(
        &self,
        manifest: &LoadedProjectManifest,
        create_default_parent: bool,
    ) -> Result<PathBuf, String> {
        if let Some(path) = &self.brain {
            if !path.is_absolute() {
                return Err("--brain must be an absolute path outside the workspace".to_owned());
            }
            let parent = path
                .parent()
                .ok_or_else(|| "--brain must have an existing parent directory".to_owned())?;
            if !parent.is_dir() {
                return Err("--brain parent directory does not exist".to_owned());
            }
            return Ok(path.clone());
        }

        let local_app_data = env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .ok_or_else(|| "LOCALAPPDATA is unavailable; pass --brain explicitly".to_owned())?;
        let parent = local_app_data.join("APF").join("projects").join(format!(
            "{}--{}",
            manifest.slug,
            manifest.project_ref.as_str().to_ascii_lowercase()
        ));
        if create_default_parent {
            fs::create_dir_all(&parent)
                .map_err(|error| format!("cannot create the APF data directory: {error}"))?;
        }
        Ok(parent.join("brain.db"))
    }
}

fn init(options: &Options) -> Result<u8, String> {
    let manifest = load_manifest(options)?;
    if !manifest.intent_matches() {
        return Err(format!(
            "PROJECT.md diverges from .apf/project.yaml (recorded={}, actual={})",
            manifest.recorded_intent_sha256, manifest.actual_intent_sha256
        ));
    }
    let brain_path = options.brain_path(&manifest, true)?;
    let occurred_at = Timestamp::now().to_string();
    let brain = Brain::create_initialized(
        &brain_path,
        &manifest.workspace_root,
        &occurred_at,
        &manifest.project_initialization(&occurred_at),
    )
    .map_err(|error| error.to_string())?;
    let status = brain.status().map_err(|error| error.to_string())?;
    println!("command=init");
    println!("project={}", manifest.project_ref);
    println!("brain={}", display_path(brain.path()));
    println!("intent=MATCH");
    println!("brain_user_version={}", status.user_version);
    println!("tasks={}", status.task_count);
    println!("events={}", status.event_count);
    Ok(0)
}

fn status(options: &Options) -> Result<u8, String> {
    let manifest = load_manifest(options)?;
    let brain_path = options.brain_path(&manifest, false)?;
    let brain =
        Brain::open(&brain_path, &manifest.workspace_root).map_err(|error| error.to_string())?;
    let project = brain.project().map_err(|error| error.to_string())?;
    let binding_matches = project.project_ref == manifest.project_ref.as_str()
        && project.name == manifest.name
        && project.slug == manifest.slug
        && project.root_path == manifest.workspace_root;
    if !binding_matches {
        println!("command=status");
        println!("project={}", manifest.project_ref);
        println!("brain={}", display_path(brain.path()));
        println!("binding=DIVERGED");
        return Ok(2);
    }
    let intent_matches = manifest.intent_matches()
        && project.intent_sha256 == manifest.actual_intent_sha256
        && project.intent_revision == manifest.intent_revision;
    let status = brain.status().map_err(|error| error.to_string())?;
    println!("command=status");
    println!("project={}", project.project_ref);
    println!("brain={}", display_path(brain.path()));
    println!("binding=MATCH");
    println!(
        "intent={}",
        if intent_matches { "MATCH" } else { "DIVERGED" }
    );
    println!("brain_user_version={}", status.user_version);
    println!("sqlite={}", status.sqlite_version);
    println!("integrity={}", status.integrity);
    println!("tasks={}", status.task_count);
    println!("runs={}", status.run_count);
    println!("events={}", status.event_count);
    Ok(if intent_matches { 0 } else { 2 })
}

fn doctor(options: &Options) -> Result<u8, String> {
    let manifest = load_manifest(options)?;
    let brain_path = options.brain_path(&manifest, false)?;
    println!("command=doctor");
    println!("platform=windows-x64");
    println!("workspace={}", display_path(&manifest.workspace_root));
    println!("manifest=VALID");
    println!(
        "intent={}",
        if manifest.intent_matches() {
            "MATCH"
        } else {
            "DIVERGED"
        }
    );
    println!("brain={}", display_path(&brain_path));
    println!(
        "brain_state={}",
        if brain_path.is_file() {
            "PRESENT"
        } else {
            "ABSENT"
        }
    );
    println!("provider_runtime=DISABLED_BY_T0.8A");
    println!("provider_writes=DENY");
    println!("doctor_scope=DETERMINISTIC_SLICE1_ONLY");
    Ok(if manifest.intent_matches() { 0 } else { 2 })
}

fn load_manifest(options: &Options) -> Result<LoadedProjectManifest, String> {
    LoadedProjectManifest::load(&options.workspace).map_err(|error| error.to_string())
}

fn display_path(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn usage() -> String {
    "usage: apf <init|doctor|status> [--workspace PATH] [--brain ABSOLUTE_PATH]".to_owned()
}
