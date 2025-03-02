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
    name = "12207c24e40bf9152aea80c3248b81f26b25fa6d997e71b1fd6d16276a2f0a776fe7";
    path = fetchzip {
      url = "https://github.com/Ivan-Velickovic/dtb.zig/archive/fc940d8ebefebe6f27713ebc92fda1ee7fe342c7.tar.gz";
      hash = "sha256-vUfOPtGLWl2gqkmL6v/KtrXvMcihVyXTLZTBQG8ntyI=";
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
