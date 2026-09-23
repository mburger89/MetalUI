# Vendored libunibreak

- Version: 8.0 (UAX #14 revision 55, Unicode 17.0)
- Source: https://github.com/adah1972/libunibreak/releases/download/libunibreak_8_0/libunibreak-8.0.tar.gz
- SHA-256 (tarball): 9c4fad6e517338a098373acc9f35579ae2c325e6446666fb9ac2666ba15ceba4
- Licence: zlib (`LICENCE`, kept verbatim).
- Kept: the line-breaking sources and what they include — `linebreak.c`,
  `linebreakdata.c`, `linebreakdef.c/.h`, `linebreakauxdata.c`,
  `unibreakbase.c/.h`, `unibreakdef.c/.h`, `eastasianwidthdef.c/.h`,
  `eastasianwidthdata.c`; `linebreak.h` and the `unibreakbase.h` it includes
  moved to `include/` as the public headers (the sources find them there by
  the same quoted name).
- Removed: word and grapheme breaking, emoji data, generator scripts, the
  conformance test data and runner, build files, docs.
- Edited: nothing.
- Compiled (ruling LB-A): the six `.c` files that are translation units;
  `linebreakauxdata.c` and `eastasianwidthdata.c` are `#include`d by
  `linebreak.c` and `eastasianwidthdef.c` and excluded from compilation
  (compiling them separately duplicates `ub_is_op_east_asian`, measured).
