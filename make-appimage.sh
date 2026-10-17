#!/bin/sh

set -eu

ARCH=$(uname -m)
export ARCH
export OUTPATH=./dist
export ADD_HOOKS="self-updater.hook:fix-namespaces.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export DEPLOY_QT=1
export QT_DIR=qt
export DEPLOY_QT_WEB_ENGINE=1
export DEPLOY_QML=1
export DEPLOY_PIPEWIRE=1

# the shell imports WebEngine from QML instead of linking it, so the helper has
# to be passed explicitly for its libraries to be collected
# node and ffmpeg are spawned by the shell from the directory of the node
# binary, which is bin/ in the AppDir
quick-sharun \
	./AppDir/bin/stremio                  \
	/usr/bin/node                         \
	/usr/bin/ffmpeg                       \
	/usr/bin/ffprobe                      \
	/usr/lib/qt/libexec/QtWebEngineProcess

# Turn AppDir into AppImage
quick-sharun --make-appimage

# Test the app for 12 seconds, if the test fails due to the app
# having issues running in the CI use --simple-test instead
quick-sharun --test ./dist/*.AppImage
