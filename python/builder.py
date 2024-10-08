import os
import platform
from setuptools.command.build_ext import build_ext
import sysconfig


class ZigBuilder(build_ext):
    def build_extension(self, ext):
        assert len(ext.sources) == 1

        modpath = self.get_ext_fullpath(ext.name).split('/')
        modpath = os.path.abspath('/'.join(modpath[0:-1]))

        windows = platform.system() == "Windows"
        # self.spawn(
        #     [
        #         "zig",
        #         "build-lib",
        #         "-O",
        #         "ReleaseFast",
        #         "-lc",
        #         *(["-target", "x86_64-windows-msvc"] if windows else []),
        #         f"-femit-bin={self.get_ext_fullpath(ext.name)}",
        #         "-fallow-shlib-undefined",
        #         "-dynamic",
        #         *[f"-I{d}" for d in self.include_dirs],
        #         *(
        #             [
        #                 f"-L{sysconfig.get_config_var('installed_base')}\Libs",
        #                 "-lpython3",
        #             ]
        #             if windows
        #             else []
        #         ),
        #         ext.sources[0],
        #     ]
        # )
        self.spawn(
            [
                "zig",
                "build",
                "pysdfgen",
                "-Doptimize=ReleaseFast",
                *(["-target", "x86_64-windows-msvc"] if windows else []),
                "--prefix-lib-dir",
                f"{modpath}",
                f"-Dpysdfgen-emit={self.get_ext_filename(ext.name)}",
                # "-fallow-shlib-undefined",
                # *[f"-I{d}" for d in self.include_dirs],
                # ext.sources[0],
            ]
        )

