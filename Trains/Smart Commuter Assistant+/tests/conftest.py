import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON_SCRIPT = ROOT / "lib" / "PythonScript"

sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(PYTHON_SCRIPT))
