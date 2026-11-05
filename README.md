# patonlab_unix

Unix utilities for computational chemistry workflows in the Paton Research Group.

## Contents

### bash/
**patonlab_profile.sh** - The group's login environment: Gaussian 16, NBO 7, Q-Chem, ORCA and OpenMPI, xtb, CREST, g-xTB, COSMOtherm, TURBOMOLE, NCIPlot and the group tools. Each block only takes effect if that software is installed, so the same file works on every workstation. Installed as `/etc/profile.d/patonlab.sh` (see below), every account gets it at login. It is plain POSIX sh, prints nothing, and skips root.

**orca** - Launcher for ORCA, serial or parallel: `orca job.inp > job.out`. It runs the real ORCA by its full path (which parallel runs need) with the group's OpenMPI first in `PATH`, so parallel ORCA works even when conda's base environment puts MPICH's `mpirun` first. It also means `orca` never runs `/usr/bin/orca`, an unrelated GNOME screen reader.

**openmpi_env.sh** - Puts the group's OpenMPI (`/opt/openmpi`, else `/opt/openmpi-4.1.6`, else `/usr/local`) first in `PATH` and `LD_LIBRARY_PATH`. Read by the profile, the `orca` launcher, `qsub` run scripts (before ORCA jobs) and `autotest`.

**example_bash_profile** - A `~/.bash_profile` for machines without `/etc/profile.d/patonlab.sh`: it reads `~/.bashrc`, then `patonlab_profile.sh`.

### python/

**GaussianPrep** - Generate Gaussian input files from computational chemistry output files (.log, .out). Supports Gaussian, ORCA, Q-Chem, GAMESS, Molpro, NWChem, and Psi4 via cclib.

```bash
GaussianPrep --route "B3LYP/6-31G(d) Opt" --nproc 16 --mem 72GB file.log
```

**OrcaPrep** - Generate ORCA input files from computational chemistry output files (.log, .out). Supports Gaussian, ORCA, Q-Chem, GAMESS, Molpro, NWChem, and Psi4 via cclib.

```bash
OrcaPrep --route "B3LYP def2-SVP Opt" --nproc 16 --maxcore 5000 file.log
```

**qsub** - Generate submission scripts for running jobs on machines without a scheduler.

```bash
qsub --nproc 16 job.com job2.inp
nohup ./sub.sh &
```

`--nproc` sets the cores for Q-Chem, CREST and xtb. Gaussian and ORCA use the core count in the input file (`%nprocshared`, `%pal`).

### testing/
Test suite for verifying computational chemistry software installations. Includes sample input files for supported programs.

```bash
autotest              # test everything installed on this machine
autotest --list       # list available tests
autotest --keep       # keep the working directory with all inputs and outputs
autotest --cores 16   # cores for the parallel tests (default 8)
```

Each test runs a small calculation and checks that it finished normally. Where there is a reference value, it also checks that the final energy matches to within 1e-5 hartree, which catches builds that run but give wrong numbers. When a test fails, the end of its output is printed. Besides the chemistry codes, autotest checks that `mpirun` is OpenMPI 4.x (needed by parallel ORCA 6), and that this repository's `qsub`, `GaussianPrep` and `OrcaPrep` work.

Machine-specific executable paths, disabled tests and reference-energy overrides go in `testing/config.local.yaml` (ignored by git), which is merged over `config.yaml`.

### admin/
**install_software.sh** - Install the standard ORCA, xtb, CREST and g-xTB binaries, and the OpenMPI that parallel ORCA uses, on a workstation, at the paths the profile, qsub and autotest expect. Downloads are checked against pinned SHA-256 checksums. Each version goes into its own directory (e.g. `/usr/local/xtb-6.7.1`), with `/usr/local/xtb` a symlink to it. The previous installation is kept as `<name>.pre-<date>` and the undo commands are printed. It refuses to switch a package that running jobs are using.

```bash
sudo admin/install_software.sh --all --dry-run       # show what would change
sudo admin/install_software.sh --all                 # xtb, CREST, g-xTB, OpenMPI
sudo admin/install_software.sh --openmpi             # OpenMPI 4.1.8 only, in /opt/openmpi
sudo admin/install_software.sh --orca ~/orca_6_1_1_linux_x86-64_shared_openmpi418.tar.xz
```

ORCA needs a FACCTs login, so download its tarball first. g-xTB 2 is a modified xtb, installed as `xtb-gxtb` so it never shadows the regular `xtb`; run it as `xtb-gxtb mol.xyz --gxtb`.

OpenMPI 4.1.8, the version ORCA 6.1 is built against, is compiled from source (needs `gcc` and `make`) into `/opt/openmpi-4.1.8`, with `/opt/openmpi` a symlink to it. The example profile puts it ahead of conda in `PATH`, because Anaconda's base environment can include MPICH, whose `mpirun` can't start ORCA.

**make_motd** - Rebuild a workstation's `/etc/motd` from the shared template (`admin/motd_template.txt`), the machine's hardware (CPU, RAM, GPUs) and the results of `autotest`, so every machine's login message has the same layout, correct paths and an up-to-date software status. The banner art at the top of the current MOTD is kept. Run `autotest` as a normal user, not root:

```bash
autotest --json > ~/autotest.json
admin/make_motd --autotest ~/autotest.json                       # preview
admin/make_motd --autotest ~/autotest.json > /tmp/motd.new       # write to a file first:
sudo cp /etc/motd /etc/motd.bak && sudo cp /tmp/motd.new /etc/motd   # make_motd reads /etc/motd
admin/make_motd --autotest ~/autotest.json --note "Rebooting Friday 9am for updates" > /tmp/motd.new
```

Software that isn't installed on a machine is left out. Failures are marked, with "licence expired" when that is the cause.

## Installation

On a group workstation, install the group profile once, as root:

```bash
sudo ln -s /usr/local/patonlab_unix/bash/patonlab_profile.sh /etc/profile.d/patonlab.sh
```

Every account then gets the software environment at its next login, with nothing to copy, and updates to this repository reach everyone. Undo it with `sudo rm /etc/profile.d/patonlab.sh`. A user's own `~/.bash_profile` and `~/.bashrc` run afterwards, so their settings still apply; old lines pointing at moved software (e.g. `ORCA504`, `orca610`) can be deleted.

Without the group profile, copy `bash/example_bash_profile` to `~/.bash_profile`, or add the scripts to your PATH:

```bash
export PATH="/path/to/patonlab_unix/bash:${PATH}:/path/to/patonlab_unix/python:/path/to/patonlab_unix/testing"
```

### Deploying on group machines

- Keep one clone at `/usr/local/patonlab_unix`, owned by root and not writable by users.
- Update it with `sudo git -C /usr/local/patonlab_unix pull`. Don't edit the installed files: commit changes to this repository and pull them on each machine.
- Put machine-specific settings in `testing/config.local.yaml` rather than editing tracked files.

## Requirements

- Python 3.6+ (3.7+ for autotest)
- cclib (`pip install cclib`) for GaussianPrep and OrcaPrep
- pyyaml (`pip install pyyaml`) optional, for autotest config files

## Author

Paton Research Group
patonlab@colostate.edu
