#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/data/ceus_envs_rev513a}"
PAYLOAD_ROOT="${2:-$(pwd)}"

COMMON_ZIP="$(find "$PAYLOAD_ROOT" -type f -name 'ceus_python311_common_offline_rev513a_r1_cdx_cl.zip' -print -quit)"
PYQT5_ZIP="$(find "$PAYLOAD_ROOT" -type f -name 'ceus_pyqt5_binding_offline_rev513a_r1_cdx_cl.zip' -print -quit)"
PYSIDE6_ZIP="$(find "$PAYLOAD_ROOT" -type f -name 'ceus_pyside6_binding_offline_rev513a_r1_cdx_cl.zip' -print -quit)"
SYSTEM_ZIP="$(find "$PAYLOAD_ROOT" -type f -name 'ceus_system_deps_ubuntu2404_offline_rev513a_r1_cdx_cl.zip' -print -quit)"

for item in "$COMMON_ZIP" "$PYQT5_ZIP" "$PYSIDE6_ZIP" "$SYSTEM_ZIP"; do
	if [[ -z "$item" || ! -f "$item" ]]; then
		echo "ERROR: required archive missing under $PAYLOAD_ROOT" >&2
		exit 2
	fi
done

mkdir -p "$ROOT"/{archives,expanded,venvs,tools,logs}
cp -f "$COMMON_ZIP" "$PYQT5_ZIP" "$PYSIDE6_ZIP" "$SYSTEM_ZIP" "$ROOT/archives/"

for archive in "$ROOT"/archives/*.zip; do
	unzip -q -o "$archive" -d "$ROOT/expanded/$(basename "$archive" .zip)"
done

PYTHON_BIN="$(
	find "$ROOT/expanded" -type f \( -path '*/bin/python3.11' -o -path '*/bin/python3' \) -perm -u+x \
		-print | head -n 1
)"

if [[ -z "$PYTHON_BIN" ]]; then
	echo "ERROR: no executable CPython 3.11 runtime found in common archive." >&2
	exit 3
fi

PY_VERSION="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "$PY_VERSION" != "3.11" ]]; then
	echo "ERROR: expected Python 3.11, got $PY_VERSION from $PYTHON_BIN" >&2
	exit 4
fi

mapfile -t COMMON_WHEELS < <(find "$ROOT/expanded" -type f -name '*.whl' \
	! -iname 'PyQt5*' ! -iname 'PySide6*' ! -iname 'shiboken6*' ! -iname 'pyqtspinner*')
mapfile -t PYQT5_WHEELS < <(find "$ROOT/expanded" -type f -name '*.whl' \
	\( -iname 'PyQt5*' -o -iname 'pyqt5_*' -o -iname 'pyqtgraph*' \))
mapfile -t PYSIDE6_WHEELS < <(find "$ROOT/expanded" -type f -name '*.whl' \
	\( -iname 'PySide6*' -o -iname 'pyside6_*' -o -iname 'shiboken6*' -o -iname 'pyqtgraph*' \))

if (( ${#COMMON_WHEELS[@]} == 0 )); then
	echo "ERROR: common wheelhouse is empty." >&2
	exit 5
fi
if (( ${#PYQT5_WHEELS[@]} == 0 )); then
	echo "ERROR: PyQt5 binding wheelhouse is empty." >&2
	exit 6
fi
if (( ${#PYSIDE6_WHEELS[@]} == 0 )); then
	echo "ERROR: PySide6 binding wheelhouse is empty." >&2
	exit 7
fi

create_env() {
	local env_name="$1"
	shift
	local env_dir="$ROOT/venvs/$env_name"
	rm -rf "$env_dir"
	"$PYTHON_BIN" -m venv --copies "$env_dir"
	"$env_dir/bin/python" -m pip install --no-index --no-deps "${COMMON_WHEELS[@]}"
	"$env_dir/bin/python" -m pip install --no-index --no-deps "$@"
	"$env_dir/bin/python" -m pip check
}

create_env pyqt5_rev513 "${PYQT5_WHEELS[@]}"
create_env pyside6_rev513 "${PYSIDE6_WHEELS[@]}"

# Best-effort extraction of bundled external tools without mutating the host OS.
find "$ROOT/expanded" -type f \( -name 'pixelmed.jar' -o -name 'dsrdump' -o -name 'java' \) \
	-exec cp -f --parents {} "$ROOT/tools/" \; 2>/dev/null || true

cat > "$ROOT/activate_pyqt5.sh" <<EOF
#!/usr/bin/env bash
export QT_QPA_PLATFORM=offscreen
export JAVA_OPTS="\${JAVA_OPTS:--Xmx4g}"
export PIXELMED_TIMEOUT="\${PIXELMED_TIMEOUT:-900}"
source "$ROOT/venvs/pyqt5_rev513/bin/activate"
EOF

cat > "$ROOT/activate_pyside6.sh" <<EOF
#!/usr/bin/env bash
export QT_QPA_PLATFORM=offscreen
export QT_API=pyside6
export JAVA_OPTS="\${JAVA_OPTS:--Xmx4g}"
export PIXELMED_TIMEOUT="\${PIXELMED_TIMEOUT:-900}"
source "$ROOT/venvs/pyside6_rev513/bin/activate"
EOF

chmod +x "$ROOT/activate_pyqt5.sh" "$ROOT/activate_pyside6.sh"

VERIFY_SCRIPT="$(find "$PAYLOAD_ROOT" -type f -name 'verify_ceus_envs.py' -print -quit)"
if [[ -n "$VERIFY_SCRIPT" ]]; then
	"$ROOT/venvs/pyqt5_rev513/bin/python" "$VERIFY_SCRIPT" pyqt5 \
		| tee "$ROOT/logs/verify_pyqt5.txt"
	"$ROOT/venvs/pyside6_rev513/bin/python" "$VERIFY_SCRIPT" pyside6 \
		| tee "$ROOT/logs/verify_pyside6.txt"
fi

echo "CEUS environments installed under: $ROOT"
echo "PyQt5:  source $ROOT/activate_pyqt5.sh"
echo "PySide6: source $ROOT/activate_pyside6.sh"
