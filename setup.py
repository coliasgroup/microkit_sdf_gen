from setuptools import setup, Extension
from pathlib import Path

from builder import ZigBuilder

sdfgen = Extension("sdfgen", sources=["module.c"])

setup(
    name="sdfgen",
    version="0.0.2",
    url="https://github.com/Ivan-Velickovic/microkit_sdf_gen",
    description="Automating the creation of Microkit System Description Files (SDF)",
    ext_modules=[sdfgen],
    cmdclass={"build_ext": ZigBuilder},
    long_description=(Path(__file__).parent / "README.md").read_text(encoding="utf-8"),
    long_description_content_type="text/markdown",
    py_modules=["builder"],
)
