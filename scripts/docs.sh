#!/bin/bash

PATH=$(pwd)/venv/bin/:$PATH
cd docs/python
make html
cd ..
