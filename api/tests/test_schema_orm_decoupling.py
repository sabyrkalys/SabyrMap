import ast
from pathlib import Path


def test_schemas_package_does_not_import_orm_models():
    schemas_dir = Path(__file__).resolve().parent.parent / "app" / "schemas"
    violations = []
    for path in schemas_dir.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("app.models"):
                violations.append(f"{path.name}: imports {node.module}")
    assert violations == [], f"schemas layer must not import ORM models: {violations}"
