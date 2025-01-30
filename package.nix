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
    name = "12203b53b94afece3a3bda2798fca90d3ccf34cf9d96be99d2adc573ea1438a0c233";
    path = fetchzip {
      url = "https://github.com/Ivan-Velickovic/dtb.zig/archive/dafd03209d97092909b4faeda630839b17fa1ae4.tar.gz";
      hash = "sha256-8UFLQTVKxPJO1CaOR/ZRR1zOyol4NAUZCY59ouXTChA=";
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
