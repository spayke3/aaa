#!/bin/bash
# ==========================================================
# FreeCine V3 Smart Auto Patcher
# Downloads APK -> Decompile -> Detect Update Popup
# Patch Exact Methods -> Rebuild -> Sign
# ==========================================================

set -e

URL="https://github.com/spayke3/aaa/raw/refs/heads/main/FreeCine_v3.0.3_VIP_.apk"
APK="FreeCine_v3.0.3_VIP_.apk"
WORK="freecine_src"
OUTAPK="FreeCine_FIXED_V3.apk"

echo "[1/9] Installing requirements..."
sudo apt update
sudo apt install -y openjdk-17-jdk wget curl unzip zipalign apksigner grep sed

echo "[2/9] Install apktool..."
if ! command -v apktool >/dev/null 2>&1; then
    wget -q https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool
    wget -q https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar -O apktool.jar
    sudo mv apktool /usr/local/bin/
    sudo mv apktool.jar /usr/local/bin/
    sudo chmod +x /usr/local/bin/apktool
fi

echo "[3/9] Cleanup..."
rm -rf "$WORK" "$APK" *.keystore unsigned.apk aligned.apk "$OUTAPK"

echo "[4/9] Download APK..."
wget -O "$APK" "$URL"

echo "[5/9] Decompile APK..."
apktool d "$APK" -o "$WORK" -f

echo "[6/9] Finding popup/version check files..."

MATCHES=$(grep -RilE \
"New Update Available|Telegram Channel|Outdated Or Expired|update now|expired|latest version" \
"$WORK" || true)

echo "$MATCHES"

echo "[7/9] Smart patching matched smali files..."

for file in $MATCHES; do
    if [[ "$file" == *.smali ]]; then
        echo "Patching $file"

        # Targeted patch: find methods that contain update/version popup keywords
        # and inject a return-void at the start so they exit immediately.
        # This leaves all other methods in the file untouched.
        python3 - "$file" <<'PYEOF'
import sys, re

filepath = sys.argv[1]
keywords = [
    'new update available', 'telegram channel', 'outdated or expired',
    'update now', 'expired', 'latest version', 'updatedialog', 'showupdate',
    'forceupdate', 'checkupdate', 'updatecheck'
]

with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

method_re = re.compile(r'(\.method[^\n]*\n)(.*?)(\.end method)', re.DOTALL)
patched = 0

def patch_method(m):
    global patched
    decl   = m.group(1)
    body   = m.group(2)
    end    = m.group(3)

    # Only patch non-constructor methods whose return type is void (ends with )V)
    is_void        = bool(re.search(r'\)V\s*$', decl.strip()))
    is_constructor = '<init>' in decl or '<clinit>' in decl

    if is_void and not is_constructor:
        combined = (decl + body).lower()
        if any(kw in combined for kw in keywords):
            # Already patched?
            if 'return-void' not in body.split('\n')[0]:
                patched += 1
                return decl + '    return-void\n' + body + end
    return m.group(0)

new_content = method_re.sub(patch_method, content)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"  -> {patched} method(s) patched in {filepath}")
PYEOF
    fi
done

echo "[8/9] Rebuild..."

apktool b "$WORK" -o unsigned.apk

echo "[9/9] Signing..."

keytool -genkey -v \
-keystore my.keystore \
-alias freecine \
-keyalg RSA \
-keysize 2048 \
-validity 10000 \
-storepass 123456 \
-keypass 123456 \
-dname "CN=FreeCine,O=Patch,C=US"

zipalign -f 4 unsigned.apk aligned.apk

apksigner sign \
--ks my.keystore \
--ks-pass pass:123456 \
--key-pass pass:123456 \
--out "$OUTAPK" \
aligned.apk

echo ""
echo "===================================="
echo "DONE!"
echo "Patched APK: $OUTAPK"
echo "Install:"
echo "adb install -r $OUTAPK"
echo "===================================="
