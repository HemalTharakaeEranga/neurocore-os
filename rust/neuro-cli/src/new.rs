// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

use anyhow::{Context, Result, bail};
use std::fs;
use std::path::{Component, Path, PathBuf};

const TEMPLATES_ROOT: &str = "/usr/share/neurocore/templates";
const VALID_TEMPLATES: &[&str] = &[
    "mojo-simd",
    "rust-burn",
    "rust-linfa-polars",
    "python-pytorch",
];

pub fn run(template: &str, name: &str) -> Result<()> {
    if !VALID_TEMPLATES.contains(&template) {
        bail!(
            "Unknown template '{}'. Available templates: {}",
            template,
            VALID_TEMPLATES.join(", ")
        );
    }

    validate_project_name(name)?;

    let src = locate_template(template)?;
    let dst = PathBuf::from(name);
    if dst.exists() {
        bail!("Destination '{}' already exists.", dst.display());
    }

    copy_dir_recursive(&src, &dst)
        .with_context(|| format!("Failed to scaffold '{}' into '{}'", template, dst.display()))?;

    println!(
        "Created NeuroCore '{}' project at '{}'.",
        template,
        dst.display()
    );
    Ok(())
}

/// Rejects path traversal (CWE-22), absolute paths, leading dashes, and control chars.
fn validate_project_name(name: &str) -> Result<()> {
    if name.is_empty() || name.len() > 128 {
        bail!(
            "Invalid project name '{}': must be 1..128 characters.",
            name
        );
    }
    if name.starts_with('-') {
        bail!("Invalid project name '{}': cannot begin with '-'.", name);
    }
    if name
        .chars()
        .any(|c| c.is_control() || c == '\\' || c == '/')
    {
        bail!(
            "Invalid project name '{}': use a single safe directory name without path separators.",
            name
        );
    }
    let path = Path::new(name);
    let mut comps = path.components();
    match (comps.next(), comps.next()) {
        (Some(Component::Normal(_)), None) => Ok(()),
        _ => bail!(
            "Invalid project name '{}': path traversal and rooted paths are prohibited.",
            name
        ),
    }
}

fn locate_template(template: &str) -> Result<PathBuf> {
    let installed = Path::new(TEMPLATES_ROOT).join(template);
    if installed.is_dir() {
        return Ok(installed);
    }
    let dev_path = Path::new("mkosi/mkosi.extra/usr/share/neurocore/templates").join(template);
    if dev_path.is_dir() {
        return Ok(dev_path);
    }
    bail!(
        "Template '{}' not found in {} or local checkout.",
        template,
        TEMPLATES_ROOT
    )
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let path = entry.path();
        let meta = fs::symlink_metadata(&path)?;
        if meta.file_type().is_symlink() {
            bail!(
                "Refusing to copy symlink '{}' from template directory.",
                path.display()
            );
        }
        let target = dst.join(entry.file_name());
        if meta.is_dir() {
            copy_dir_recursive(&path, &target)?;
        } else if meta.is_file() {
            fs::copy(&path, &target)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_path_traversal_and_flags() {
        assert!(validate_project_name("../escape").is_err());
        assert!(validate_project_name("/etc/evil").is_err());
        assert!(validate_project_name("-rf").is_err());
        assert!(validate_project_name("a/b").is_err());
        assert!(validate_project_name("").is_err());
        assert!(validate_project_name("my_demo-01").is_ok());
    }
}
