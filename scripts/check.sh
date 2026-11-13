#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
python3 -m unittest discover -s tests -v
if command -v node >/dev/null 2>&1; then
  node tests/test_usage_model.js
  node tests/test_model.js
else
  echo 'Node unavailable: chart model tests skipped (not a runtime dependency).'
fi
python3 - <<'PY'
import json
from pathlib import Path
manifest = json.loads(Path('manifest.json').read_text())
assert manifest['id'] == 'eusener.power'
assert manifest['schemaVersion'] == 1
assert manifest['omarchy']['clonedFrom'] == 'omarchy.power'
assert manifest['barWidget']['defaultSection'] == 'right'
for entry in manifest['entryPoints'].values():
    assert Path(entry).is_file() and not Path(entry).is_absolute() and '..' not in Path(entry).parts
catalogs = {p.stem: json.loads(p.read_text()) for p in Path('i18n').glob('*.json')}
for locale, catalog in catalogs.items():
    assert catalog.keys() == catalogs['en'].keys(), locale
    assert all(isinstance(value, str) and value for value in catalog.values()), locale
print('Manifest and translation catalogs: OK')
PY
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy plugin validate "$project_dir"
else
  echo 'Omarchy unavailable: native plugin validation skipped.'
fi
qml_formatter=$(command -v qmlformat || true)
if [[ -z $qml_formatter && -x /usr/lib/qt6/bin/qmlformat ]]; then
  qml_formatter=/usr/lib/qt6/bin/qmlformat
fi
if [[ -n $qml_formatter ]]; then
  "$qml_formatter" -n Panel.qml >/dev/null
  "$qml_formatter" -n UsageChart.qml >/dev/null
  echo 'QML syntax: OK'
else
  echo 'qmlformat unavailable: QML syntax check skipped.'
fi
