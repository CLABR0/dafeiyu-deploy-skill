"""Unpack a manifest-verified DSH plugin without Windows tar filename issues."""
import shutil
import sys
import tarfile
from pathlib import Path, PurePosixPath

archive, destination = map(Path, sys.argv[1:3])
destination.mkdir(parents=True, exist_ok=True)
root = destination.resolve()
with tarfile.open(archive, mode='r:gz', encoding='utf-8') as tar:
    members = tar.getmembers()
    roots = set()
    for member in members:
        name = PurePosixPath(member.name)
        parts = name.parts
        if not parts or name.is_absolute() or any(p in ('.', '..') or ':' in p or '\\' in p for p in parts):
            raise ValueError('Unsafe plugin path')
        roots.add(parts[0])
        if len(roots) != 1 or not (member.isdir() or member.isfile()):
            raise ValueError('Unexpected plugin archive layout')
        if len(parts) == 1:
            continue
        target = root.joinpath(*parts[1:]).resolve()
        if not target.is_relative_to(root):
            raise ValueError('Plugin extraction escaped destination')
        if member.isdir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(member) as src, target.open('wb') as dest:
                shutil.copyfileobj(src, dest)
if not (root / 'package.json').is_file():
    raise ValueError('Plugin manifest missing')
