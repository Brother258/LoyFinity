#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE_URL="${API_BASE_URL:-}"
if [[ -z "$API_BASE_URL" || "$API_BASE_URL" != https://* || "$API_BASE_URL" == *yourdomain.com* || "$API_BASE_URL" == *example.com* || "$API_BASE_URL" == */v1* ]]; then
  echo "Set API_BASE_URL to your real HTTPS API origin (for example https://api.yourdomain.com), without /v1." >&2
  exit 1
fi
"$ROOT/scripts/bootstrap_platforms.sh"
cd "$ROOT/client"
flutter pub get
flutter analyze
flutter test
flutter build ipa --release --dart-define=API_BASE_URL="$API_BASE_URL"
echo "IPA output is under client/build/ios/ipa/"
