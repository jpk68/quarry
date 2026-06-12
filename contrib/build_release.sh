#!/usr/bin/env bash

zig build --release=fast -Duse-llvm=true -Dfmt-check=true --summary all
