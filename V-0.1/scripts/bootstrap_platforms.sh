#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT="$ROOT/client"
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is required. Install the Flutter stable SDK first." >&2
  exit 1
fi
if [[ -d "$CLIENT/android" || -d "$CLIENT/ios" ]]; then
  echo "Native platform folders already exist. Skipping scaffold generation."
  exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
flutter create --platforms=android,ios --org com.loyfinity --project-name loyfinity "$TMP/loyfinity"
cp -R "$TMP/loyfinity/android" "$CLIENT/android"
cp -R "$TMP/loyfinity/ios" "$CLIENT/ios"
cp "$TMP/loyfinity/.metadata" "$CLIENT/.metadata"
python3 - "$CLIENT" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1])
manifest=root/'android/app/src/main/AndroidManifest.xml'
s=manifest.read_text()
permissions=['android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION','android.permission.CAMERA']
for perm in permissions:
    marker=f'<uses-permission android:name="{perm}"'
    if marker not in s:
        idx=s.find('<application')
        s=s[:idx]+f'    <uses-permission android:name="{perm}" />\n    '+s[idx:]
s=s.replace('android:label="loyfinity"','android:label="Loyfinity"')
manifest.write_text(s)
plist=root/'ios/Runner/Info.plist'
s=plist.read_text()
if '<key>CFBundleDisplayName</key>' in s:
    import re
    s=re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>).*?(</string>)', r'\1Loyfinity\2', s, count=1, flags=re.S)
else:
    s=s.replace('<dict>', '<dict>\n\t<key>CFBundleDisplayName</key>\n\t<string>Loyfinity</string>', 1)
needle='<key>UILaunchStoryboardName</key>'
insert='<key>NSLocationWhenInUseUsageDescription</key>\n\t<string>Loyfinity uses your location while the app is open to show nearby participating businesses and verify in-person loyalty check-ins.</string>\n\t<key>NSCameraUsageDescription</key>\n\t<string>Loyfinity uses the camera to scan business check-in and reward QR codes.</string>\n\t'
if 'NSLocationWhenInUseUsageDescription' not in s: s=s.replace(needle,insert+needle)
plist.write_text(s)
PY
echo "Android and iOS scaffolds created. Review signing, bundle identifiers, app icons and permissions before release."
