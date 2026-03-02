#!/bin/bash
# ============================================================
# Fylooo Linux Deployment Script
# Usage: ./deploy_linux.sh [version]
# Example: ./deploy_linux.sh 1.1.5
# ============================================================

set -e  # Exit on any error

# ─── Configuration ───────────────────────────────────────────
APP_NAME="fylooo"
EXE_NAME="cpft"
VERSION="${1:-1.1.5}"
MAINTAINER="info@omnity.com"
DESCRIPTION="Fylooo — High-speed wireless file transfer"
DIST_DIR="dist/desktop_releases"
BUILD_DIR="build/linux/x64/release/bundle"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo "============================================"
echo "  Fylooo Linux Deployment — v${VERSION}"
echo "============================================"

# ─── Step 1: Check Prerequisites ─────────────────────────────
log "Checking prerequisites..."
command -v flutter >/dev/null 2>&1 || error "Flutter not found. Install Flutter first."
command -v dpkg-deb >/dev/null 2>&1 || error "dpkg-deb not found. Run: sudo apt-get install dpkg-dev"
command -v zip >/dev/null 2>&1 || error "zip not found. Run: sudo apt-get install zip"

# ─── Step 2: Flutter Build ────────────────────────────────────
log "Building Flutter Linux release..."
flutter build linux --release
log "Build complete. Output: ${BUILD_DIR}/"

# ─── Step 3: Set up Package Directory ────────────────────────
PKG_DIR="${APP_NAME}-${VERSION}-amd64"
log "Creating package structure in ${PKG_DIR}/..."

rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/usr/bin/${APP_NAME}"
mkdir -p "${PKG_DIR}/usr/share/applications"
mkdir -p "${PKG_DIR}/usr/share/icons/hicolor/512x512/apps"
mkdir -p "${PKG_DIR}/DEBIAN"

# ─── Step 4: Copy Bundle ──────────────────────────────────────
log "Copying build bundle..."
cp -r "${BUILD_DIR}/." "${PKG_DIR}/usr/bin/${APP_NAME}/"
chmod +x "${PKG_DIR}/usr/bin/${APP_NAME}/${EXE_NAME}"

# ─── Step 5: Copy Icon ────────────────────────────────────────
log "Copying app icon..."
if [ -f "assets/images/app-logo.png" ]; then
    cp "assets/images/app-logo.png" \
       "${PKG_DIR}/usr/share/icons/hicolor/512x512/apps/${APP_NAME}.png"
else
    warn "Icon not found at assets/images/app-logo.png, skipping icon."
fi

# ─── Step 6: Create .desktop Entry ───────────────────────────
log "Creating .desktop entry..."
cat > "${PKG_DIR}/usr/share/applications/${APP_NAME}.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Fylooo
Comment=High-speed wireless file transfer
Exec=/usr/bin/${APP_NAME}/${EXE_NAME}
Icon=${APP_NAME}
Terminal=false
Categories=Network;FileTransfer;
StartupNotify=true
EOF

# ─── Step 7: Create DEBIAN/control ───────────────────────────
log "Creating DEBIAN/control..."
cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: ${APP_NAME}
Version: ${VERSION}
Section: net
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libblkid1, liblzma5
Maintainer: ${MAINTAINER}
Description: ${DESCRIPTION}
 Fylooo enables fast peer-to-peer file transfers over Wi-Fi and hotspot
 connections between Linux, Windows, and Android devices.
EOF

# ─── Step 8: Create postinst ─────────────────────────────────
cat > "${PKG_DIR}/DEBIAN/postinst" << 'EOF'
#!/bin/bash
chmod +x /usr/bin/fylooo/cpft
update-desktop-database /usr/share/applications &>/dev/null || true
EOF
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

# ─── Step 9: Build .deb ──────────────────────────────────────
DEB_FILE="${APP_NAME}-${VERSION}-amd64.deb"
log "Building .deb package → ${DEB_FILE}..."
dpkg-deb --build "${PKG_DIR}"
log "Package created: ${DEB_FILE}"

# ─── Step 10: Create Update ZIP ──────────────────────────────
ZIP_FILE="${APP_NAME}-linux-update-${VERSION}.zip"
log "Creating update ZIP → ${ZIP_FILE}..."
(cd "${BUILD_DIR}" && zip -r "../../../../../${ZIP_FILE}" .)
log "Update ZIP created: ${ZIP_FILE}"

# ─── Step 11: Copy to dist/ ──────────────────────────────────
log "Copying to ${DIST_DIR}/..."
mkdir -p "${DIST_DIR}"
cp "${DEB_FILE}" "${DIST_DIR}/"
cp "${ZIP_FILE}" "${DIST_DIR}/"

# ─── Step 12: Update releases.json ───────────────────────────
RELEASES_FILE="dist/releases.json"
TODAY=$(date +%Y-%m-%d)

if [ -f "${RELEASES_FILE}" ]; then
    log "Updating ${RELEASES_FILE}..."
    # Mark all previous linux entries as not available
    python3 -c "
import json, sys
with open('${RELEASES_FILE}') as f:
    data = json.load(f)

# Mark old linux entries unavailable
for entry in data:
    if entry.get('platform') == 'linux' and entry.get('version') != 'v${VERSION}':
        entry['available'] = False

# Check if this version already exists
versions = [e['version'] for e in data]
if 'v${VERSION}' not in versions:
    new_entry = {
        'platform': 'linux',
        'version': 'v${VERSION}',
        'release_type': 'Stable',
        'filename': '${APP_NAME}-${VERSION}-amd64.deb',
        'downloadUrl': '/desktop_releases/${APP_NAME}-${VERSION}-amd64.deb',
        'update_zip': '/desktop_releases/${APP_NAME}-linux-update-${VERSION}.zip',
        'date': '${TODAY}',
        'available': True,
        'notes': 'Stability improvements and bug fixes.'
    }
    # Insert after first linux entry or at beginning
    insert_at = next((i for i, e in enumerate(data) if e.get('platform') == 'linux'), 0)
    data.insert(insert_at, new_entry)

with open('${RELEASES_FILE}', 'w') as f:
    json.dump(data, f, indent=4)
print('releases.json updated.')
"
else
    warn "${RELEASES_FILE} not found, skipping releases.json update."
fi

# ─── Done ─────────────────────────────────────────────────────
echo ""
echo "============================================"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo "============================================"
echo "  .deb installer : ${DIST_DIR}/${DEB_FILE}"
echo "  Update ZIP      : ${DIST_DIR}/${ZIP_FILE}"
echo ""
echo "Next steps:"
echo "  1. Restart your Node.js server to serve the new files"
echo "  2. Test the .deb: sudo dpkg -i ${DEB_FILE}"
echo "  3. Verify download URL from your releases page"
echo "============================================"
