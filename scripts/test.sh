#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Pin the actual Forever UI source used by the native guild-action tests.
ui_ref=c01a87b549bbc19e0f284c1616d18654c91297de
fixtures="$PWD/.test-fixtures"
mkdir -p "$fixtures"
for extension in lua xml; do
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 10 --max-time 60 \
    "https://raw.githubusercontent.com/Gethe/wow-ui-source/$ui_ref/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.$extension" \
    --output "$fixtures/wow-forever-SecureTemplates.$extension"
done

for source in ./*.lua tests/*.test.lua; do luac5.1 -p "$source"; done
for test in tests/*.test.lua; do
  echo "Running $test"
  VIRTUOUS_WOW_UI_FIXTURES="$fixtures" lua5.1 "$test"
done
