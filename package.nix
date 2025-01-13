#
# Copyright 2024, UNSW
# SPDX-License-Identifier: BSD-2-Clause
#
{
  zig
, nix-gitignore
, pythonPackages
, lib
, linkFarm
, fetchzip
}:

  let deps = linkFarm "zig-packages" [ {
    name = "122035424754163fd26b512208f67c89a3bb24a916a0b2921e686ebc13242b40225a";
    path = fetchzip {
      url = "https://github.com/kivikakk/dtb.zig/archive/7b4f1968ed71fa2968f1ac0a149a1c1dfa48e773.tar.gz";
      hash = "sha256-VFhGHcBEEfWCw4aPtc0Gku2XHmIO1Pn3r61KWfympLA=";
    };
  } ];
in
  with pythonPackages;
    buildPythonPackage rec {
      pname = "sdfgen";
      version = builtins.readFile ./VERSION;
      src = nix-gitignore.gitignoreSource [] ./.;

      build-system = [ setuptools ];

      pythonImportsCheck = [ "sdfgen" ];

      meta = with lib; {
        homepage = "https://github.com/au-ts/microkit_sdf_gen";
        maintainers = with maintainers; [ au-ts ];
      };

      postPatch = ''
        export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)
        export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
        ln -s ${deps} $ZIG_GLOBAL_CACHE_DIR/p
      '';

      nativeBuildInputs = [ zig ];
    }
