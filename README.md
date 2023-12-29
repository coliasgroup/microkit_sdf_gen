# Higher-level tooling for constructing seL4 Microkit systems

This repository currently holds various programs to help with automating the
process of creating seL4 Microkit systems.

**Status**

The code you see here is all highly experimental, with merely the *potential* that it
will be offered to users as a solution to their problems. One important note however is
that the experimentation will continue to happen in this repository until we are satisfied
with the solution(s). It is at that point that we can start discussing whether to make these
tools part of the official Microkit project or keep them as separate. It is not clear what will
happen at this stage as it is too early to say anything.

## Problem

In order to remain simple, the seL4 Microkit (intentionally) does not provide one-size-fits-all
abstractions for creating systems where the information about the design of the system flows into
the actual code of the system.

A concrete example of this might be say some code that needs to know how many clients it needs to
serve. This obviously depends on the system designer, and could easily be something that changes
for different configurations of the same system. The Microkit SDF offers no way to pass down this
kind of information. For the example described, an easy 'solution' would be to pass some kind of
compile-time parameter (e.g a #define in C) for the number of clients. However imagine now you
have the same system, one with two clients and one with three, this requires two separate SDF files
even though they are very similar systems and the code remains identical expect for the compile-time
parameter. This problem ultimately hampers experimentation.

Another 'problem' with SDF is that is verbose and descriptive. I say 'problem' as the verbosity of it
makes it an ideal source of truth for the design of the system and hides minimal information as to the
capability distribution and access policy of a system. But the negative of this is that it does not scale
well, even small changes to a large SDF file are difficult to make and ensure are correct.

## Solution(s)

* Allow for users to easily auto-generate SDF programmatically using a tool called `sdfgen`.
* Create a graphical user-interface to visually display and produce/maintain the design of a Microkit system.
  This graphical user-interface will sort of act as a 'frontend' for the `sdfgen` tool.

Both of these solutions are very much in a work-in-progress state.

