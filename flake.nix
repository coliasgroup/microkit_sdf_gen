#
# Copyright 2024, UNSW
# SPDX-License-Identifier: BSD-2-Clause
#
{
  description = "A flake for building sDDF";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/24.05";
    utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, zig-overlay, ... }@inputs: inputs.utils.lib.eachSystem [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ]
    (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        zig = zig-overlay.packages.${system}.master;

        pysdfgen = with pkgs.python313Packages;
          buildPythonPackage rec {
            pname = "sdfgen";
            version = "0.2.0";
            src = ./.;

            build-system = [ setuptools ];

            meta = with lib; {
              homepage = "https://github.com/au-ts/microkit_sdf_gen";
              maintainers = with maintainers; [ au-ts ];
            };

            ZIG_LOCAL_CACHE_DIR="/tmp/zig-cache-local";
            ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache-global";

            nativeBuildInputs = [ zig ];
          };

        pythonWithSdfgen = pkgs.python313.withPackages (ps: [
          pysdfgen
        ]);
      in
      {
        devShells.default = pkgs.mkShell rec {
          name = "dev";

          nativeBuildInputs = with pkgs; [
            dtc
            zig
            python313
            sphinx
          ];
        };

        devShells.ci = pkgs.mkShell rec {
          name = "ci";

          env.ZIG_LOCAL_CACHE_DIR="/tmp/zig-cache-local";
          env.ZIG_GLOBAL_CACHE_DIR="/tmp/zig-cache-global";

          nativeBuildInputs = with pkgs; [
            dtc
            zig
            pythonWithSdfgen
            sphinx
          ];
        };
      });
}
