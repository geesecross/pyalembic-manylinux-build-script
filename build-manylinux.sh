#!/bin/bash
set -eux

# Run this within the manylinux2014 image. For example:
# docker run --rm -it -v `pwd`:/io quay.io/pypa/manylinux2014_x86_64 /bin/bash /io/build-manylinux.sh

BOOST_SRC_URL=${BOOST_SRC_URL:-https://boostorg.jfrog.io/artifactory/main/release/1.80.0/source/boost_1_80_0.tar.gz}
IMATH_BRANCH=${IMATH_BRANCH:-v3.1.6}
ALEMBIC_BRANCH=${ALEMBIC_BRANCH:-1.8.4}

# Python targets to build wheels: the default is to build all python 3.x versions available in manylinux image.
PYTHON_TARGETS=${PYTHON_TARGETS:-/opt/python/cp3*/bin/python}
# or you can assign a specific version:
# PYTHON_TARGETS="python3.7 python3.8"

# the new package name of PyAlembic. default is 'PyAlembic,' which is same as gohlke's unofficial build.
PYALEMBIC_PACKAGE_NAME=${PYALEMBIC_PACKAGE_NAME:-PyAlembic}

pushd /tmp
    if [ ! -d boost ]; then
        # We must have boost-python library binaries for each python distributions
        # and it cannot be achived by installing a pre-built package.
        
        if [ ! -f boost.tar.gz ]; then
            if [ -f /io/boost.tar.gz ]; then
                # if we prepared boost.tar.gz source codes, then we can use it instead of downloading it.
                ln -s /io/boost.tar.gz boost.tar.gz
            else
                # veeeeeery slow
                curl -o boost.tar.gz -L ${BOOST_SRC_URL}
            fi
        fi
        mkdir -p boost && tar -xzf boost.tar.gz --strip-components 1 -C boost
    fi

    if [ ! -d Imath ]; then
        git clone --branch ${IMATH_BRANCH} --depth 1 https://github.com/AcademySoftwareFoundation/Imath.git
    fi
    pushd Imath
        # Dark magic to work with recent CMake versions(>=3.18) & manylinux docker image.
        # manylinux dockers do not have static library of Python (libpython*.so)
        # and we cannot meet Development or Development.Embed target requirement.
        # Hopefully, the python embedding is actually not required to make modules,
        # so we are okay to modify the build target to Development.Module.
        sed -i 's/COMPONENTS Interpreter Development)/COMPONENTS Interpreter Development.Module)/g' src/python/CMakeLists.txt
        find ./src -type f -exec sed -i 's/Python3::Python/Python3::Module/g' {} \;
        find ./src -type f -exec sed -i 's/if(Python3::Module)/if(TARGET Python3::Module)/g' {} \;

        # prepare a build directory for the later operations
        mkdir -p build
    popd

    if [ ! -d alembic ]; then
        git clone --branch ${ALEMBIC_BRANCH} --depth 1 https://github.com/alembic/alembic.git
    fi
    pushd alembic
        # Dark magic happens here again.
        sed -i 's/COMPONENTS Interpreter Development)/COMPONENTS Interpreter Development.Module)/g' CMakeLists.txt
        sed -i 's/DPYTHON_EXECUTABLE/DPython3_EXECUTABLE/g' setup.py

        # We will reuse this directory to build packages for every python distribtion.
        # and the previous cmake caches may be disturbing
        # so I will add --fresh switch to make it work correctly.
        sed -i "s|cmake_args = \['-DCMAKE|cmake_args = \['--fresh', '-DCMAKE|g" setup.py

        # Why should I have to do this? ;(
        ALEMBIC_VERSION=$(grep -Po '(?<=Alembic VERSION )([0-9\.]+)' CMakeLists.txt)
        sed -i "s/version='1.7.16'/version='${ALEMBIC_VERSION}'/g" setup.py

        # Unfortunately, package name 'alembic' is already occupied by SQLAlchemy, which is another famous package.
        # For the peace & love I will rename the package to another.
        sed -i "s/name='alembic'/name='${PYALEMBIC_PACKAGE_NAME}'/g" setup.py

        # Forget about the old dark magic. We do not need a manual copy of Python 2.x dependencies anymore.
        sed -i 's/for package in missing_packages:/for package in missing_packages[:0]:/g' setup.py

        # Recent machines have many cores to compile faster ;)
        sed -i "s/'-j2'/'-j$(nproc)'/g" setup.py

        # We will embed imath and imathnumpy module into PyAlembic wheels ;)
        sed -i 's|  zip_safe=False,|  packages=\[""\], package_data=\{"": \["imath.so", "imathnumpy.so"\]\}, zip_safe=False,|g' setup.py
    popd
popd

for python_target in ${PYTHON_TARGETS}; do
    python_target=$(which ${python_target})
    PYTHON_SITE_PACKAGES_DIR=$(${python_target} -c 'import site; print(site.getsitepackages()[0])')

    # numpy for Imath
    ${python_target} -m pip install numpy

    pushd /tmp/boost
        ./bootstrap.sh --with-python=${python_target}
        ./b2 -j$(nproc) install
    popd

    pushd /tmp/Imath/build
        cmake --fresh \
            -DPYTHON=ON \
            -DBUILD_TESTING=OFF \
            -DPYIMATH_OVERRIDE_PYTHON_INSTALL_DIR=${PYTHON_SITE_PACKAGES_DIR} \
            -DPython3_EXECUTABLE=${python_target} \
            ..
        make -j $(nproc) install
    popd

    pushd /tmp/alembic
        /bin/cp -f ${PYTHON_SITE_PACKAGES_DIR}/imath*.so .
        ${python_target} setup.py bdist_wheel
        for whl in dist/*.whl; do
            auditwheel repair $whl
        done
        /bin/rm -f dist/*.whl
        /bin/mv -f wheelhouse/*.whl /io/
    popd
done
