# Build script for PyAlembic manylinux wheels

To make [manylinux](https://github.com/pypa/manylinux) .whl builds of [PyAlembic](https://github.com/alembic/alembic) for the Python 3.6 and above versions, run this command:
```
docker run --rm -it -v `pwd`:/io quay.io/pypa/manylinux2014_x86_64 /bin/bash /io/build-manylinux.sh
```

It will generate manylinux .whl builds for each python version into your working directory.

However it might take a long time to build for all python versions. If you just need builds for specific version(s) of python, use `PYTHON_TARGETS` environment variable.
```
docker ... -e PYTHON_TARGETS="python3.7 python3.8" ...
```

Generated wheel binary is designed to "batteries-included." It includes `imath` & `imathnumpy` module and some shared libraries.

You can specify which version of [alembic](https://github.com/alembic/alembic), [Imath](https://github.com/AcademySoftwareFoundation/Imat), and [boost](https://github.com/boostorg/boost) to build:
```
docker ... \
    -e BOOST_SRC_URL=https://boostorg.jfrog.io/artifactory/main/release/1.80.0/source/boost_1_80_0.tar.gz \
    -e IMATH_BRANCH=v3.1.6 \
    -e ALEMBIC_BRANCH=1.8.4 \
    ...
```

The script automatically download the required source codes from the web.

Note that downloading the Boost source code might take a long time. If you prepare the Boost source code as `boost.tar.gz` into your working directory, the script will bypass the download phase.

For more details, refer `build-manylinux.sh` script.