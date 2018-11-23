#!/bin/bash
#
# Copyright (c) 2017-2018 The Swipp developers
#
# Distributed under the MIT/X11 software license, see the accompanying file COPYING or http://www.opensource.org/licenses/mit-license.php.
#
# General build script for Swipp, supporting different platforms and
# flavours.

repo="https://github.com/teamswipp/swippcore.git"

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

# percentage_so_far, logfile, errfile, logfile_max_len, jobs
build_dialog() {
	local -n arr=$5
	progress=0

	for i in $(eval echo {0..${#arr[@]}}); do
		if [ ${arr[$i]} = "_" ]; then
			break
		fi
	done

	while (( $progress < ${4} )); do
		progress=$(cat $2 | wc -l)
		arr[$i]="-$(((100*$progress)/$4))"
		clear

		dialog --title "Building Linux flavour" --mixedgauge " " 22 70 $1 \
		       "Creating build files from QMAKE file" ${arr[0]} \
		       "Building native QT wallet" ${arr[1]} \
		       "Building native console wallet" ${arr[2]} \
		       "Generating cross-platform QT wallet" ${arr[3]} \
		       "Generating cross-platform console wallet" ${arr[4]}
		sleep 5

		# Includes some general cases we don't want to count as errors
		if (( $(cat $3 | grep -v "Project MESSAGE: INFO:" | grep -v " Warning:" \
		    | grep -v "^ar:" | wc -l) > 0 )); then
			return 1
		fi
	done

	return 0
}

trap cleanup EXIT
dialog --textbox build-components/welcome.txt 22 70
choices=$(choose_flavours)

if [[ $choices =~ "linux" ]]; then
	clone linux
	install_dependencies build-essential make g++ libboost-all-dev libssl1.0-dev libdb5.3++-dev \
	                     libminiupnpc-dev libz-dev libcurl4-openssl-dev qt5-default \
	                     qttools5-dev-tools
	pushd build-linux/swippcore
	pjobs=(_ 8 8 8 8)
	qmake -Wnone swipp.pro 2> ../qmake.error 1> ../qmake.log &
	build_dialog 0 ../qmake.log ../qmake.error 0 pjobs
	pjobs[0]=$(if (($? == 0)); then echo 3; else echo 2; fi)

	pjobs[1]="_"
	share/genbuild.sh build/build.h
	make -j$(($(nproc)/2)) 2> ../make-qt.error 1> ../make-qt.log & # Use half
	build_dialog 20 ../make-qt.log ../make-qt.error $(make -n 2> /dev/null | wc -l) pjobs
	pjobs[1]=$(if (($? == 0)); then echo 3; else echo 2; fi)

	pushd src
	pjobs[2]="_"
	make -j$(($(nproc)/2)) -f makefile.unix 2> ../../make-console.error 1> ../../make-console.log & # Use half
	build_dialog 40 ../../make-console.log ../../make-console.error $(make -n -f makefile.unix 2> /dev/null | wc -l) pjobs
	pjobs[2]=$(if (($? == 0)); then echo 3; else echo 2; fi)

	popd
	popd
	pjobs[3]="_"
	./build-components make -j$(($(nproc)/2)) -f makefile.unix 2> ../../make-console.error 1> ../../make-console.log & # Use half
	build_dialog 40 ../../make-console.log ../../make-console.error $(make -n -f makefile.unix 2> /dev/null | wc -l) pjobs
	pjobs[2]=$(if (($? == 0)); then echo 3; else echo 2; fi)
fi
