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
      url = "https://github.com/Ivan-Velickovic/dtb.zig/archive/6a1307379f5a0c048dbf8e4eb01644eb215c76e7.tar.gz";
      hash = "sha256-a86Yg/amDqK28YoTBB6Ex0l1Wi39ZCI1M1qD93mkPFc=";
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
