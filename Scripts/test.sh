#!/bin/bash
# Runs the Swift Testing suite (Tests/QuickReminderCoreTests) via `swift test`.
# Any extra arguments are passed straight through, so
#   Scripts/test.sh --filter NaturalDateParserTests
# runs just that suite.
set -euo pipefail
cd "$(dirname "$0")/.."

if swift test "$@"; then
    echo ""
    echo "All tests passed."
else
    status=$?
    echo ""
    echo "Tests FAILED (exit $status)." >&2
    exit $status
fi
