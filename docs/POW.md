# PoW/RandomX info

Some notes about this project's implementation of RandomX.

## Supported backends

An interpreted backend based on a bytecode machine architecture (similar to that of the original
RandomX implementation) is planned, as well as a JIT-compiled backend targeting x86-64 and other
platforms later down the line.

## Blake2b-based hashing functions

This project will use the Zig standard library's implementation of Blake2b for the time being.

## AES-based functions

These will likely be implemented using either standard library functionality, or in assembly for
supported platforms. The first iterations of AES-based generator functions can also be hardcoded,
which is one approach used by the original RandomX implementation.

## Cache construction using Argon2d

While Zig's standard library provides an implementation of Argon2d, we can't actually use this as it
doesn't expose the internal state which is used for cache initialization. At present, the best
approach seems to be essentially copying the needed parts from the standard library, with any
necessary modifications applied.
