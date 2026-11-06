#!/usr/bin/env bash
# Pack the Any-Honest validator image build context.
set -euo pipefail
cd "$(dirname "$0")/.."
tar --force-local -czf "$1" package.json provider vendor node_modules/@noble
echo "$1"
