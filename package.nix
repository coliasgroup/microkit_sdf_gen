#
# Copyright 2024, UNSW
# SPDX-License-Identifier: BSD-2-Clause
#
{
  zig
, pythonPackages
, lib
}:

  with pythonPackages;
    buildPythonPackage rec {
      pname = "sdfgen";
      version = builtins.readFile ./VERSION;
      # TODO: fix this
      src = ./.;

      build-system = [ setuptools ];

      meta = with lib; {
        homepage = "https://github.com/au-ts/microkit_sdf_gen";
        maintainers = with maintainers; [ au-ts ];
      };

      preBuild = ''
        export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)
        export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
      '';

      nativeBuildInputs = [ zig ];
    }
