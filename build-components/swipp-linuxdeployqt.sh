#!/bin/bash
#
# This file is part of The Swipp Build System.
#
# Copyright (c) 2017-2018 The Swipp developers
#
# The Swipp Build System is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# The Swipp Build System is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Swipp Build System. If not, see
# <https://www.gnu.org/licenses/>.
#
# Recipe for creating a Swipp QT AppImage package
#
# $1: Location of Swipp executable
# $2: Executable name

if [[ $# -lt 2 ]]; then
	echo "Please specify the full location of the swipp executable and executable name"
	exit 0
fi

if [ -f "$2-x86_64.AppImage" ]; then
	exit 0
fi

# Create AppDir FHS-like stucture
mkdir -p $2.AppDir/usr $2.AppDir/usr/bin

# Used by AppImageKit-checkrt (see below)
mkdir -p $2.AppDir/usr/optional $2.AppDir/usr/optional/libstdc++

# Copy files into empty AppDir
cp $1/$2 $2.AppDir/usr/bin

# Get and run linuxdeployqt
wget -c https://github.com/probonopd/linuxdeployqt/releases/download/continuous/linuxdeployqt-continuous-x86_64.AppImage
chmod a+x linuxdeployqt-continuous-x86_64.AppImage

# Prepare AppDir
./linuxdeployqt-continuous-x86_64.AppImage --appimage-extract
./squashfs-root/usr/bin/linuxdeployqt $2.AppDir/usr/bin/$2 -bundle-non-qt-libs

# Workaround to increase compatibility with older systems; see https://github.com/darealshinji/AppImageKit-checkrt for details
rm $2.AppDir/AppRun
cp /usr/lib/x86_64-linux-gnu/libstdc++.so.6 $2.AppDir/usr/optional/libstdc++/
wget -c https://github.com/darealshinji/AppImageKit-checkrt/releases/download/continuous/exec-x86_64.so -O $2.AppDir/usr/optional/exec.so
wget -c https://github.com/darealshinji/AppImageKit-checkrt/releases/download/continuous/AppRun-patched-x86_64 -O $2.AppDir/AppRun
chmod a+x $2.AppDir/AppRun

# Copy in desktop descriptor and icon
printf "[Desktop Entry]\nType=Application\nName=swipp-qt\nGenericName=swipp-qt\nComment=Store and transfer Swipp coins\nIcon=swipp\nExec=../usr/bin/$2\nTerminal=false\nCategories=Network;Finance;" > $2.AppDir/swipp-qt.desktop
cp swippcore/src/qt/res/icons/swipp.png $2.AppDir/

# Manually invoke appimagetool so that the modified AppRun stays intact
PATH=$(readlink -f ./squashfs-root/usr/bin):$PATH
./squashfs-root/usr/bin/appimagetool $2.AppDir $2-x86_64.AppImage
