# Useful scripts for developing/maintaning

## release.sh

Very simple script to automate new releases to PyPI.

```sh
# Make sure to run from root of repository
./scripts/release.sh <VERSION>
```

For example: `./scripts/release.sh 0.8.0` will create a tag
called 0.8.0 and that will cause the CI to automatically build
and push the Python package to PyPI with version 0.8.0.

