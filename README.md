# patonlab_unix

Unix utilities for computational chemistry workflows in the Paton Research Group.

## Contents

### bash/
Example bash profile with environment setup for:
- Gaussian 16
- ORCA
- Q-Chem
- XTB / CREST
- COSMOtherm
- TURBOMOLE
- NCIPlot
- NBO7

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
**install_software.sh** - Install the standard ORCA, xtb, CREST and g-xTB binaries on a workstation, at the paths the profile, qsub and autotest expect. Downloads are checked against pinned SHA-256 checksums. Each version goes into its own directory (e.g. `/usr/local/xtb-6.7.1`), with `/usr/local/xtb` a symlink to it. The previous installation is kept as `<name>.pre-<date>` and the undo commands are printed. It refuses to switch a package that running jobs are using.

```bash
sudo admin/install_software.sh --all --dry-run       # show what would change
sudo admin/install_software.sh --all                 # xtb, CREST, g-xTB
sudo admin/install_software.sh --orca ~/orca_6_1_1_linux_x86-64_shared_openmpi418.tar.xz
```

ORCA needs a FACCTs login, so download its tarball first. g-xTB 2 is a modified xtb, installed as `xtb-gxtb` so it never shadows the regular `xtb`; run it as `xtb-gxtb mol.xyz --gxtb`.

## Installation

Add the scripts to your PATH:

```bash
export PATH="${PATH}:/path/to/patonlab_unix/python:/path/to/patonlab_unix/bash:/path/to/patonlab_unix/testing"
```

`bash/example_bash_profile` sets up all of the above and works unchanged on every group workstation: each block only takes effect if that software is installed.

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
