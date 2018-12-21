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
# Small script to create MacOS X DMG archives

# 1312 instead of 1024 bytes. Seems some space needs to be reserved.
# In the end it does not matter much, as the file is compressed.
dd if=/dev/zero of=$2.dmg bs=1312 count=$(du  -s $1 | cut -f1)

/sbin/mkfs.hfsplus -v "Swipp" $2.dmg
hfsplus $2.dmg addall $1
hfsplus $2.dmg symlink " " /Applications
dmg dmg $2.dmg $2-compressed.dmg
mv -f $2-compressed.dmg $2.dmg
