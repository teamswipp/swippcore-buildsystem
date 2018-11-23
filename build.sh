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

repo="https://github.com/teamswipp/swippcore.git"
return_code=0

pushd () {
	command pushd "$@" > /dev/null
}

popd () {
	command popd "$@" > /dev/null
}

cleanup() {
	kill $(jobs -p) &> /dev/null
}

choose_flavours() {
	current_distro=$(lsb_release -d | sed 's/Description:\s//g')

	dialog --stdout --checklist "Please choose which wallet versions of Swipp you would like to build:" \
	       12 60 4 linux "Linux [$current_distro]" 0 \
	       osx   "MacOS X [10.11 (El Capitan)]" 0 \
	       win32 "Windows [32 bit]" 0 \
	       win64 "Windows [64 bit]" 0

	if [ $? -eq 1 ]; then
		exit 1
	fi

	return $?
}

clone() {
	if [ ! -d "build-$1" ]; then
		mkdir build-linux
	fi

	if [ ! -d "build-$1/swippcore" ]; then
		clear
		git clone $repo build-$1/swippcore
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

# percentage_so_far, logfile, errfile, logfile_max_len, jobs, pid
build_dialog() {
	local -n arr=$5
	range=($1)
	progress=$(cat $2 | wc -l)
	span=$((${range[-1]}-${range[0]}))

	for i in $(eval echo {0..${#arr[@]}}); do
		if [ ${arr[$i]} = "_" ]; then
			break
		fi
	done

	while (( $progress < ${4} )); do
		percent=$(((100*$progress)/$4))
		percent=$(if (($percent > 100)); then echo 100; else echo $percent; fi) # clamp
		arr[$i]="-$percent"
		clear

		dialog --title "Building Linux flavour [$progress/${4}]" --mixedgauge " " 22 70 \
		       $((${range[0]}+($span*$percent)/100)) \
		       "Creating build files from QMAKE file" ${arr[0]} \
		       "Building native QT wallet" ${arr[1]} \
		       "Building native console wallet" ${arr[2]} \
		       "Generating cross-platform QT wallet" ${arr[3]} \
		       "Generating cross-platform console wallet" ${arr[4]}

		if [ ! -d "/proc/$6" ]; then
			sleep 0.5
			return $return_code
		fi

		sleep 5

		if [ -f "$3" ] && [ -s "$3" ]; then
			# Includes some general cases we don't want to count as errors
			if (( $(cat $3 | grep -v "Project MESSAGE: INFO:" | grep -v " Warning:" \
			    | grep -v "^ar:" | wc -l) > 0 )); then
			    kill $6 &> /dev/null
				return 1
			fi
		fi

		progress=$(cat $2 | wc -l)
	done

	wait $6
	return $return_code
}

trap cleanup EXIT
dialog --textbox build-components/welcome.txt 22 70
choices=$(choose_flavours)

if [[ $choices =~ "linux" ]]; then
	clone linux
	install_dependencies build-essential make g++ libboost-all-dev libssl1.0-dev libdb5.3++-dev \
	                     libminiupnpc-dev libz-dev libcurl4-openssl-dev qt5-default \
	                     qttools5-dev-tools
	pushd build-linux
	pushd swippcore
	pjobs=(_ 8 8 8 8)
	{
		qmake -Wnone swipp.pro 2> ../qmake.error 1> ../qmake.log
		return_code=$?
	} &
	build_dialog "$(echo {0..5})" ../qmake.log ../qmake.error 6 pjobs $!
	pjobs[0]=$(if (($? == 0)); then echo 3; else echo 1; fi)

	pjobs[1]="_"
	share/genbuild.sh build/build.h
	todo=$(make -n 2> /dev/null | wc -l)
	{
		make -j$(($(nproc)/2)) 2> ../make-qt.error 1> ../make-qt.log # Use half
		return_code=$?
	} &
	build_dialog "$(echo {5..50})" ../make-qt.log ../make-qt.error $todo pjobs $!
	pjobs[1]=$(if (($? == 0)); then echo 3; else echo 1; fi)

	pushd src
	pjobs[2]="_"
	todo=$(make -n -f makefile.unix 2> /dev/null | grep "^\(cc\|g++\)" | wc -l)
	{
		make -j$(($(nproc)/2)) -f makefile.unix 2> ../../make-console.error 1> ../../make-console.log # Use half
		return_code=$?
	} &
	build_dialog "$(echo {50..80})" ../../make-console.log ../../make-console.error $todo pjobs $!
	pjobs[2]=$(if (($? == 0)); then echo 3; else echo 1; fi)

	popd
	popd
	pjobs[3]="_"
	{
		../build-components/swipp-linuxdeployqt.sh swippcore swipp-qt 2> linuxdeployqt-qt.log 1> /dev/null
		return_code=$?
	} &
	build_dialog "$(echo {80..90})" linuxdeployqt-qt.log ".nolog" 85 pjobs $! # hard coded expected job size
	pjobs[3]=$(if (($? == 0)); then echo 3; else echo 1; fi)

	pjobs[4]="_"
	{
		../build-components/swipp-linuxdeployqt.sh swippcore/src swippd 2> linuxdeployqt-qt.log 1> /dev/null
		return_code=$?
	} &
	build_dialog "$(echo {90..100})" linuxdeployqt-console.log ".nolog" 85 pjobs $! # hard coded expected job size
	pjobs[4]=$(if (($? == 0)); then echo 3; else echo 1; fi)
fi
