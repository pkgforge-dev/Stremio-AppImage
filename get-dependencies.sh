#!/bin/sh

set -eu

ARCH=$(uname -m)

# aarch64 cannot be built: the shell requires Qt5WebEngine, and there is no
# aarch64 build of qt5-webengine in the Arch repos, the AUR or ALARM
if [ "$ARCH" != 'x86_64' ]; then
	echo "Stremio has no $ARCH build, bailing out..."
	exit 1
fi

SHELL_REPO=https://github.com/Stremio/stremio-shell.git
BUILD_DIR=$PWD/build

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
# libmpv links against libjack.so.0, so something has to provide it, and
# pipewire-jack is the one that works without a jack server running
pacman -Syu --noconfirm \
	cmake             \
	curl              \
	mpv               \
	nodejs            \
	pipewire-jack     \
	qt5-base          \
	qt5-declarative   \
	qt5-quickcontrols \
	qt5-quickcontrols2

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano ffmpeg-mini

echo "Installing Qt5 WebEngine..."
echo "---------------------------------------------------------------"
# qt5-webengine and the qt5-webchannel and qt5-location it needs were dropped
# from the Arch repos
make-aur-package --archlinuxcn qt5-webengine

echo "Getting the shell sources..."
echo "---------------------------------------------------------------"
rm -rf "$BUILD_DIR"
git clone "$SHELL_REPO" "$BUILD_DIR/shell" && (
	cd "$BUILD_DIR/shell"
	# the tag list also carries -qt6 and other work in progress names, so only
	# plain dotted numbers are considered
	tag=$(git tag --sort=-v:refname | grep -E '^v?[0-9]+(\.[0-9]+)+$' | head -n 1)
	git checkout -q "$tag"
	git submodule update --init --depth 1 deps/libmpv deps/singleapplication
	echo "${tag#v}" > ~/version
)
echo "Stremio version: $(cat ~/version)"

echo "Getting the streaming server..."
echo "---------------------------------------------------------------"
# the shell does not ship server.js, its URL is pinned per tag in
# server-url.txt so the server always matches the shell
SERVER_URL=$(cat "$BUILD_DIR/shell/server-url.txt")
curl -sSfL --retry 30 --retry-connrefused "$SERVER_URL" \
	-o "$BUILD_DIR/shell/server.js"

echo "Building the shell..."
echo "---------------------------------------------------------------"
mkdir -p "$BUILD_DIR/build" && (
	cd "$BUILD_DIR/build"
	cmake -G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$BUILD_DIR/staging" \
		"$BUILD_DIR/shell"
	make -j"$(nproc)"
	make install
)

# cmake only installs the binary itself, the streaming server and the desktop
# entry are installed by the shell's release.makefile which we cannot use
# because it also downloads server.js
STAGING=$BUILD_DIR/staging/opt/stremio
cp -v "$BUILD_DIR/shell/server.js" "$STAGING/server.js"
cp -v "$BUILD_DIR/shell/smartcode-stremio.desktop" "$STAGING/smartcode-stremio.desktop"

echo "Preparing AppDir..."
echo "---------------------------------------------------------------"
mkdir -p ./AppDir/bin
cp -rv "$STAGING"/. ./AppDir/bin/

# the desktop entry and a single icon go at the top level of the AppDir, which
# is where quick-sharun looks for them, the tray icon falls back to the one
# embedded in the shell so no icon theme is needed
cp -v ./AppDir/bin/smartcode-stremio.desktop ./AppDir
cp -v "$BUILD_DIR/shell/images/stremio.svg" ./AppDir/smartcode-stremio.svg

# stremio's own updater replaces itself with the upstream AppImage when it
# sees that it runs from /tmp/.mount_*, which is where uruntime mounts this
# AppImage, so that check is neutralized and quick-sharun's self-updater is
# used instead. The replacement has to be the same length or the ELF breaks
if grep -aq -m 1 '/tmp/\.mount_' ./AppDir/bin/stremio; then
	sed -i -e 's|/tmp/\.mount_|/nonexistent|' ./AppDir/bin/stremio
fi
