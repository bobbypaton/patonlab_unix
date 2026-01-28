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

**qsub** - Generate submission scripts for running jobs on machines without a scheduler.

```bash
qsub --nproc 24 job.com job2.inp
```

### testing/
Test suite for verifying computational chemistry software installations. Includes sample input files for supported programs.

## Installation

Add the scripts to your PATH:

```bash
export PATH="${PATH}:/path/to/patonlab_unix/python:/path/to/patonlab_unix/bash"
```

## Requirements

- Python 3.6+
- cclib (`pip install cclib`) for GaussianPrep

## Author

Paton Research Group
patonlab@colostate.edu
