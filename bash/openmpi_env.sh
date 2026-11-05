# Put the group's OpenMPI first in PATH and LD_LIBRARY_PATH, for parallel ORCA.
#
# Sourced (". openmpi_env.sh") by the group login profile, the orca launcher in this
# directory, qsub's run scripts and autotest. Conda's base environment can include
# MPICH (Anaconda's h5py needs mpi4py, which needs mpich), and conda puts its bin
# directory first when ~/.bashrc runs, so its mpirun would otherwise win; MPICH's
# mpirun can't start ORCA's OpenMPI programs.
#
# Uses the first of: /opt/openmpi (admin/install_software.sh --openmpi), the older
# /opt/openmpi-4.1.6 build, or an OpenMPI installed into /usr/local. If none exists,
# PATH is left alone. POSIX sh, prints nothing.

for _pl_mpi in /opt/openmpi /opt/openmpi-4.1.6 /usr/local; do
	if [ -x "${_pl_mpi}/bin/mpirun" ]; then
		MPI_ROOT=${_pl_mpi}
		export MPI_ROOT
		# Move ${MPI_ROOT}/bin to the front of PATH and ${MPI_ROOT}/lib to the front of
		# LD_LIBRARY_PATH, dropping any later copies. The lib order matters too: an older
		# OpenMPI's lib earlier in LD_LIBRARY_PATH (e.g. /opt/openmpi-4.1.6/lib from an
		# old ~/.bash_profile) overrides this build's runpath, so its programs would run
		# with the other version's libraries. Empty entries (the current directory) are dropped.
		_pl_ifs_set=${IFS+set}
		_pl_ifs=${IFS-}
		IFS=:
		_pl_rest=
		for _pl_dir in ${PATH}; do
			[ -z "${_pl_dir}" ] || [ "${_pl_dir}" = "${MPI_ROOT}/bin" ] || _pl_rest="${_pl_rest:+${_pl_rest}:}${_pl_dir}"
		done
		PATH="${MPI_ROOT}/bin${_pl_rest:+:${_pl_rest}}"
		_pl_rest=
		for _pl_dir in ${LD_LIBRARY_PATH:-}; do
			[ -z "${_pl_dir}" ] || [ "${_pl_dir}" = "${MPI_ROOT}/lib" ] || _pl_rest="${_pl_rest:+${_pl_rest}:}${_pl_dir}"
		done
		LD_LIBRARY_PATH="${MPI_ROOT}/lib${_pl_rest:+:${_pl_rest}}"
		if [ -n "${_pl_ifs_set}" ]; then IFS=${_pl_ifs}; else unset IFS; fi
		export PATH LD_LIBRARY_PATH
		break
	fi
done
unset _pl_mpi _pl_rest _pl_ifs _pl_ifs_set _pl_dir
