# Custom python310 package for nixos-26.05, which no longer ships it.
#
# The OctoPrint fork (1.7.3) pins Flask<2, tornado<7, PyYAML<6, wrapt<1.13, ...
# and does not build on Python 3.11+. Instead of copying the interpreter recipe
# into this repo, reuse the one from the nixpkgs-py310 source tree (nixos-25.11,
# Python 3.10.x) and build it with the current nixpkgs' dependencies/toolchain.
#
# The recipe's `self` argument resolves through `__splicedPackages.python310`,
# i.e. back to this overlay's python310, so passthru (pkgs, withPackages, ...)
# stays consistent.
{ nixpkgs-py310 }:

final: prev: {
  python310 =
    (final.callPackage "${nixpkgs-py310}/pkgs/development/interpreters/python" { }).python310;
}
