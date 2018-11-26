#!/bin/bash
#
# Copyright (c) 2017-2018 The Swipp developers
#
# This file is part of The Swipp Build System.
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
# General build script for Swipp, supporting different platforms and
# flavours.

swipp_repo="https://github.com/teamswipp/swippcore.git"
mxe_repo="https://github.com/mxe/mxe.git"
return_code=0

pushd () {
	command pushd "$@" > /dev/null
}

popd () {
	command popd "$@" > /dev/null
}

cleanup() {
	kill $(jobs -p) &> /dev/null
	clear
}

choose_flavours() {
	current_distro=$(lsb_release -d | sed 's/Description:\s//g')

	dialog --stdout --checklist "Please choose which wallet flavour of Swipp you would like to build:" \
	       12 60 4 linux "Linux [$current_distro]" 0 \
	       osx   "MacOS X [10.11 (El Capitan)]" 0 \
	       win32 "Windows [32 bit]" 0 \
	       win64 "Windows [64 bit]" 0

	if [ $? -eq 1 ]; then
		exit 0
	fi

	return $?
}

version="none"

choose_tags() {
	if [ $version -ne "none" ]; then
		return
	fi

	tags="$(git tag) master"

	for i in $tags; do
		if [ $i = "master" ]; then
			tags_arguments=($i "Master version ($(git rev-parse --short master))" off "${tags_arguments[@]}")
		else
			tags_arguments=($i "Tagged release $i" off "${tags_arguments[@]}")
		fi
	done

	tags_arguments[5]=on

	dialog --stdout --radiolist "Please choose which versions of Swipp you would like to build:" \
	       17 54 10 "${tags_arguments[@]}"

	if [ $? -eq 1 ]; then
		exit 0
	fi

	return $?
}

checkout() {
	if [ $version -eq "none" ]; then
		version=master
	fi

	clear
	git checkout $version > /dev/null

	if (($? != 0)); then
		dialog --msgbox "Failed to check out $version in repository $3" 7 70
		exit 1
	fi
}

#buildir_name, clone_dir, repo
clone() {
	if [ ! -d "build-$1" ]; then
		mkdir build-$1
	fi

	if [ ! -d "build-$1/$2" ]; then
		clear
		git clone $3 build-$1/$2

		if (($? != 0)); then
			dialog --msgbox "Failed to clone repository $3" 7 70
			exit 1
		fi
	fi
}

install_dependencies() {
	for i in $@; do
		dpkg -l $i &> /dev/null

		if [ $? -eq 1 ]; then
			missingdeps+=" $i"
		fi
	done

	missingdeps=${missingdeps:1}

	if [ -n "$missingdeps" ]; then
		dialog --msgbox "The dependencies '$missingdeps' are missing and need to be installed " \
		       "before running this script." 8 70
		exit 1
	fi
}

# percentage_span, logfile, errfile, logfile_max_len, jobs, pid
build_dialog() {
	range=($1)
	progress=$(eval "cat $2 | wc -l")
	span=$((${range[-1]}-${range[0]}))

	for i in $(eval echo {0..${#pjobs[@]}}); do
		if [ "${pjobs[$i]}" = "_" ]; then
			break
		fi
	done

	if [ $progress -eq 0 ]; then
		pjobs[$i]="3"
		dialog --title "$title" --mixedgauge " " 22 70 ${range[-1]} "${pjobs[@]}"
	fi

	while (( $progress < ${4} )); do
		percent=$(((100*$progress)/$4))
		percent=$(if (($percent > 100)); then echo 100; else echo $percent; fi) # clamp
		pjobs[$i]="-$percent"
		clear

		dialog --title "$title [$progress/${4}]" --mixedgauge " " 22 70 \
		       $((${range[0]}+($span*$percent)/100)) "${pjobs[@]}"

		if [ ! -d "/proc/$5" ]; then
			sleep 0.5
			return $return_code
		fi

		sleep 5

		if [ -f "$3" ] && [ -s "$3" ]; then
			if (( $(cat $3 | grep -E "error|ERROR" | wc -l) > 0 )); then
			    kill $6 &> /dev/null
				return 1
			fi
		fi

		progress=$(eval "cat $2 | wc -l")
	done

	wait $6
	return $return_code
}

# step, percentage_span, logfile, errfile
build_step() {
	pjobs[$1]="_"
	touch $3 $4

	if [ -n "${todo[0]}" ] && [ "${todo[0]}" -eq "${todo[0]}" ] 2> /dev/null; then
		todores="${todo[0]}"
	else
		todores=$(eval ${todo[0]} | wc -l)
	fi

	{
		eval ${todo[1]}
		return_code=$?
	} &

	build_dialog "$2" $3 $4 $todores $!
	pjobs[$1]=$(if (($? == 0)); then echo 3; else echo 1; fi)
}

trap cleanup EXIT
dialog --textbox build-components/welcome.txt 22 70
choices=$(choose_flavours)

if [[ $choices =~ "linux" ]]; then
	title="Building Linux flavour"
	pjobs=("Creating build files from QMAKE file"     8 \
	       "Building native QT wallet"                8 \
	       "Building native console wallet"           8 \
	       "Generating cross-platform QT wallet"      8 \
	       "Generating cross-platform console wallet" 8)

	install_dependencies build-essential make g++ libboost-all-dev libssl1.0-dev libdb5.3++-dev \
	                     libminiupnpc-dev libz-dev libcurl4-openssl-dev qt5-default \
	                     qttools5-dev-tools

	clone linux swippcore $swipp_repo
	pushd build-linux
	pushd swippcore
	version=$(choose_tags)
	checkout

	todo=(6 "qmake -Wnone swipp.pro 2> ../qmake.error 1> ../qmake.log")
	build_step 1 "$(echo {0..5})" ../qmake.log ../qmake.error

	sh share/genbuild.sh build/build.h
	todo=("make -n 2> /dev/null" "make -j$(($(nproc)/2)) 2> ../make-qt.error 1> ../make-qt.log")
	build_step 3 "$(echo {5..50})" ../make-qt.log ../make-qt.error

	pushd src
	todo=("make -n -f makefile.unix 2> /dev/null | grep \"^\(cc\|g++\)\"" \
	      "make -j$(($(nproc)/2)) -f makefile.unix 2> ../../make-console.error 1> ../../make-console.log")
	build_step 5 "$(echo {50..80})" ../../make-console.log ../../make-console.error

	popd
	popd
	todo=(85 "../build-components/swipp-linuxdeployqt.sh swippcore swipp-qt 2> linuxdeployqt-qt.log 1> /dev/null")
	build_step 7 "$(echo {80..90})" linuxdeployqt-qt.log linuxdeployqt-qt.error

	todo=(85 "../build-components/swipp-linuxdeployqt.sh swippcore/src swippd 2> linuxdeployqt-console.log 1> /dev/null")
	build_step 7 "$(echo {90..100})" linuxdeployqt-console.log linuxdeployqt-console.error
fi

if [[ $choices =~ "win32" || $choices =~ "win64" ]]; then
	title="Preparing Windows dependencies"
	pjobs=("Building GCC and build environment" 8 \
	       "Building QT base dependencies"      8 \
	       "Building QT tools dependencies"     8 \
	       "Building CURL dependency"           8)

	clone win32 swippcore $swipp_repo
	pushd build-win32
	pushd swippcore
	version=$(choose_tags)
	checkout
	popd
	clone win32 mxe $mxe_repo
	pushd mxe

	arg_mxe_path=.
	arg_target=i686-w64-mingw32.static
	targets="i686-w64-mingw32.static x86_64-w64-mingw32.static"
	source "../../build-components/cross-compile-win.sh"

	todo=("make -n MXE_TARGETS=\"$targets\" cc | grep -o \"\[done\]\"" \
	      "make MXE_TARGETS=\"$targets\" -j$(($(nproc)/2)) cc 2> ../makedep-cc.error 1> ../makedep-cc.log")
	build_step 1 "$(echo {0..30})" ../makedep-cc.log ../makedep-cc.error

	todo=("make -n MXE_TARGETS=\"$targets\" qtbase | grep -o \"\[done\]\"" \
	      "make MXE_TARGETS=\"$targets\" -j$(($(nproc)/2)) qtbase 2> ../makedep-qtbase.error 1> ../makedep-qtbase.log")
	build_step 3 "$(echo {30..50})" ../makedep-qtbase.log ../makedep-qtbase.error

	todo=("make -n MXE_TARGETS=\"$targets\" qttools | grep -o \"\[done\]\"" \
	      "make MXE_TARGETS=\"$targets\" -j$(($(nproc)/2)) qttools 2> ../makedep-qttools.error 1> ../makedep-qttools.log")
	build_step 5 "$(echo {50..80})" ../makedep-qtbase.log ../makedep-qtbase.error

	todo=("make -n MXE_TARGETS=\"$targets\" curl | grep -o \"\[done\]\"" \
	      "make MXE_TARGETS=\"$targets\" -j$(($(nproc)/2)) curl 2> ../makedep-curl.error 1> ../makedep-curl.log")
	build_step 7 "$(echo {80..100})" ../makedep-curl.log ../makedep-curl.error
fi
