# Higher-level tooling for constructing seL4 Microkit systems

**NOTE: this project is experimental, we are using it internally to get it into a
  usable state for the public. For development this work exists in a separate repository,
  but that may change once it is ready for use.**

This repository currently holds various programs to help with automating the
process of creating seL4 Microkit systems.

## Problem

In order to remain simple, the seL4 Microkit (intentionally) does not provide one-size-fits-all
abstractions for creating systems where the information about the design of the system flows into
the actual code of the system.

A concrete example of this might be say some code that needs to know how many clients it needs to
serve. This obviously depends on the system designer, and could easily be something that changes
for different configurations of the same system. The Microkit SDF offers no way to pass down this
kind of information. For the example described, an easy 'solution' would be to pass some kind of
compile-time parameter (e.g a #define in C) for the number of clients. However imagine now you
have the same system with two configurations, with two clients and one with three, this requires
two separate SDF files even though they are very similar systems and the code remains identical
expect for the compile-time parameter. This problem ultimately hampers experimentation.

Another 'problem' with SDF is that is verbose and descriptive. I say 'problem' as the verbosity of it
makes it an ideal source of truth for the design of the system and hides minimal information as to the
capability distribution and access policy of a system. But the negative of this is that it does not scale
well, even small changes to a large SDF file are difficult to make and ensure are correct.

## Solution(s)

* Allow for users to easily auto-generate SDF programmatically using a tool called `sdfgen`.
* Create a graphical user-interface to visually display and produce/maintain the design of a Microkit system.
  This graphical user-interface will sort of act as a 'frontend' for the `sdfgen` tool.

Both of these solutions are very much in a work-in-progress state.

## Developing

All the tooling is currently written in [Zig](https://ziglang.org/download/) with bindings
for other languages available.

### Dependencies

There are two dependencies:

* Zig (`0.14.0-dev.2079+ba2d00663` or higher).
  * See https://ziglang.org/download/, until 0.14.0 is released we rely on a master version of Zig.
* Device Tree Compiler (dtc)

### Zig bindings

The source code for the sdfgen tooling is written in Zig, and so we simply expose a module called
`sdf` in `build.zig`.

To build and run an example of the Zig bindings being used run:
```sh
zig build zig_example -- --example webserver --board qemu_virt_aarch64
```

The source code is in `examples/examples.zig`.

To see all the options run:
```sh
zig build zig_example -- --help
```

### C bindings

```sh
zig build c
```

The library will be at `zig-out/lib/csdfgen`.

The source code for the bindings is in `src/c/`.

To run an example C program that uses the bindings, run:
```sh
zig build c_example
```

The source code for the example is in `examples/examples.c`.

### Python bindings

The Python bindings are based on the C bindings. While it is possible to just use pure
Zig with the Python C API to create modules, types, functions etc for the Python bindings,
I opted with the C API to minimise friction. There are minor things like macros that are not
usable within Zig hence making writing the module in C slightly easier.

First, create a virtual environment and activate it:
```sh
cd python
python3 -m venv venv
source venv/bin/activate
```

To build just the bindings, without the package, you can run the command below.

```sh
zig build python -Dpython-include=/python/include
```

You will need to supply one or more include directories to build the bindings, since they depend
on what your OS is and where your package manager put them.

You can find the include directories using `python3-config --includes`. However, be careful that
the `python3-config` version is using the same Python as the one used to make the virtual environment.
If you have multiple versions of Python on your machine, this can be an easy mistake to make.

Finally, to build the package, you can run:
```sh
./venv/bin/python3 -m pip install .
```

Now you should be able to import and use the bindings:
```sh
./venv/bin/python3
>>> import sdfgen
>>> help(sdfgen)
```

