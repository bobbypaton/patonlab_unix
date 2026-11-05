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
		# Move ${MPI_ROOT}/bin to the front of PATH (dropping any later copy)
		_pl_rest=
		_pl_ifs_set=${IFS+set}
		_pl_ifs=${IFS-}
		IFS=:
		for _pl_dir in ${PATH}; do
			[ "${_pl_dir}" = "${MPI_ROOT}/bin" ] || _pl_rest="${_pl_rest:+${_pl_rest}:}${_pl_dir}"
		done
		if [ -n "${_pl_ifs_set}" ]; then IFS=${_pl_ifs}; else unset IFS; fi
		PATH="${MPI_ROOT}/bin${_pl_rest:+:${_pl_rest}}"
		case ":${LD_LIBRARY_PATH:-}:" in
			*":${MPI_ROOT}/lib:"*) ;;
			*) LD_LIBRARY_PATH="${MPI_ROOT}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;;
		esac
		export PATH LD_LIBRARY_PATH
		break
	fi
done
unset _pl_mpi _pl_rest _pl_ifs _pl_ifs_set _pl_dir
