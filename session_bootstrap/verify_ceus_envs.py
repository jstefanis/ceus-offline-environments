#!/usr/bin/env python3
from __future__ import annotations

import importlib
import json
import os
import platform
import subprocess
import sys
from pathlib import Path


def package_present(name: str) -> bool:
	try:
		import importlib.metadata as metadata
		metadata.version(name)
		return True
	except importlib.metadata.PackageNotFoundError:
		return False


def import_one(name: str) -> str:
	module = importlib.import_module(name)
	return getattr(module, "__version__", "import-ok")


def main() -> int:
	if len(sys.argv) != 2 or sys.argv[1] not in {"pyqt5", "pyside6"}:
		raise SystemExit("usage: verify_ceus_envs.py pyqt5|pyside6")

	mode = sys.argv[1]
	if sys.version_info[:2] != (3, 11):
		raise RuntimeError(f"Python 3.11 required, got {sys.version}")

	if package_present("pyqtspinner"):
		raise RuntimeError("pyqtspinner must be absent")

	if mode == "pyqt5":
		if package_present("PySide6") or package_present("shiboken6"):
			raise RuntimeError("PySide6/Shiboken6 must be absent from PyQt5 venv")
		from PyQt5 import QtCore, QtWidgets  # type: ignore
		binding = QtCore.PYQT_VERSION_STR
	else:
		if package_present("PyQt5"):
			raise RuntimeError("PyQt5 must be absent from PySide6 venv")
		from PySide6 import QtCore, QtWidgets  # type: ignore
		binding = QtCore.__version__

	os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
	app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
	widget = QtWidgets.QWidget()
	widget.setWindowTitle("CEUS environment verification")
	widget.show()
	app.processEvents()
	widget.close()

	required_imports = [
		"numpy",
		"scipy",
		"pandas",
		"pydicom",
		"highdicom",
		"cv2",
		"skimage",
		"matplotlib",
		"pyqtgraph",
		"weasyprint",
		"docx",
		"pikepdf",
		"h5py",
	]

	results = {}
	for module in required_imports:
		results[module] = import_one(module)

	report = {
		"mode": mode,
		"python": sys.version,
		"executable": sys.executable,
		"platform": platform.platform(),
		"binding_version": binding,
		"imports": results,
		"qt_offscreen_smoke": True,
		"pyqtspinner_absent": True,
	}

	print(json.dumps(report, indent=2, sort_keys=True))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
