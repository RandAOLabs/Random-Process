#!/bin/bash

if [[ "$(uname)" == "Linux" ]]; then
    BIN_PATH="$HOME/.luarocks/bin"
else
    BIN_PATH="/opt/homebrew/bin"
fi

rm luacov.report.out
rm luacov.report.out.index
rm luacov.stats.out

# Run tests
$BIN_PATH/busted test --pattern "_test"

luacov-console