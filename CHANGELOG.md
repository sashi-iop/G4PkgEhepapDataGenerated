# CMS Model — Complete Changelog & Developer Notes

> **Date**: 21 February 2026  
> **Project**: `~/Desktop/cmsModel` — Geant4 + ROOT CMS Detector Simulation  
> **Geant4 Version**: 11.4.0 (`~/software/geant4/geant4-v11.4.0/`)  
> **ROOT**: via conda `hep` environment (`~/miniforge3/envs/hep/`)

---

## Table of Contents

1. [Build System Fixes](#1-build-system-fixes)
2. [Compilation Error Fixes](#2-compilation-error-fixes)
3. [Runtime Crash Fix](#3-runtime-crash-fix)
4. [Hands-On Session: Primary Particle Config](#4-hands-on-session-primary-particle-configuration)
5. [Hands-On Session: Energy Resolution](#5-hands-on-session-energy-resolution-in-hcal)
6. [Hands-On Session: 32-bit Word Packing](#6-hands-on-session-32-bit-word-packing)
7. [Hands-On Session: Calibration Histograms](#7-hands-on-session-calibration-histograms)
8. [Digitisation Macro](#8-digitisation-macro)
9. [Build Script](#9-build-script)
10. [How to Build & Run](#10-how-to-build--run)

---

## 1. Build System Fixes

### Problem
`cmake` could not find Geant4 or ROOT packages.

### Solution
Pass explicit paths to cmake:
```bash
cmake -DGeant4_DIR=$HOME/software/geant4/geant4-v11.4.0/lib/cmake/Geant4 \
      -DCMAKE_PREFIX_PATH=$HOME/miniforge3/envs/hep \
      ..
```
- `-DGeant4_DIR` points to the Geant4 cmake config
- `-DCMAKE_PREFIX_PATH` points to the conda env so ROOT and its dependency `Vdt` are found

### File Changed
**None** — this is a cmake command-line fix, not a code change.

---

## 2. Compilation Error Fixes

### Problem
Three "variable-sized object may not be initialized" errors.  
In C++, you cannot initialize a variable-length array (VLA) with `= {values}`.  
Accessing `pAnalysis->nsilayer` through a pointer makes the compiler treat it as a runtime value, even though `nsilayer` is `static const`.

### Fix: Use the class constant directly

#### File: `src/Serc19DetectorConstruction.cc` (lines 250, 252)
```diff
-  const int nsilayer=pAnalysis->nsilayer;
-  double sirad[pAnalysis->nsilayer]={2.9, 6.8, ...};
+  const int nsilayer=Serc19SimAnalysis::nsilayer;
+  double sirad[Serc19SimAnalysis::nsilayer]={2.9, 6.8, ...};
```

#### File: `src/Serc19EventAction.cc` (lines 153, 176)
```diff
-  G4double totET[pAnalysis->nsilayer] = {0};
+  G4double totET[Serc19SimAnalysis::nsilayer] = {0};

-  G4double totEH[pAnalysis->nhcalLayer] = {0};
+  G4double totEH[Serc19SimAnalysis::nhcalLayer] = {0};
```

### Why it works
`Serc19SimAnalysis::nsilayer` is a compile-time constant (static const), so the compiler knows the array size at compile time.

---

## 3. Runtime Crash Fix

### Problem
Running `./cmsmodel` without arguments caused a **segmentation fault**.

### Root Cause
Line 41 of `serc19_cmsmodel.cc` unconditionally accessed `argv[1]` and `argv[2]`, which are NULL when `argc == 1`.

### Fix
#### File: `serc19_cmsmodel.cc` (line 41)
```diff
-  G4cout <<"argc "<<argc<<" "<<argv[0]<<" "<<argv[1]<<" "<<argv[2]<<G4endl;
+  G4cout <<"argc "<<argc<<" "<<argv[0];
+  if (argc > 1) G4cout <<" "<<argv[1];
+  if (argc > 2) G4cout <<" "<<argv[2];
+  G4cout <<G4endl;
```

---

## 4. Hands-On Session: Primary Particle Configuration

### Change
Updated beam energy from 15 GeV to 200 GeV for π⁺ study.

#### File: `src/Serc19PrimaryGeneratorAction.cc` (line 51)
```diff
-  SetIncEnergy(15.0*GeV);
+  SetIncEnergy(200.0*GeV);
```

`SetPartId(211)` (pion) was already set — no change needed.

### For kaon comparison (future)
```cpp
SetPartId(321);          // K+ instead of π+
SetIncEnergy(40.0*GeV);  // or 100.0*GeV
```

---

## 5. Hands-On Session: Energy Resolution in HCAL

### What was implemented
Three effects applied in `EndOfEvent()` after cell-level energy accumulation:

#### File: `src/Serc19HclSD.cc` — `EndOfEvent()` method

**a) Photon Statistics (Stochastic Term)**
```cpp
#include "G4Poisson.hh"
// ...
G4double npe_mean = 40.0 * edep_MeV;            // 40 p.e. per MeV
G4long   npe_sampled = G4Poisson(npe_mean);      // Poisson sampling
G4double edep_smeared_MeV = edep_MeV * (G4double(npe_sampled) / npe_mean);
```

**b) Collection Efficiency (depth-dependent)**
```cpp
G4double efficiency = 1.0 + 0.1 * G4double(approx_depth) / G4double(nhcalLayer);
edep_smeared_MeV *= efficiency;
```

**c) Electronic Noise**
```cpp
#include "CLHEP/Random/RandGauss.h"
// ...
edep_smeared_MeV += G4RandGauss::shoot(0.0, 200.0);  // σ = 200 MeV
```

### New includes added to `src/Serc19HclSD.cc`
```cpp
#include "Randomize.hh"
#include "CLHEP/Random/RandGauss.h"
#include "G4Poisson.hh"
```

---

## 6. Hands-On Session: 32-bit Word Packing

### Old layout (17 bits for detid)
```
ieta(6) << 11 | iphi(6) << 5 | idepth(5)
```

### New layout (32 bits total)
```
| ieta (6 bits) | iphi (6 bits) | depth (3 bits) | energy (17 bits) |
|   bits 31-26  |  bits 25-20   |   bits 19-17   |    bits 16-0     |
```

#### File: `src/Serc19HclSD.cc` — `ProcessHits()` method
```cpp
// 17 layers mapped to 3 bits
unsigned int depth3 = (idepth / 3);
if (depth3 > 7) depth3 = 7;  // cap at 3-bit max

unsigned int detid = ieta;
detid <<= 6;
detid += iphi;
detid <<= 3;
detid += depth3;
```

#### File: `src/Serc19HclSD.cc` — `EndOfEvent()` method
```cpp
// Pack into 32-bit word: cellid(15 bits) << 17 | energy(17 bits)
G4int energy_MeV = (edep_smeared_MeV > 0) ? G4int(edep_smeared_MeV) : 0;
if (energy_MeV > 131071) energy_MeV = 131071;  // 2^17 - 1

unsigned long int packed_word = (static_cast<unsigned long int>(cellid) << 17) + energy_MeV;
pAnalysis->detidHL[pAnalysis->nsimhtHL] = packed_word;
```

#### File: `src/Serc19EventAction.cc` — `EndOfEventAction()` (depth extraction updated)
```diff
-  unsigned il = ((*EHC2)[ij]->GetHitId()) & 0x1F;  // old: 5-bit depth
+  unsigned il = detid & 0x7;                         // new: 3-bit depth
+  unsigned layer = il * 3;                            // map back to ~original layer
```

---

## 7. Hands-On Session: Calibration Histograms

### New histogram declarations
#### File: `include/Serc19SimAnalysis.hh`
```cpp
// Calibration histograms (with and without ECAL)
TH1F* h_hcal_total_energy;        // Total HCAL energy only
TH1F* h_ecal_hcal_total_energy;   // Combined ECAL + HCAL energy
```

### Histogram creation
#### File: `src/Serc19SimAnalysis.cc` — in `OpenRootfiles()`
```cpp
h_hcal_total_energy = new TH1F("hcal_total_energy",
    "HCAL Total Energy (GeV)", 200, 0, 400);
h_ecal_hcal_total_energy = new TH1F("ecal_hcal_total_energy",
    "ECAL+HCAL Total Energy (GeV)", 200, 0, 400);
```

### Histogram filling
#### File: `src/Serc19EventAction.cc` — in `EndOfEventAction()`
```cpp
// ECAL energy moved to wider scope
G4double totEE = 0;
// ... ECAL loop fills totEE ...

// HCAL total accumulated
G4double totEH_all = 0;
// ... HCAL loop fills totEH_all ...

// Fill calibration histograms
G4double hcal_GeV = totEH_all / 1.0e6;  // keV -> GeV
G4double ecal_GeV = totEE / GeV;
pAnalysis->h_hcal_total_energy->Fill(hcal_GeV);
pAnalysis->h_ecal_hcal_total_energy->Fill(ecal_GeV + hcal_GeV);
```

---

## 8. Digitisation Macro

### File: `skeleton_ecal_hcal_digitisation.C`

The skeleton was provided with empty digitisation logic. The following was implemented:

#### a) Bug fix: `detidHL` type mismatch
```diff
-  unsigned int detidHL[nsimhtmxHL];     // WRONG: doesn't match /l branch
+  unsigned long int detidHL[nsimhtmxHL]; // CORRECT: matches 64-bit branch
```

#### b) ECAL Digitisation (crystal-level)
```cpp
for (unsigned int ih = 0; ih < nsimhtEC; ih++) {
    float sim_energy_GeV = energyEC[ih] / 1000.0;  // MeV -> GeV
    float smeared_energy = sim_energy_GeV + gRandom3->Gaus(0, pedwidth);
    if (smeared_energy > otherthrs) {
        ecal_digi_total += smeared_energy;
    }
}
```

#### c) HCAL Digitisation (32-bit unpacking + noise)
```cpp
for (unsigned int ih = 0; ih < nsimhtHL; ih++) {
    unsigned int energy_MeV = detidHL[ih] & 0x1FFFF;  // lower 17 bits
    float sim_energy_GeV = energy_MeV / 1000.0;
    float smeared_energy = sim_energy_GeV + gRandom3->Gaus(0, hclwidth);
    if (smeared_energy > hclthrs) {
        hcal_digi_total += smeared_energy;
    }
}
```

#### d) Removed CLHEP dependency
Commented out `CLHEP/Matrix/Matrix.h`, `CLHEP/Vector/LorentzVector.h`, `CLHEP/Vector/ThreeVector.h` and the `dgap()` function — not needed for digitisation.

#### e) Added to `CMakeLists.txt`
```cmake
add_executable(ecal_hcal_digitisation skeleton_ecal_hcal_digitisation.C)
target_include_directories(ecal_hcal_digitisation PRIVATE include)
target_link_libraries(ecal_hcal_digitisation ${ROOT_LIBRARIES})
target_link_libraries(ecal_hcal_digitisation ${Geant4_LIBRARIES})
```

### Output
Produces a ROOT file with tree `T2` containing branches:
- `totsimenr` — ECAL + HCAL simulated energy (GeV)
- `totdigienr` — ECAL + HCAL digitised energy (GeV)
- `hclsimenr` — HCAL-only simulated energy (GeV)
- `hcldigienr` — HCAL-only digitised energy (GeV)

---

## 9. Build Script

### File: `runit.sh`

Complete build/run/digitise script with commands:
```
./runit.sh build   — Build only (incremental)
./runit.sh clean   — Clean + full rebuild
./runit.sh run     — Build + batch simulation
./runit.sh digi    — Run digitisation
./runit.sh all     — Full pipeline: build → simulate → digitise
./runit.sh         — Build + interactive mode
```

---

## 10. How to Build & Run

### Prerequisites
```bash
conda activate hep
```

### Full pipeline
```bash
cd ~/Desktop/cmsModel
./runit.sh all
```

### Manual step-by-step
```bash
# Build
cd ~/Desktop/cmsModel
source ~/software/geant4/geant4-v11.4.0/bin/geant4.sh
cd build
cmake -DGeant4_DIR=$HOME/software/geant4/geant4-v11.4.0/lib/cmake/Geant4 \
      -DCMAKE_PREFIX_PATH=$HOME/miniforge3/envs/hep ..
make -j$(sysctl -n hw.ncpu)

# Simulate (batch mode)
./cmsmodel run.mac

# Digitise
echo "test_run10.root 10000" > test_pion_klong.log
./ecal_hcal_digitisation 40 200 25 100
```

### Digitisation arguments (all in MeV)
| Arg | Meaning | Typical Value |
|-----|---------|---------------|
| 1 | ECAL noise per crystal | 40 |
| 2 | ECAL energy threshold | 200 |
| 3 | HCAL noise per tower | 25 |
| 4 | HCAL energy threshold | 100 |

---

## Files Modified Summary

| File | Changes |
|------|---------|
| `serc19_cmsmodel.cc` | Guard `argv[1]`/`argv[2]` access |
| `src/Serc19DetectorConstruction.cc` | VLA fix: `Serc19SimAnalysis::nsilayer` |
| `src/Serc19EventAction.cc` | VLA fix + calibration histograms + 3-bit depth mask |
| `src/Serc19PrimaryGeneratorAction.cc` | Beam energy 15→200 GeV |
| `src/Serc19HclSD.cc` | Energy resolution + 32-bit packing (major rewrite) |
| `include/Serc19SimAnalysis.hh` | Added calibration histogram pointers |
| `src/Serc19SimAnalysis.cc` | Created calibration histograms |
| `skeleton_ecal_hcal_digitisation.C` | Completed digitisation logic |
| `CMakeLists.txt` | Added digitisation executable target |
| `runit.sh` | Complete build/run/digitise script |
