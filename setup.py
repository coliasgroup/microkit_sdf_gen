import os
from setuptools.command.build_ext import build_ext
from setuptools import setup, Extension, find_packages
from pathlib import Path

csdfgen = Extension("csdfgen", sources=[], depends=["src/c/sdfgen.h"], include_dirs=["src/c/"])


class ZigBuilder(build_ext):
    def build_extension(self, ext):
        modpath = self.get_ext_fullpath(ext.name).split('/')
        modpath = os.path.abspath('/'.join(modpath[0:-1]))

        # include_args = [f"-Dpython-include={include}" for include in self.include_dirs]
        print(f"ext.name: {self.get_ext_filename(ext.name)}")
        args = [
            "zig",
            "build",
            "c",
            "-Doptimize=ReleaseSafe",
            "-Dc-dynamic=true",
            f"-Dcsdfgen-emit={self.get_ext_filename(ext.name)}",
            "--prefix-lib-dir",
            f"{modpath}",
        ]
        # args.extend(include_args)

        self.spawn(args)


setup(
    name="sdfgen",
    version="0.2.0",
    url="https://github.com/au-ts/microkit_sdf_gen",
    description="Automating the creation of Microkit System Description Files (SDF)",
    packages=["sdfgen"],
    package_dir={
        "sdfgen": "./python"
    },
    # Necessary for mypy to work
    package_data={"sdfgen": ["py.typed"]},
    ext_modules=[csdfgen],
    cmdclass={"build_ext": ZigBuilder},
    long_description=(Path(__file__).parent / "README.md").read_text(encoding="utf-8"),
    long_description_content_type="text/markdown",
    # py_modules=["builder"],
)
