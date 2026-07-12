# CEUS rev513a automated session bootstrap

## One-time repository setup

Commit these files to `jstefanis/ceus-offline-environments`:

```text
.github/workflows/build_rev513a_session_bootstrap.yml
session_bootstrap/bootstrap_ceus_envs.sh
session_bootstrap/verify_ceus_envs.py
session_bootstrap/README_SESSION_BOOTSTRAP.md
```

Run **Build CEUS rev513a session bootstrap** once from the Actions tab.

The workflow will:

1. Download the 12 authored release assets.
2. Verify declared SHA-256 values.
3. Verify all four ZIP files.
4. Publish an Actions artifact named `ceus-rev513a-session-bootstrap`.
5. Commit `session_bootstrap/LATEST_SESSION_BOOTSTRAP.json` with the current run ID.

## How a new ChatGPT session restores the environment

Tell ChatGPT:

```text
Restore the CEUS rev513a environments from
jstefanis/ceus-offline-environments using
session_bootstrap/LATEST_SESSION_BOOTSTRAP.json.
Download the named workflow artifact, run bootstrap_ceus_envs.sh,
and verify both PyQt5 and PySide6 environments.
```

The GitHub connector can then:

1. Read `session_bootstrap/LATEST_SESSION_BOOTSTRAP.json`.
2. Call `fetch_workflow_run_artifacts` using its `run_id`.
3. Download the matching artifact.
4. Extract it into the session.
5. Run:

```bash
bash bootstrap_ceus_envs.sh /mnt/data/ceus_envs_rev513a <artifact-extraction-root>
```

## Resulting activation commands

```bash
source /mnt/data/ceus_envs_rev513a/activate_pyqt5.sh
source /mnt/data/ceus_envs_rev513a/activate_pyside6.sh
```

The environments are always separate. `pyqtspinner` is rejected in both. PyQt5 is rejected from the PySide6 environment, and PySide6/Shiboken6 are rejected from the PyQt5 environment.
