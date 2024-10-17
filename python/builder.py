import os
import platform
from setuptools.command.build_ext import build_ext
import sysconfig


class ZigBuilder(build_ext):
    def build_extension(self, ext):
        assert len(ext.sources) == 1

        modpath = self.get_ext_fullpath(ext.name).split('/')
        modpath = os.path.abspath('/'.join(modpath[0:-1]))

        include_args = [f"-Dpython-include={include}" for include in self.include_dirs]
        args = [
            "zig",
            "build",
            "python",
            # "-Doptimize=ReleaseFast",
            f"-Dpysdfgen-emit={self.get_ext_filename(ext.name)}",
            "--prefix-lib-dir",
            f"{modpath}",
        ]
        args.extend(include_args)

        cwd = os.getcwd()
        os.chdir("/Users/ivanv/ts/microkit_sdf_gen/python")

        self.spawn(args)

        os.chdir(cwd)
