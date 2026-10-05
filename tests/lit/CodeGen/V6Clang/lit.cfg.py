import lit.formats
import os

config.name = "V6CLANG"
config.test_format = lit.formats.ShTest(False)
config.suffixes = ['.ll', '.c']
config.test_source_root = os.path.dirname(__file__)

# Find workspace root (contains llvm-build/) by walking upward
d = os.path.dirname(os.path.abspath(__file__))
while d:
    if os.path.isdir(os.path.join(d, 'llvm-build', 'bin')):
        break
    parent = os.path.dirname(d)
    if parent == d:
        break
    d = parent

build_bin = os.path.join(d, 'llvm-build', 'bin')
# Prefer the project-local Python (.venv) over a system one: build.ps1 provisions
# it, and it keeps a machine-wide or Windows-Store-stub `python` from being
# picked up by tests that invoke `python` in their RUN lines.
venv_scripts = os.path.join(d, '.venv', 'Scripts')
config.environment['PATH'] = os.pathsep.join(
    [build_bin, venv_scripts, os.environ.get('PATH', '')])

# %scripts substitution — resolves to <workspace_root>/scripts/ regardless of test depth
config.substitutions.append(('%scripts', os.path.join(d, 'scripts')))
