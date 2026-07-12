# CEUS rev513a automated session bootstrap

Revision: `rev513a_env_bootstrap_runtime_r2_cdx_cl`

## Repository files

Use these canonical paths:

```text
.github/workflows/build_rev513a_session_bootstrap.yml
.github/workflows/rev513a_fetch_release_assets.yml
session_bootstrap/bootstrap_ceus_envs.sh
session_bootstrap/verify_ceus_envs.py
session_bootstrap/README_SESSION_BOOTSTRAP.md
```

Delete obsolete duplicate workflow files after the canonical workflow is updated.

## Release assets

The release must include five ZIP archives, five ZIP checksum sidecars, the release checksum manifest, and the three manifest documents. The CPython runtime remains a separate artifact so every Actions artifact stays below the connector download limit.

## Deterministic restore behavior

The bootstrap:

1. Resolves all five ZIP archives and sidecars.
2. Verifies every archive before extraction.
3. Clears prior staging and venv directories.
4. Extracts common, PyQt5, PySide6, system, and runtime content into separate roots.
5. Verifies internal wheelhouse manifests.
6. Rejects binding cross-contamination and `pyqtspinner`.
7. Builds isolated PyQt5 and PySide6 CPython 3.11 venvs.
8. Runs `pip check`, Qt offscreen, pyqtgraph, Matplotlib QtAgg, pydicom decoder, WeasyPrint, and pikepdf smoke tests.

Run:

```bash
bash bootstrap_ceus_envs.sh /mnt/data/ceus_envs_rev513a <artifact-extraction-root>
```

Activation:

```bash
source /mnt/data/ceus_envs_rev513a/activate_pyqt5.sh
source /mnt/data/ceus_envs_rev513a/activate_pyside6.sh
```

The Ubuntu 24.04 `.deb` bundle is preserved as an offline system-dependency artifact. The bootstrap does not install those packages automatically onto a non-Ubuntu host.
