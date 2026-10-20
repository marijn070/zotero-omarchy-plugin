#!/bin/sh
# Runs the offscreen Panel tests against the Omarchy shell test doubles in ./stubs.
# Needs the Qt 6 qmltestrunner (qt6-declarative); no Omarchy shell or Zotero is started.
# Set QMLTESTRUNNER to override the runner.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
runner=${QMLTESTRUNNER:-}
if [ -z "$runner" ]; then
  for candidate in /usr/lib/qt6/bin/qmltestrunner /usr/lib64/qt6/bin/qmltestrunner /usr/lib/x86_64-linux-gnu/qt6/bin/qmltestrunner qmltestrunner6 qmltestrunner; do
    if command -v "$candidate" >/dev/null 2>&1; then runner=$candidate; break; fi
  done
fi
[ -n "$runner" ] || { echo "qmltestrunner (Qt 6) not found" >&2; exit 127; }
NO_AT_BRIDGE=1 QT_QPA_PLATFORM=offscreen exec "$runner" -import "$here/stubs" -input "$here/tst_panel.qml" "$@"
