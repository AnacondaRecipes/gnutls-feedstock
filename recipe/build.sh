#!/bin/bash
set -x

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/libtool/build-aux/config.* ./build-aux

if [[ ${target_platform} =~ .*linux.* ]]; then
    export LDFLAGS="$LDFLAGS -Wl,-rpath-link,${PREFIX}/lib"
fi

export CPPFLAGS="${CPPFLAGS//-DNDEBUG/}"
#export CFLAGS="${CFLAGS//-DNDEBUG/}"
#export CXXFLAGS="${CXXFLAGS//-DNDEBUG/}"

if [[ ${target_platform} =~ osx.* ]]; then
    # To avoid 'perl: warning: Setting locale failed' before running libtoolize
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
fi

# libtoolize deletes things we need from build-aux, automake puts them back
libtoolize --copy --force --verbose
automake --add-missing --copy --verbose

declare -a configure_opts

# Get ./configure and make to go a little faster...
#configure_opts+=(--disable-dependency-tracking)
configure_opts+=(--disable-maintainer-mode)
configure_opts+=(--cache-file=test-output.log)

# Limit what we build
configure_opts+=(--enable-shared)
configure_opts+=(--disable-static)
configure_opts+=(--disable-doc)
configure_opts+=(--disable-gtk-doc)
if [[ ${target_platform} =~ osx.* ]]; then
    # Don't use zlib on osx
    configure_opts+=(--without-zlib)
fi

# Use the libraries we provide
configure_opts+=(--without-included-libtasn1)
configure_opts+=(--without-nettle-mini)
configure_opts+=(--without-included-unistring)

# Broken protocols that shouldn't be used in 2021+
configure_opts+=(--disable-ssl2-support)    # SSLv2 client hello
configure_opts+=(--disable-ssl3-support)
configure_opts+=(--disable-sha1-support)    # SHA1 cert signatures

# NOTE: must use libidn2, _not_ libidn,  to avoid security issues:
#   http://lists.gnupg.org/pipermail/gnutls-devel/2015-May/007582.html
configure_opts+=(--with-idn)

# Don't assume users will have cryptographic hardware
configure_opts+=(--disable-hardware-acceleration)   # AES-NI instructions
configure_opts+=(--without-tpm)         # support for TPM 1.2 modules
configure_opts+=(--without-p11-kit)     # support for smart cards, etc.

# Don't run very slow components of test suite
configure_opts+=(--disable-full-test-suite)
# Don't run valgrind tests
configure_opts+=(--disable-valgrind-tests)

# Language bindings
configure_opts+=(--enable-cxx)
configure_opts+=(--disable-guile)

# Interoperability
configure_opts+=(--disable-oldgnutls-interop)
configure_opts+=(--disable-openssl-compatibility)

# Use `ca-certificates` data as default trust store
configure_opts+=(--with-default-trust-store-file=$PREFIX/ssl/cert.pem)

# "System" configuration files should be in the install prefix
configure_opts+=(--with-system-priority-file=$PREFIX/etc/gnutls/config)
configure_opts+=(--with-unbound-root-key-file=$PREFIX/etc/unbound/root.key)

./configure --prefix="${PREFIX}"          \
            "${configure_opts[@]}"          \
            || { exit 1; cat config.log; exit 1; }

cat libtool | grep as-needed 2>&1 >/dev/null || \
    { echo "ERROR: Not using libtool with --as-needed fixes?"; exit 1; }

# Prevent "tests cannot be compiled with NDEBUG defined" errors
find tests -name 'Makefile' -exec sed -i.bak 's| -DNDEBUG||g' {} +

make -j${CPU_COUNT} ${VERBOSE_AT}

if [[ ${target_platform} =~ osx.* ]]; then
    # The test 'gnutls-cli-debug.sh' fails, see https://gitlab.com/gnutls/gnutls/-/issues/1539
    make -j${CPU_COUNT} check || true
else
    make -j${CPU_COUNT} -k check || \
    { find tests -name 'test-*.log' -exec egrep -A5 '^FAIL: ' {} +; exit 1; }
fi

make install
