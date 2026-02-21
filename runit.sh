#!/bin/bash
#
# CMS Model - Build, Simulate, and Digitise
#
# Usage:
#   ./runit.sh build     - Only build (cmake + make)
#   ./runit.sh clean     - Clean build and rebuild from scratch
#   ./runit.sh run       - Run simulation in batch mode (run.mac)
#   ./runit.sh digi      - Run digitisation on simulation output
#   ./runit.sh all       - Build + Run + Digitise (full pipeline)
#   ./runit.sh           - Default: build + run interactive mode
#

set -e  # Exit on error

PROJECT_DIR="$HOME/Desktop/cmsModel"
BUILD_DIR="$PROJECT_DIR/build"
GEANT4_DIR="$HOME/software/geant4/geant4-v11.4.0"
CONDA_PREFIX="$HOME/miniforge3/envs/hep"

# Source Geant4 environment
source "$GEANT4_DIR/bin/geant4.sh"

ACTION="${1:-default}"

#------------------------------------------------------------
# BUILD function
#------------------------------------------------------------
do_build() {
    echo "=== Building cmsmodel ==="
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # Only run cmake if CMakeCache doesn't exist yet
    if [ ! -f CMakeCache.txt ]; then
        echo "--- Running cmake ---"
        cmake -DGeant4_DIR="$GEANT4_DIR/lib/cmake/Geant4" \
              -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
              ..
    fi

    echo "--- Running make ---"
    make -j$(sysctl -n hw.ncpu)
    echo "=== Build complete ==="
}

#------------------------------------------------------------
# CLEAN BUILD function
#------------------------------------------------------------
do_clean() {
    echo "=== Clean build ==="
    rm -rf "$BUILD_DIR"
    do_build
}

#------------------------------------------------------------
# RUN SIMULATION function (batch mode)
#------------------------------------------------------------
do_run() {
    cd "$BUILD_DIR"
    echo "=== Running simulation (batch mode with run.mac) ==="
    ./cmsmodel run.mac
    echo "=== Simulation complete ==="
    echo "ROOT output file(s):"
    ls -la *.root 2>/dev/null || echo "  (no ROOT files found)"
}

#------------------------------------------------------------
# DIGITISATION function
#------------------------------------------------------------
do_digi() {
    cd "$BUILD_DIR"

    # Find the latest simulation ROOT file
    ROOT_FILE=$(ls -t *_run*.root 2>/dev/null | head -1)
    if [ -z "$ROOT_FILE" ]; then
        echo "ERROR: No simulation ROOT file found in $BUILD_DIR"
        echo "Run the simulation first: ./runit.sh run"
        exit 1
    fi

    echo "=== Running digitisation on: $ROOT_FILE ==="

    # Create input file list
    echo "$ROOT_FILE 10000" > test_pion_klong.log

    # Run digitisation with:
    #   ECAL noise = 40 MeV, ECAL threshold = 200 MeV
    #   HCAL noise = 25 MeV, HCAL threshold = 100 MeV
    ./ecal_hcal_digitisation 40 200 25 100

    echo "=== Digitisation complete ==="
    echo "Output files:"
    ls -la *.root 2>/dev/null
}

#------------------------------------------------------------
# Main dispatch
#------------------------------------------------------------
case "$ACTION" in
    build)
        do_build
        ;;
    clean)
        do_clean
        ;;
    run)
        do_build
        do_run
        ;;
    digi)
        do_digi
        ;;
    all)
        do_build
        do_run
        do_digi
        ;;
    default)
        do_build
        cd "$BUILD_DIR"
        echo "=== Starting interactive mode ==="
        ./cmsmodel
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Usage: ./runit.sh [build|clean|run|digi|all]"
        exit 1
        ;;
esac
