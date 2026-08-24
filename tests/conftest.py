import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON_SCRIPT = ROOT / "scripts"
BACKEND = ROOT / "backend"

sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(PYTHON_SCRIPT))
sys.path.insert(0, str(BACKEND))
