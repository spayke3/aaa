#!/bin/bash
# ==========================================================
# FreeCine Auto Reverse + Patch + Rebuild Script
# Target:
# https://github.com/spayke3/aaa/raw/refs/heads/main/FreeCine_v3.0.3_VIP_.apk
# ==========================================================

set -e

URL="https://github.com/spayke3/aaa/raw/refs/heads/main/FreeCine_v3.0.3_VIP_.apk"
APK="FreeCine_v3.0.3_VIP_.apk"
WORK="freecine_src"
OUTAPK="FreeCine_FIXED.apk"

echo "[1/10] Install dependencies..."
sudo apt update
sudo apt install -y openjdk-17-jdk wget curl unzip zipalign apksigner grep sed git

echo "[2/10] Install apktool..."
if ! command -v apktool >/dev/null 2>&1; then
  wget -q https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool
  wget -q https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar -O apktool.jar
  sudo mv apktool /usr/local/bin/
  sudo mv apktool.jar /usr/local/bin/
  sudo chmod +x /usr/local/bin/apktool
fi

echo "[3/10] Install jadx..."
if ! command -v jadx >/dev/null 2>&1; then
  wget -q https://github.com/skylot/jadx/releases/latest/download/jadx-1.5.0.zip
  unzip -q jadx-1.5.0.zip -d jadx_tmp
  sudo mv jadx_tmp/bin/jadx /usr/local/bin/
  sudo chmod +x /usr/local/bin/jadx
fi

echo "[4/10] Cleanup..."
rm -rf "$WORK" output_java *.keystore unsigned.apk aligned.apk "$APK" "$OUTAPK"

echo "[5/10] Download APK..."
wget -O "$APK" "$URL"

echo "[6/10] Decompile..."
apktool d "$APK" -o "$WORK" -f

echo "[7/10] Extract Java..."
jadx -d output_java "$APK" || true

echo "[8/10] Search suspicious strings..."
grep -RniE "New Update Available|Telegram Channel|Outdated|Expired|Update Now" "$WORK" || true

echo "[9/10] Patch popup logic..."

find "$WORK" -type f -name "*.smali" | while read f; do
    if grep -qiE "New Update Available|Telegram Channel|Outdated|Expired|Update Now" "$f"; then
        echo "Patching $f"

        # disable invoke calls in suspicious methods
        sed -i 's/invoke-virtual/# invoke removed/g' "$f"
        sed -i 's/invoke-static/# invoke removed/g' "$f"

        # make conditions false
        sed -i 's/if-nez/if-eqz/g' "$f"
        sed -i 's/if-gtz/if-lez/g' "$f"
    fi
done

echo "[10/10] Rebuild + Sign..."

apktool b "$WORK" -o unsigned.apk

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
echo "====================================="
echo "DONE!"
echo "Patched APK => $OUTAPK"
echo "Install with:"
echo "adb install -r $OUTAPK"
echo "====================================="
