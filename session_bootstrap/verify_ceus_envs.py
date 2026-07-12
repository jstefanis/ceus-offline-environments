#!/usr/bin/env python3
# rev513a_env_bootstrap_runtime_r2_cdx_cl
from __future__ import annotations

import importlib
import importlib.metadata as metadata
import json
import os
import platform
import subprocess
import sys
import tempfile
from pathlib import Path


def package_present(name: str) -> bool:
	"""Return whether an installed distribution exists by canonical package name."""
	try:
		metadata.version(name)
		return True
	except metadata.PackageNotFoundError:
		return False


def import_one(name: str) -> str:
	"""Import one required module and return a printable version marker."""
	module = importlib.import_module(name)
	return str(getattr(module, "__version__", "import-ok"))


def codec_status() -> dict[str, bool]:
	"""Return pydicom decoder availability for required compressed transfer syntaxes."""
	from pydicom.pixels import get_decoder
	from pydicom.uid import JPEGBaseline8Bit, JPEG2000Lossless, JPEGLSLossless

	return {
		"jpeg_baseline": bool(get_decoder(JPEGBaseline8Bit).is_available),
		"jpeg_ls_lossless": bool(get_decoder(JPEGLSLossless).is_available),
		"jpeg2000_lossless": bool(get_decoder(JPEG2000Lossless).is_available),
	}


def verify_rendering(QtWidgets: object) -> dict[str, bool]:
	"""Exercise Qt, pyqtgraph, Matplotlib QtAgg, WeasyPrint, and pikepdf output paths."""
	import matplotlib

	matplotlib.use("QtAgg")
	from matplotlib.backends.backend_qtagg import FigureCanvasQTAgg
	from matplotlib.figure import Figure
	import pikepdf
	import pyqtgraph as pg
	from weasyprint import HTML

	app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
	widget = QtWidgets.QWidget()
	widget.setWindowTitle("CEUS environment verification")
	widget.show()
	app.processEvents()

	plot = pg.PlotWidget()
	plot.plot([0.0, 1.0, 2.0], [0.0, 1.0, 0.5])
	plot.show()
	app.processEvents()

	figure = Figure(figsize=(2.0, 1.5))
	canvas = FigureCanvasQTAgg(figure)
	axis = figure.add_subplot(111)
	axis.plot([0.0, 1.0], [0.0, 1.0])
	canvas.draw()

	with tempfile.TemporaryDirectory(prefix="ceus_env_verify_") as tmpdir:
		pdf_path = Path(tmpdir) / "weasyprint.pdf"
		rewrite_path = Path(tmpdir) / "pikepdf.pdf"
		HTML(string="<html><body><p>CEUS environment verification</p></body></html>").write_pdf(pdf_path)
		with pikepdf.open(pdf_path) as document:
			document.save(rewrite_path)
		if not pdf_path.is_file() or pdf_path.stat().st_size == 0:
			raise RuntimeError("WeasyPrint produced no PDF bytes")
		if not rewrite_path.is_file() or rewrite_path.stat().st_size == 0:
			raise RuntimeError("pikepdf produced no rewritten PDF bytes")

	plot.close()
	widget.close()
	app.processEvents()
	return {
		"qt_offscreen_smoke": True,
		"pyqtgraph_plot_smoke": True,
		"matplotlib_qtagg_draw": True,
		"weasyprint_pdf": True,
		"pikepdf_rewrite": True,
	}


def main() -> int:
	"""Validate one isolated CEUS Qt environment and print a JSON evidence report."""
	if len(sys.argv) != 2 or sys.argv[1] not in {"pyqt5", "pyside6"}:
		raise SystemExit("usage: verify_ceus_envs.py pyqt5|pyside6")

	mode = sys.argv[1]
	if sys.version_info[:2] != (3, 11):
		raise RuntimeError(f"Python 3.11 required, got {sys.version}")

	for module_name in ("bz2", "ctypes", "ensurepip", "lzma", "sqlite3", "ssl", "venv", "zlib"):
		importlib.import_module(module_name)

	if package_present("pyqtspinner"):
		raise RuntimeError("pyqtspinner must be absent")

	os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
	os.environ["QT_API"] = mode

	if mode == "pyqt5":
		if package_present("PySide6") or package_present("shiboken6"):
			raise RuntimeError("PySide6/Shiboken6 must be absent from PyQt5 venv")
		from PyQt5 import QtCore, QtWidgets  # type: ignore
		binding_version = QtCore.PYQT_VERSION_STR
	else:
		if package_present("PyQt5"):
			raise RuntimeError("PyQt5 must be absent from PySide6 venv")
		from PySide6 import QtCore, QtWidgets  # type: ignore
		binding_version = QtCore.__version__

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
	imports = {name: import_one(name) for name in required_imports}

	codecs = codec_status()
	missing_codecs = [name for name, available in codecs.items() if not available]
	if missing_codecs:
		raise RuntimeError(f"required pydicom decoders unavailable: {missing_codecs}")

	pip_check = subprocess.run(
		[sys.executable, "-m", "pip", "check"],
		capture_output=True,
		text=True,
		check=False,
	)
	pip_output = (pip_check.stdout + pip_check.stderr).strip()
	if pip_check.returncode != 0:
		raise RuntimeError(f"pip check failed:\n{pip_output}")

	rendering = verify_rendering(QtWidgets)
	report = {
		"mode": mode,
		"python": sys.version,
		"executable": sys.executable,
		"platform": platform.platform(),
		"binding_version": binding_version,
		"imports": imports,
		"pydicom_decoder_availability": codecs,
		"runtime_stdlib_ok": True,
		"pip_check_ok": True,
		"pip_check_output": pip_output,
		"pyqtspinner_absent": True,
		**rendering,
	}
	print(json.dumps(report, indent=2, sort_keys=True))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
