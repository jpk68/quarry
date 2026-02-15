# RandomX documentation

Some notes about this project's implementation of RandomX.

## Backends

An interpreted backend based on a bytecode machine architecture (similar to that of the official
RandomX implementation) is planned, as well as a JIT-compiled backend targeting x86 and other
platforms later.

## Blake2b hashing function

We will be using the Zig standard library's implementation of Blake2b.

## AES-based functions

These will likely be implemented using either standard library functionality or inline assembly for
platforms that support it. The first iterations of AES-based generator functions can also be
hardcoded, which is one approach used by the official RandomX implementation.

## Cache construction using Argon2d

The Zig standard library provides an implementation of Argon2d, however we can't use this as it
doesn't expose its internal state, which RandomX uses for cache initialization. At present, the
best approach seems to be basically copying the needed parts from the standard library and making
any necessary modifications.
