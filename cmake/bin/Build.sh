#!/bin/bash
#set -x

# When the script directory is not set then
if [[ -z "${SCRIPT_DIR}" ]] ; then
	# Get the bash script directory.
	SCRIPT_DIR="$(realpath "$(cd "$( dirname "${BASH_SOURCE[0]}")" && pwd)/../..")"
	exit 1
fi

# Define and use some foreground colors values when not running CI-jobs.
if [[ ${CI} ]] ; then
	fg_black="";
	fg_red=""
	fg_green=""
	fg_yellow=""
	fg_blue=""
	fg_magenta=""
	fg_cyan=""
	fg_white=""
	fg_reset=""
else
	# shellcheck disable=SC2034
	fg_black="$(tput setaf 0)"
	fg_red="$(tput setaf 1)"
	# shellcheck disable=SC2034
	fg_green="$(tput setaf 2)"
	fg_yellow="$(tput setaf 3)"
	# shellcheck disable=SC2034
	fg_blue="$(tput setaf 4)"
	fg_magenta="$(tput setaf 5)"
	fg_cyan="$(tput setaf 6)"
	# shellcheck disable=SC2034
	fg_white="$(tput setaf 7)"
	fg_reset="$(tput sgr0)"
fi

# Writes to stderr.
#
function WriteLog()
{
	# shellcheck disable=SC2034
	# shellcheck disable=SC2124
	local LAST_ARG="${@: -1}"
	local LAST_CH="${LAST_ARG: 0-1}"
	local FIRST_CH="${LAST_ARG:0:1}"
	# Set color based on first character of the string.
	case "${FIRST_CH}" in
		"-")
			local COLOR="${fg_magenta}"
			;;
		"=")
			local COLOR="${fg_yellow}"
			;;
		*)
			local COLOR=""
			;;
	esac
	case "${LAST_CH}" in
		"!")
			local COLOR="${fg_red}"
			;;
		".")
			local COLOR="${fg_cyan}"
			;;
	esac
	echo -n "${COLOR}" 1>&2;
	# shellcheck disable=SC2068
	echo ${@} 1>&2;
	echo -n "${fg_reset}" 1>&2;
}

# Amount of CPU cores to use for compiling.
CPU_CORES_TO_USE="$(($(nproc --all) -1))"
# Get the target OS.
SF_TARGET_OS="$(uname -o)"

# Change to the scripts directory to operated from when script is called from a different location.
if ! cd "${SCRIPT_DIR}" ; then
	WriteLog "Change to operation directory '${SCRIPT_DIR}' failed!"
	exit 1;
fi

# Prints the help to stderr.
#
function ShowHelp()
{
	echo "Usage: ${0} [<options>] <sub-dir> [<target>]
  -d, --debug    : Debug: Show executed commands rather then executing them.
  -p, --packages : Install prerequisite Linux packages using 'apt' for now.
  -c, --clean    : Cleans build targets first (adds build option '--clean-first')
  -C, --wipe     : Wipe clean the targeted cmake-build-<build-type>-<compiler-type>
  -t, --test     : Add tests to the build configuration.
  -w, --windows  : Cross compile Windows on Linux using MinGW.
  -m, --make     : Create build directory and makefiles only.
  -b, --build    : Build target only.
  -v, --verbose  : CMake verbose enabled during CMake make (level VERBOSE).
  --clion        : Use CLion CMake tool and compilers (Windows).
  --studio       : Build using Visual Studio
  --gitlab-ci    : Simulate CI server by setting CI_SERVER environment variable (disables colors i.e.).
  Where <sub-dir> is:
    '.', 'com', 'rt-shared-lib/app', 'rt-shared-lib/iface',
    'rt-shared-lib/impl-a', 'rt-shared-lib', 'custom-ui-plugin'
  When the <target> argument is omitted it defaults to 'all'.
  The <sub-dir> is also the directory where cmake will create its 'cmake-build-???' directory.

  Examples:
    Make/Build all projects: ${0} -mb .
    Same as above: ${0} -mb . all
    Clean all projects: ${0} . clean
    Install all projects: ${0} . install
    Show all projects to be build: ${0} . help
    Build 'sf-misc' project in 'com' sub-dir only: ${0} -b . sf-misc
    Build 'com' project and all sub-projects: ${0} -b com
    Build 'rt-shared-lib' project and all sub-projects: ${0} -b rt-shared-lib
	"
}

# Install needed packages depending in the Windows(cygwin) or Linux environment it is called from.
#
function InstallPackages()
{
	WriteLog "About to install required packages for ($1)..."
	if [[ "$1" == "GNU/Linux/x86_64" || "$1" == "GNU/Linux/arm64" || "$1" == "GNU/Linux/aarch64" ]] ; then
		if ! sudo apt install --install-recommends cmake doxygen graphviz libopengl0 libgl1-mesa-dev libxkbcommon-dev \
			libxkbfile-dev libvulkan-dev libssl-dev exiftool ; then
			WriteLog "Failed to install 1 or more packages!"
			exit 1
		fi
	elif [[ "$1" == "GNU/Linux/x86_64/Cross" ]] ; then
		if ! sudo apt install --install-recommends mingw-w64 cmake doxygen graphviz wine exiftool ; then
			WriteLog "Failed to install 1 or more packages!"
			exit 1
		fi
	elif [[ "$1" == "Cygwin/x86_64" ]] ; then
		if ! apt-cyg install doxygen graphviz perl-Image-ExifTool ; then
			WriteLog "Failed to install 1 or more Cygwin packages (Try the Cygwin setup tool when elevation is needed) !"
			exit 1
		fi
	else
		# shellcheck disable=SC2128
		WriteLog "Unknown '$1' environment selection passed to function '${FUNCNAME}' !"
	fi
}

# Detect windows using the cygwin 'uname' command.
if [[ "${SF_TARGET_OS}" == "Cygwin" ]] ; then
	WriteLog "- Windows OS detected through Cygwin and Qt expected on drive 'P:'"
	export SF_TARGET_OS="Cygwin"
	FLAG_WINDOWS=true
	# Set the directory the local QT root.
	LOCAL_QT_ROOT="/cygdrive/p/Qt"
	EXEC_SCRIPT="$(mktemp --suffix .bat)"
elif [[ "${SF_TARGET_OS}" == "GNU/Linux" ]] ; then
	WriteLog "- Linux detected ."
	export SF_TARGET_OS="GNU/Linux"
	FLAG_WINDOWS=false
	# Set the directory the local QT root.
	LOCAL_QT_ROOT="${HOME}/lib/Qt"
	EXEC_SCRIPT="$(mktemp --suffix .sh)"
	chmod +x "${EXEC_SCRIPT}"
# Windows Bash from Git install.
elif [[ "${SF_TARGET_OS}" == "Msys" ]] ; then
	WriteLog "- Windows OS detected through Msys and Qt expected on drive 'P:'"
	export SF_TARGET_OS="Msys"
	FLAG_WINDOWS=true
	# Set the directory the local QT root.
	LOCAL_QT_ROOT="/p/Qt"
	EXEC_SCRIPT="$(mktemp --suffix .bat)"
else
	WriteLog "Targeted OS '${SF_TARGET_OS}' not supported!"
fi

# No arguments at show help and bailout.
if [[ $# == 0 ]]; then
	ShowHelp
	exit 1
fi

# Initialize arguments and switches.
FLAG_DEBUG=false
FLAG_CONFIG=false
FLAG_BUILD=false
FLAG_WIPE_DIR=false
FLAG_CLION=false
# Flag for cross compiling for Windows from Linux.
FLAG_CROSS_WINDOWS=false
# Flag for when using Visual Studio
FLAG_VISUAL_STUDIO=false
# Initialize the config options.
CONFIG_OPTIONS="-L"
CONFIG_OPTIONS=""
# Initialize the build options.
BUIlD_OPTIONS=
# Initialize the target.
TARGET="all"
# Additional Cmake make command line options.
declare -A CMAKE_DEFS
# Default profile is debug.
CMAKE_DEFS['CMAKE_BUILD_TYPE']='Debug'
# Default build dynamic libraries.
CMAKE_DEFS['BUILD_SHARED_LIBS']='ON'
#
CMAKE_DEFS['CMAKE_COLOR_DIAGNOSTICS']='ON'
# Parse options.
TEMP=$(getopt -o 'dhcCbtmwpv' --long \
	'clion,help,debug,verbose,packages,wipe,clean,make,build,test,windows,studio,gitlab-ci' \
	-n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]] ; then
	ShowHelp
	exit 1
fi
eval set -- "$TEMP" ; unset TEMP
while true; do
	case $1 in

		--clion)
			FLAG_CLION=true
			shift 1
			continue
			;;

		--gitlab-ci)
			export CI_SERVER="yes"
			shift 1
			continue
			;;

		-h|--help)
			ShowHelp
			exit 0
			;;

		-d|--debug)
			WriteLog "- Script debugging is enabled"
			FLAG_DEBUG=true
			shift 1
			continue
			;;

		-v|--verbose)
			WriteLog "- CMake verbose level set"
			CMAKE_DEFS['CMAKE_MESSAGE_LOG_LEVEL']='VERBOSE'
			shift 1
			continue
			;;

		-p|--packages)
			if [[ ${FLAG_CROSS_WINDOWS} == true ]] ; then
				InstallPackages "${SF_TARGET_OS}/$(uname -m)/Cross"
			else
				InstallPackages "${SF_TARGET_OS}/$(uname -m)"
			fi
			exit 0
			;;

		-C|--wipe)
			WriteLog "- Wipe clean targeted build directory commenced"
			# Set the flag to wipe the build directory first.
			FLAG_WIPE_DIR=true
			shift 1
			continue
			;;

		-c|--clean)
			WriteLog "- Clean first enabled"
			BUIlD_OPTIONS="${BUIlD_OPTIONS} --clean-first"
			shift 1
			continue
			;;

		-m|--make)
			WriteLog "- Create build directory and makefiles"
			FLAG_CONFIG=true
			shift 1
			continue
			;;

		-b|--build)
			WriteLog "- Build the given target"
			FLAG_BUILD=true
			shift 1
			continue
			;;

		-t,--test)
			WriteLog "Include test builds."
			CMAKE_DEFS['SF_BUILD_TESTING']='ON'
			shift 1
			continue
			;;

		-w|--windows)
			if ! ${FLAG_WINDOWS} ; then
				WriteLog "- Cross compile for Windows"
				if [[ ! ${FLAG_WINDOWS} = true ]] ; then
					FLAG_CROSS_WINDOWS=true
				fi
			else
				WriteLog "Ignoring Cross compile when in Windows"
			fi
			shift 1
			continue
			;;

		--studio)
			if ${FLAG_WINDOWS} ; then
				WriteLog "- Using Visual Studio Compiler"
				FLAG_VISUAL_STUDIO=true
			else
				WriteLog "-  Ignoring Visual Studio switch when in Linux"
			fi
			shift 1
			continue
			;;

		'--')
			shift
			break
		;;

		*)
			echo 'Internal error!' >&2
			exit 1
		;;
	esac
done

# Get the arguments in an array.
argument=()
while [ $# -gt 0 ] && ! [[ "$1" =~ ^- ]]; do
	argument=("${argument[@]}" "$1")
	shift
done

# First argument is mandatory.
if [[ -z "${argument[0]}" ]]; then
	WriteLog "Mandatory target (sub-)directory not passed!"
	ShowHelp
	exit 1
fi

# Initialize variables.
SOURCE_DIR="${argument[0]}"
# Initialize the first part of the build directory depending on the build type (Debug, Release etc.).
BUILD_SUBDIR="cmake-build-${CMAKE_DEFS['CMAKE_BUILD_TYPE'],,}"
#
# Assemble CMake build directory depending on OS and passed options.
#
# When Windows is the OS running Cygwin.
if ${FLAG_WINDOWS} = true ; then
	# Set the build-dir for the cross compile.
	if ${FLAG_VISUAL_STUDIO} = true ; then
		BUILD_SUBDIR="${BUILD_SUBDIR}-msvc"
	else
		BUILD_SUBDIR="${BUILD_SUBDIR}-mingw"
	fi
# When a Linux is the OS.
else
	# Set the build-dir for the cross compile.
	if ${FLAG_CROSS_WINDOWS} ; then
		# Set the CMake define.
		CMAKE_DEFS['SF_CROSS_WINDOWS']='ON'
		BUILD_SUBDIR="${BUILD_SUBDIR}-gw"
	else
		BUILD_SUBDIR="${BUILD_SUBDIR}-gnu"
	fi
fi

# When second argument is not given all targets are build as the default.
if [[ -n "${argument[1]}" ]]; then
	TARGET="${argument[1]}"
fi

# Check if wiping can be performed.
if [[ "${TARGET}" == @(help|install) && ${FLAG_WIPE_DIR} == true ]] ;  then
	FLAG_WIPE_DIR=false
	WriteLog "Wiping clean with target '${TARGET}' not possible!"
fi

# When the Wipe flag is set.
if ${FLAG_WIPE_DIR} ; then
	WriteLog "- Wiping clean build-dir '${RM_SUBDIR}/${BUILD_SUBDIR}'"
	RM_CMD="rm --verbose --recursive --one-file-system --interactive=never"
	RM_SUBDIR="${SCRIPT_DIR}"
	if [[ -n "${TARGET}" && "${TARGET}" && "${TARGET}" != "all" ]] ; then
		RM_SUBDIR="${RM_SUBDIR}/${TARGET}"
	fi
	# Check if only build flag is specified.
	if ! ${FLAG_CONFIG} && ${FLAG_BUILD} ; then
		WriteLog "Only building is impossible after wipe!"
		FLAG_BUILD=false
	fi
	if ${FLAG_DEBUG} ; then
		WriteLog "@${RM_CMD} ${RM_SUBDIR}/${BUILD_SUBDIR}/*"
	else
		# Check if the build directory really exists checking an expected subdir.
		if [[ -d "${RM_SUBDIR}/${BUILD_SUBDIR}" ]] ; then
			# Remove all content from the build directory also the hidden ones skipping '.' and '..'
			${RM_CMD} "${RM_SUBDIR}/${BUILD_SUBDIR}/"..?* "${RM_SUBDIR}/${BUILD_SUBDIR}/".[!.]* "${RM_SUBDIR}/${BUILD_SUBDIR}/"* > /dev/null
		fi
	fi
fi

# Configure Build generator depending .
if ${FLAG_WINDOWS} ; then
	# Find Clion CMake executable.
	if ${FLAG_CLION} ; then
		# Try finding the CLion cmake in Windows.
		# shellcheck disable=SC2154
		CMAKE_BIN="$(ls -d "$(cygpath -u "${ProgramW6432}")/JetBrains/CLion"*/bin/cmake/win/bin/cmake.exe)"
		# Check if the file exists.
		if [[ ! -f "${CMAKE_BIN}" ]] ; then
			WriteLog "CLion cmake was not found!"
			exit 1
		fi
		# Also set the path prefix so the CLion compilers are selected together with the CMake executable.
		PATH_PREFIX="$(ls -d "$(cygpath -u "${ProgramW6432}")/JetBrains/CLion"*/bin/mingw/bin)"
	# Otherwise use QT's CMake executable.
	else
		CMAKE_BIN="${LOCAL_QT_ROOT}/Tools/CMake_64/bin/cmake.exe"
		# Check if the file exists.
		if [[ ! -f "${CMAKE_BIN}" ]] ; then
			WriteLog "QT cmake '${CMAKE_BIN}' was not found!"
			exit 1
		fi
		# Also set the path prefix so the CLion compilers are selected together with the CMake executable.
		# shellcheck disable=SC2012
		PATH_PREFIX="$(ls -d "/cygdrive/"*"/Qt/Tools/mingw"*"/bin" | sort --version-sort | tail -n 1)"
	fi
	# Convert to windows path format.
	CMAKE_BIN="$(cygpath -w "${CMAKE_BIN}")"
	# Covert the prefix path to Windows format.
	PATH_PREFIX="$(cygpath -w "${PATH_PREFIX}")"
	# Assemble the Windows build directory.
	BUILD_DIR="$(cygpath -aw "${SCRIPT_DIR}/${BUILD_SUBDIR}")"
	# Covert the source path to Windows format.
	SOURCE_DIR="$(cygpath -aw "${SOURCE_DIR}")"
	# Visual Studio wants of course wants something else again.
	if ${FLAG_VISUAL_STUDIO} ; then
		BUILD_GENERATOR="CodeBlocks - NMake Makefiles"
		# CMake binary bundled with MSVC but the default QT version is also ok.
		CMAKE_BIN="%VSINSTALLDIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
	else
		BUILD_GENERATOR="CodeBlocks - MinGW Makefiles"
	fi
	# Report used cmake and its version.
	WriteLog "- CMake '${CMAKE_BIN}' $("$(cygpath -u "${CMAKE_BIN}")" --version | head -n 1)"
else
	# Try to use the CLion installed version of the cmake command.
	CMAKE_BIN="${HOME}/lib/clion/bin/cmake/linux/bin/cmake"
	if ! command -v "${CMAKE_BIN}" &> /dev/null ; then
		# Try to use the Qt installed version of the cmake command.
		CMAKE_BIN="${LOCAL_QT_ROOT}/Tools/CMake/bin/cmake"
		if ! command -v "${CMAKE_BIN}" &> /dev/null ; then
			CMAKE_BIN="$(which cmake)"
		fi
	fi
	BUILD_DIR="${SCRIPT_DIR}/${BUILD_SUBDIR}"
	BUILD_GENERATOR="CodeBlocks - Unix Makefiles"
	WriteLog "- CMake '$(realpath "${CMAKE_BIN}")' $(${CMAKE_BIN} --version | head -n 1)"
fi

# Build execution script depending on the OS.
if ${FLAG_WINDOWS} ; then
	# Start of echo capturing.
	{
		echo '@echo off'
		# Set time stamp at beginning of file.
		echo ":: Timestamp: $(date '+%Y-%m-%dT%T.%N')"
		if ${FLAG_VISUAL_STUDIO} ; then	cat <<EOF
if not defined VisualStudioVersion (
	call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64 -vcvars_ver=14.29
	echo :: MSVC v%VisualStudioVersion% vars have been set now.
) else (
	echo :: MSVC v%VisualStudioVersion% vars have been set before.
)
EOF
		fi
		echo -e "\n:: === General Section ==="
		# Add the prefix to the path when non empty.
		if [[ -n "${PATH_PREFIX}" ]] ; then
			echo ":: Set path prefix for tools to be found."
			echo "PATH=${PATH_PREFIX};%PATH%"
		fi
		# Configure
		if ${FLAG_CONFIG} ; then
			echo -e "\n:: === CMake Configure Section ==="
			echo "\"${CMAKE_BIN}\" ^"
			echo "-B \"${BUILD_DIR}\" ^"
			echo "-G \"${BUILD_GENERATOR}\" ${CONFIG_OPTIONS} ^"
			for key in "${!CMAKE_DEFS[@]}" ; do
				echo "-D ${key}=\"${CMAKE_DEFS[${key}]}\" ^"
			done
			echo "\"${SOURCE_DIR}\""
		fi
		# Build/Compile
		if ${FLAG_BUILD} ; then
			echo -e "\n:: === CMake Build Section ==="
			echo "\"${CMAKE_BIN}\" ^"
			echo "--build \"${BUILD_DIR}\" ^"
			echo "--target \"${TARGET}\" ${BUIlD_OPTIONS} ^"
			if ! ${FLAG_VISUAL_STUDIO} ; then
				echo "-- -j ${CPU_CORES_TO_USE}"
			else
				echo "-- -j ${CPU_CORES_TO_USE}"
			fi
		fi
	} >> "${EXEC_SCRIPT}"
else
	# Start of echo capturing.
	{
		# Set time stamp at beginning of file.
		echo "# Timestamp: $(date '+%Y-%m-%dT%T.%N')"
		echo -e "\n# === General Section ==="
		# Add the prefix to the path when non empty.
		if [[ -n "${PATH_PREFIX}" ]] ; then
			echo "# Set path prefix for tools to be found."
			# shellcheck disable=SC2154
			echo "path=${PATH_PREFIX};${path}"
		fi
		# Configure
		if ${FLAG_CONFIG} ; then
			echo -e "\n# === CMake Configure Section ==="
			echo "'${CMAKE_BIN}' \\"
			echo "	-B '${BUILD_DIR}' \\"
			echo "	-G '${BUILD_GENERATOR}' ${CONFIG_OPTIONS} \\"
			for key in "${!CMAKE_DEFS[@]}" ; do
				echo "	-D ${key}='${CMAKE_DEFS[${key}]}' \\"
			done
			echo "	\"${SOURCE_DIR}\""
		fi
		# Build/Compile
		if ${FLAG_BUILD} ; then
			echo -e "\n# === CMake Build Section ==="
			echo "\"${CMAKE_BIN}\" \\" ;
			echo "	--build \"${BUILD_DIR}\" \\"
			echo "	--target \"${TARGET}\" ${BUIlD_OPTIONS} \\"
			echo "	-- -j ${CPU_CORES_TO_USE}"
		fi
	} >> "${EXEC_SCRIPT}"
fi

# Execute the script or write it to the log out when debugging.
if ${FLAG_DEBUG} ; then
	WriteLog "=== Script content ${EXEC_SCRIPT} ==="
	echo "$(cat "${EXEC_SCRIPT}")\n\n"
	WriteLog "$(printf '=%.0s' {1..45})"
else
	WriteLog "- Executing generated script: '${EXEC_SCRIPT}'"
	if ${FLAG_WINDOWS} ; then
		CMD "/C $(cygpath -w "${EXEC_SCRIPT}")"
	else
		exec "${EXEC_SCRIPT}"
	fi
fi

# Cleanup generate script afterwards.
if [[ -f "${EXEC_SCRIPT}" ]] ; then
	rm "${EXEC_SCRIPT}"
fi
