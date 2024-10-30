#!/bin/bash

# Recreate build directories
rm ./build/*

# GENERATE LUA in /build-lua
mkdir -p ./build

# build teal
cyan build -u

cd build

# amalg.lua -s main.lua -o ../build-lua/process.lua \
#     globals dbUtils database userManager gameLogic gameState 

# FINAL RESULT is build/main.lua