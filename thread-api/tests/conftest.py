import os
import sys

# Doit être défini AVANT l'import de app.py (lecture au niveau module)
os.environ["JWT_SECRET"] = "test-secret-for-pytest-only"
os.environ["DB_HOST"] = "localhost"
os.environ["DB_NAME"] = "velvet"
os.environ["DB_USER"] = "velvet"
os.environ["DB_PASSWORD"] = "test"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
