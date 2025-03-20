#!/bin/bash

# Recreate build directories
rm ./build/*
rm ./process.lua
# GENERATE LUA in /build-lua
mkdir -p ./build


# build teal
cyan build -u

cd build

amalg.lua -s main.lua -o ../process.lua \
    globals dbUtils database providerManager randomManager tokenManager verifierManager

# FINAL RESULT is build/main.lua

# Run tests immediately after building
cd ..
bash scripts/test.sh