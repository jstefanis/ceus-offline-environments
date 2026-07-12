#!/usr/bin/env bash
# rev513a_env_bootstrap_runtime_r2_cdx_cl
set -euo pipefail

ROOT="${1:-/mnt/data/ceus_envs_rev513a}"
PAYLOAD_ROOT="${2:-$(pwd)}"

COMMON_NAME='ceus_python311_common_offline_rev513a_r1_cdx_cl.zip'
PYQT5_NAME='ceus_pyqt5_binding_offline_rev513a_r1_cdx_cl.zip'
PYSIDE6_NAME='ceus_pyside6_binding_offline_rev513a_r1_cdx_cl.zip'
SYSTEM_NAME='ceus_system_deps_ubuntu2404_offline_rev513a_r1_cdx_cl.zip'
RUNTIME_NAME='ceus_cpython311_runtime_linux_x86_64_offline_rev513a_r1_cdx_cl.zip'

find_one() {
	local name="$1"
	local found
	found="$(find "$PAYLOAD_ROOT" -type f -name "$name" -print -quit)"
	if [[ -z "$found" || ! -f "$found" ]]; then
		echo "ERROR: required file missing under $PAYLOAD_ROOT: $name" >&2
		exit 2
	fi
	printf '%s\n' "$found"
}

verify_sidecar() {
	local archive="$1"
	local sidecar="$2"
	local expected
	local actual
	expected="$(awk 'NF >= 1 {print $1; exit}' "$sidecar")"
	actual="$(sha256sum "$archive" | awk '{print $1}')"
	if [[ -z "$expected" || "$actual" != "$expected" ]]; then
		echo "ERROR: SHA-256 mismatch for $(basename "$archive"): got $actual expected $expected" >&2
		exit 3
	fi
	echo "SHA-256 OK: $(basename "$archive")"
}

COMMON_ZIP="$(find_one "$COMMON_NAME")"
PYQT5_ZIP="$(find_one "$PYQT5_NAME")"
PYSIDE6_ZIP="$(find_one "$PYSIDE6_NAME")"
SYSTEM_ZIP="$(find_one "$SYSTEM_NAME")"
RUNTIME_ZIP="$(find_one "$RUNTIME_NAME")"

COMMON_SHA="$(find_one "$COMMON_NAME.sha256")"
PYQT5_SHA="$(find_one "$PYQT5_NAME.sha256")"
PYSIDE6_SHA="$(find_one "$PYSIDE6_NAME.sha256")"
SYSTEM_SHA="$(find_one "$SYSTEM_NAME.sha256")"
RUNTIME_SHA="$(find_one "$RUNTIME_NAME.sha256")"

verify_sidecar "$COMMON_ZIP" "$COMMON_SHA"
verify_sidecar "$PYQT5_ZIP" "$PYQT5_SHA"
verify_sidecar "$PYSIDE6_ZIP" "$PYSIDE6_SHA"
verify_sidecar "$SYSTEM_ZIP" "$SYSTEM_SHA"
verify_sidecar "$RUNTIME_ZIP" "$RUNTIME_SHA"

rm -rf "$ROOT/archives" "$ROOT/expanded" "$ROOT/runtime" "$ROOT/venvs" "$ROOT/logs"
mkdir -p "$ROOT/archives" "$ROOT/expanded" "$ROOT/runtime" "$ROOT/venvs" "$ROOT/tools" "$ROOT/logs"

cp -f "$COMMON_ZIP" "$PYQT5_ZIP" "$PYSIDE6_ZIP" "$SYSTEM_ZIP" "$RUNTIME_ZIP" "$ROOT/archives/"

COMMON_DIR="$ROOT/expanded/common"
PYQT5_DIR="$ROOT/expanded/pyqt5"
PYSIDE6_DIR="$ROOT/expanded/pyside6"
SYSTEM_DIR="$ROOT/expanded/system_deps"
RUNTIME_UNZIP="$ROOT/expanded/runtime_package"
mkdir -p "$COMMON_DIR" "$PYQT5_DIR" "$PYSIDE6_DIR" "$SYSTEM_DIR" "$RUNTIME_UNZIP"

unzip -q -o "$COMMON_ZIP" -d "$COMMON_DIR"
unzip -q -o "$PYQT5_ZIP" -d "$PYQT5_DIR"
unzip -q -o "$PYSIDE6_ZIP" -d "$PYSIDE6_DIR"
unzip -q -o "$SYSTEM_ZIP" -d "$SYSTEM_DIR"
unzip -q -o "$RUNTIME_ZIP" -d "$RUNTIME_UNZIP"

RUNTIME_TARBALL="$(find "$RUNTIME_UNZIP" -type f -name 'cpython-3.11*install_only*.tar.gz' -print -quit)"
if [[ -z "$RUNTIME_TARBALL" ]]; then
	echo "ERROR: CPython 3.11 install_only tarball missing from runtime package." >&2
	exit 4
fi

RUNTIME_SUMS="$(find "$RUNTIME_UNZIP" -type f -name 'SHA256SUM_runtime_rev513a.txt' -print -quit)"
if [[ -z "$RUNTIME_SUMS" ]]; then
	echo "ERROR: runtime internal checksum manifest missing." >&2
	exit 4
fi
(
	cd "$(dirname "$RUNTIME_SUMS")"
	sha256sum -c "$(basename "$RUNTIME_SUMS")"
)

tar -xzf "$RUNTIME_TARBALL" -C "$ROOT/runtime"
RUNTIME_ROOT="$(find "$ROOT/runtime" -type f -path '*/bin/python3.11' -print -quit | xargs -r dirname | xargs -r dirname)"
if [[ -z "$RUNTIME_ROOT" ]]; then
	echo "ERROR: CPython 3.11 runtime root could not be resolved." >&2
	exit 4
fi
PYTHON_BIN="$RUNTIME_ROOT/bin/python3.11"
if [[ ! -x "$PYTHON_BIN" ]]; then
	echo "ERROR: CPython 3.11 executable missing: $PYTHON_BIN" >&2
	exit 4
fi

export LD_LIBRARY_PATH="$RUNTIME_ROOT/lib:${LD_LIBRARY_PATH:-}"
PY_VERSION="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "$PY_VERSION" != '3.11' ]]; then
	echo "ERROR: expected CPython 3.11, got $PY_VERSION" >&2
	exit 4
fi
"$PYTHON_BIN" -c 'import bz2, ctypes, ensurepip, lzma, sqlite3, ssl, venv, zlib'
"$PYTHON_BIN" -m ensurepip --version >/dev/null

echo "Runtime OK: $("$PYTHON_BIN" --version 2>&1) at $PYTHON_BIN"

COMMON_WHEELHOUSE="$(find "$COMMON_DIR" -type d -name wheelhouse_common -print -quit)"
PYQT5_WHEELHOUSE="$(find "$PYQT5_DIR" -type d -name wheelhouse_pyqt5 -print -quit)"
PYSIDE6_WHEELHOUSE="$(find "$PYSIDE6_DIR" -type d -name wheelhouse_pyside6 -print -quit)"

for wheelhouse in "$COMMON_WHEELHOUSE" "$PYQT5_WHEELHOUSE" "$PYSIDE6_WHEELHOUSE"; do
	if [[ -z "$wheelhouse" || ! -d "$wheelhouse" ]]; then
		echo "ERROR: required wheelhouse directory missing." >&2
		exit 5
	fi
	if [[ -f "$wheelhouse/MANIFEST.sha256" ]]; then
		while read -r expected_hash expected_size filename; do
			[[ -z "$expected_hash" || "$expected_hash" == \#* ]] && continue
			wheel_path="$wheelhouse/$filename"
			if [[ ! -f "$wheel_path" ]]; then
				echo "ERROR: wheelhouse manifest entry missing: $wheel_path" >&2
				exit 5
			fi
			actual_hash="$(sha256sum "$wheel_path" | awk '{print $1}')"
			actual_size="$(stat -c '%s' "$wheel_path")"
			if [[ "$actual_hash" != "$expected_hash" || "$actual_size" != "$expected_size" ]]; then
				echo "ERROR: wheelhouse manifest mismatch: $filename" >&2
				exit 5
			fi
		done < "$wheelhouse/MANIFEST.sha256"
	fi
done

if find "$COMMON_WHEELHOUSE" -maxdepth 1 -type f \( -iname 'PyQt5*' -o -iname 'PySide6*' -o -iname 'shiboken6*' -o -iname 'pyqtspinner*' \) -print -quit | grep -q .; then
	echo "ERROR: common wheelhouse contains a forbidden Qt binding or pyqtspinner." >&2
	exit 5
fi
if find "$PYQT5_WHEELHOUSE" -maxdepth 1 -type f \( -iname 'PySide6*' -o -iname 'shiboken6*' -o -iname 'pyqtspinner*' \) -print -quit | grep -q .; then
	echo "ERROR: PyQt5 wheelhouse contains PySide6/Shiboken6 or pyqtspinner." >&2
	exit 6
fi
if find "$PYSIDE6_WHEELHOUSE" -maxdepth 1 -type f \( -iname 'PyQt5*' -o -iname 'pyqt5_*' -o -iname 'pyqtspinner*' \) -print -quit | grep -q .; then
	echo "ERROR: PySide6 wheelhouse contains PyQt5 or pyqtspinner." >&2
	exit 7
fi

mapfile -t COMMON_WHEELS < <(find "$COMMON_WHEELHOUSE" -maxdepth 1 -type f -name '*.whl' -print | sort)
mapfile -t PYQT5_WHEELS < <(find "$PYQT5_WHEELHOUSE" -maxdepth 1 -type f -name '*.whl' -print | sort)
mapfile -t PYSIDE6_WHEELS < <(find "$PYSIDE6_WHEELHOUSE" -maxdepth 1 -type f -name '*.whl' -print | sort)

if (( ${#COMMON_WHEELS[@]} == 0 || ${#PYQT5_WHEELS[@]} == 0 || ${#PYSIDE6_WHEELS[@]} == 0 )); then
	echo "ERROR: one or more wheelhouses are empty." >&2
	exit 8
fi

create_env() {
	local env_name="$1"
	shift
	local env_dir="$ROOT/venvs/$env_name"
	"$PYTHON_BIN" -m venv --copies "$env_dir"
	"$env_dir/bin/python" -m pip install --disable-pip-version-check --no-index --no-deps --no-compile --quiet "${COMMON_WHEELS[@]}"
	"$env_dir/bin/python" -m pip install --disable-pip-version-check --no-index --no-deps --no-compile --quiet "$@"
	"$env_dir/bin/python" -m pip check
}

create_env pyqt5_rev513 "${PYQT5_WHEELS[@]}"
create_env pyside6_rev513 "${PYSIDE6_WHEELS[@]}"

cat > "$ROOT/activate_pyqt5.sh" <<EOF_ACTIVATE_PYQT5
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$RUNTIME_ROOT/lib:\${LD_LIBRARY_PATH:-}"
export QT_QPA_PLATFORM=offscreen
export QT_API=pyqt5
export JAVA_OPTS="\${JAVA_OPTS:--Xmx4g}"
export PIXELMED_TIMEOUT="\${PIXELMED_TIMEOUT:-900}"
source "$ROOT/venvs/pyqt5_rev513/bin/activate"
EOF_ACTIVATE_PYQT5

cat > "$ROOT/activate_pyside6.sh" <<EOF_ACTIVATE_PYSIDE6
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$RUNTIME_ROOT/lib:\${LD_LIBRARY_PATH:-}"
export QT_QPA_PLATFORM=offscreen
export QT_API=pyside6
export JAVA_OPTS="\${JAVA_OPTS:--Xmx4g}"
export PIXELMED_TIMEOUT="\${PIXELMED_TIMEOUT:-900}"
source "$ROOT/venvs/pyside6_rev513/bin/activate"
EOF_ACTIVATE_PYSIDE6
chmod +x "$ROOT/activate_pyqt5.sh" "$ROOT/activate_pyside6.sh"

VERIFY_SCRIPT="$(find "$PAYLOAD_ROOT" -type f -name 'verify_ceus_envs.py' -print -quit)"
if [[ -z "$VERIFY_SCRIPT" ]]; then
	echo "ERROR: verify_ceus_envs.py missing from payload." >&2
	exit 9
fi

QT_QPA_PLATFORM=offscreen QT_API=pyqt5 "$ROOT/venvs/pyqt5_rev513/bin/python" "$VERIFY_SCRIPT" pyqt5 \
	| tee "$ROOT/logs/verify_pyqt5.txt"
QT_QPA_PLATFORM=offscreen QT_API=pyside6 "$ROOT/venvs/pyside6_rev513/bin/python" "$VERIFY_SCRIPT" pyside6 \
	| tee "$ROOT/logs/verify_pyside6.txt"

find "$SYSTEM_DIR" -type f \( -name 'pixelmed.jar' -o -name 'dsrdump' -o -name 'java' \) \
	-exec cp -f --parents {} "$ROOT/tools/" \; 2>/dev/null || true

echo "CEUS environments installed under: $ROOT"
echo "PyQt5:  source $ROOT/activate_pyqt5.sh"
echo "PySide6: source $ROOT/activate_pyside6.sh"
