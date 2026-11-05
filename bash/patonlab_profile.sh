# Paton group software environment for every account on a group workstation.
#
# Install once per machine (as root), so every login shell reads it before the
# user's own ~/.bash_profile:
#     ln -s /usr/local/patonlab_unix/bash/patonlab_profile.sh /etc/profile.d/patonlab.sh
# Where it isn't installed, example_bash_profile reads it instead.
#
# Each block only takes effect if that software is installed on this machine.
# Plain POSIX sh (the desktop login reads /etc/profile with /bin/sh), prints
# nothing, and is safe to read more than once. Not applied to root.

if [ "$(id -u)" -ne 0 ]; then

PATONLAB_UNIX=${PATONLAB_UNIX:-/usr/local/patonlab_unix}

# Add a directory to the front or back of PATH, or the front of LD_LIBRARY_PATH,
# unless it's already there
_pl_front() { case ":${PATH}:" in *":$1:"*) ;; *) PATH="$1:${PATH}" ;; esac; }
_pl_back() { case ":${PATH}:" in *":$1:"*) ;; *) PATH="${PATH}:$1" ;; esac; }
_pl_lib() {
	case ":${LD_LIBRARY_PATH:-}:" in
		*":$1:"*) ;;
		*) LD_LIBRARY_PATH="$1${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;;
	esac
}

# ==================== Libraries ====================
if [ -d /usr/local/intel64_lin ]; then
	_pl_lib /usr/local/intel64_lin
fi

# ==================== Gaussian 16 and NBO 7 ====================
# The g16 directory is only readable by the gaussian group, so others skip this
if [ -f /usr/local/Gaussian/G16C/g16/bsd/g16.profile ]; then
	g16root=/usr/local/Gaussian/G16C
	export g16root
	if [ -n "${BASH_VERSION:-}" ]; then
		. "${g16root}/g16/bsd/g16.profile"
	else
		# Its closing "ulimit -X hard" lines are bash-only; everything else works in sh
		. "${g16root}/g16/bsd/g16.profile" 2>/dev/null
	fi
fi
if [ -d /usr/local/nbo7/bin ]; then
	_pl_back /usr/local/nbo7/bin
fi

# ==================== Q-Chem ====================
# qcenv.sh uses bash-only syntax, so only read it from bash
if [ -n "${BASH_VERSION:-}" ] && [ -f /usr/local/qchem6/qcenv.sh ]; then
	. /usr/local/qchem6/qcenv.sh
fi

# ==================== xtb, CREST and g-xTB ====================
if [ -d /usr/local/xtb ]; then
	XTBHOME=/usr/local/xtb
	XTBPATH="${XTBHOME}/share/xtb:${HOME}"
	export XTBHOME XTBPATH
	case ":${MANPATH:-}:" in
		*":${XTBHOME}/share/man:"*) ;;
		*) MANPATH="${MANPATH:-}:${XTBHOME}/share/man"; export MANPATH ;;
	esac
	case ":${PKG_CONFIG_PATH:-}:" in
		*":${XTBHOME}/share/xtb:"*) ;;
		*) PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+${PKG_CONFIG_PATH}:}${XTBHOME}/share/xtb"; export PKG_CONFIG_PATH ;;
	esac
	_pl_back "${XTBHOME}/bin"
	_pl_back "${XTBHOME}"
fi
# CREST 3.0.2, ahead of any older copy in ${XTBHOME}
if [ -x /usr/local/crest/crest ]; then
	_pl_front /usr/local/crest
fi
# g-xTB 2.x (admin/install_software.sh): xtb-gxtb mol.xyz --gxtb
if [ -x /usr/local/g-xtb/xtb-gxtb ]; then
	_pl_back /usr/local/g-xtb
fi
# Older standalone g-xTB (gxtb; copy its parameter files to $HOME before first use)
if [ -d /usr/local/g-xtb-main/binary ]; then
	_pl_back /usr/local/g-xtb-main/binary
fi

# ==================== COSMOtherm and TURBOMOLE ====================
if [ -d /usr/local/BIOVIA/COSMOtherm2021 ]; then
	_pl_front /usr/local/BIOVIA/COSMOtherm2021/COSMOtherm/BIN-LINUX
	_pl_front /usr/local/BIOVIA/COSMOtherm2021/COSMOthermX
fi
if [ -x /usr/local/BIOVIA/TURBOMOLE/scripts/sysname ]; then
	TURBODIR=/usr/local/BIOVIA/TURBOMOLE
	export TURBODIR
	_pl_front "${TURBODIR}/bin/$("${TURBODIR}/scripts/sysname")"
	_pl_front "${TURBODIR}/scripts"
fi

# ==================== NCIPlot ====================
if [ -d /usr/local/nciplot ]; then
	NCIPLOT_HOME=/usr/local/nciplot
	export NCIPLOT_HOME
	_pl_front "${NCIPLOT_HOME}"
fi

# ==================== OpenMPI and ORCA 6 ====================
# The group OpenMPI first (see openmpi_env.sh). Conda, set up later in ~/.bashrc,
# can still put MPICH's mpirun ahead of it in this shell, so run ORCA with the
# "orca" launcher (below) or qsub, which put OpenMPI first for the job itself.
if [ -f "${PATONLAB_UNIX}/bash/openmpi_env.sh" ]; then
	. "${PATONLAB_UNIX}/bash/openmpi_env.sh"
fi
if [ -x /usr/local/ORCA6/orca ]; then
	ORCA_ROOT=/usr/local/ORCA6
	export ORCA_ROOT
	_pl_front "${ORCA_ROOT}"
	_pl_lib "${ORCA_ROOT}"
fi

# ==================== Group tools ====================
# bash/ goes first so "orca" is the group launcher (never /usr/bin/orca, a GNOME
# screen reader); python/ and testing/ hold qsub, GaussianPrep, OrcaPrep and autotest
if [ -d "${PATONLAB_UNIX}" ]; then
	_pl_front "${PATONLAB_UNIX}/bash"
	_pl_back "${PATONLAB_UNIX}/python"
	_pl_back "${PATONLAB_UNIX}/testing"
fi

export PATH LD_LIBRARY_PATH
unset -f _pl_front _pl_back _pl_lib

fi
