#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
cp .build/release/lecturescribe ./lecturescribe
echo "built: $(pwd)/lecturescribe"
