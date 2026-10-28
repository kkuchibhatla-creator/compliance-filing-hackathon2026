"""Package source only; exclude CLI state, dependencies and runtime artifacts."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
archive = root.parent / 'compliance-filing-source.zip'
excluded = {'node_modules', 'artifacts', '.git', '.sf', '.sfdx', '__pycache__'}
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as package:
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if path.is_file() and not excluded.intersection(relative.parts) and not path.name.startswith('.env'):
            package.write(path, Path(root.name) / relative)
with zipfile.ZipFile(archive) as package:
    assert package.testzip() is None
    assert not any(excluded.intersection(Path(name).parts) for name in package.namelist())
print(f'{archive}: {archive.stat().st_size} bytes; source archive verified.')
