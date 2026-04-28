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

        # Disable all invoke calls in suspicious blocks
        sed -i 's/^[[:space:]]*invoke-static/# disabled invoke-static/g' "$file"
        sed -i 's/^[[:space:]]*invoke-virtual/# disabled invoke-virtual/g' "$file"
        sed -i 's/^[[:space:]]*invoke-direct/# disabled invoke-direct/g' "$file"

        # Flip conditionals
        sed -i 's/if-nez/if-eqz/g' "$file"
        sed -i 's/if-eqz/if-nez/g' "$file"
        sed -i 's/if-gtz/if-lez/g' "$file"
        sed -i 's/if-ltz/if-gez/g' "$file"

        # Force booleans true
        sed -i 's/const\/4 v0, 0x0/const\/4 v0, 0x1/g' "$file"
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
