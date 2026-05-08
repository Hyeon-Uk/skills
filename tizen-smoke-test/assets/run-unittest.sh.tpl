### Pattern A — paste inside the .spec %install section, AFTER %make_install
###
### Substitutions handled by `sed -i` after install:
###   <NAME>      → the package or sub-package name (passed below the heredoc)
###
### Optional: if the suite needs SMACK labels or staged fixtures, uncomment
### the set_perm / fixture lines below.

cat << EOF > run-unittest.sh
#!/bin/sh
# Optional gcov env — used when the package is built with coverage on.
# GCOV_PATH="/tmp/home/abuild/rpmbuild/BUILD"
# PACKAGE="<NAME>-%{version}"

# Optional helper: required only if the test binary writes to /tmp/home/
# or anywhere SMACK-protected. Leave commented out otherwise.
# set_perm() {
#     /usr/bin/find /tmp/home/ -print | /usr/bin/xargs -n1 /usr/bin/chsmack -a "System::Run" &> /dev/null
#     /usr/bin/find /tmp/home/ -print | /usr/bin/xargs -n1 /usr/bin/chsmack -a "System::Run" -t &> /dev/null
#     /usr/bin/chmod -R 777 /tmp/home/
# }

setup() {
    echo "setup start"
    # /usr/bin/mkdir -p "\${GCOV_PATH}/\${PACKAGE}"
    # set_perm
}

test_main() {
    echo "test_main start"
    # export "GCOV_PREFIX=/tmp"

    # Stage any on-device test fixtures the suite needs at runtime, e.g.:
    # /usr/bin/mkdir -p /tmp/<NAME>-certs
    # /usr/bin/cp -f %{_datadir}/<NAME>-unittests/certs/* /tmp/<NAME>-certs/

    /usr/bin/<NAME>_unittests
    # Or, to gate to a smoke subset:
    # /usr/bin/<NAME>_unittests --gtest_filter='*Smoke*:*BasicSanity*'
}

teardown() {
    echo "teardown start"
    # set_perm
}

main() {
    setup
    test_main
    teardown
}

main "\$*"
EOF

mkdir -p %{buildroot}%{_bindir}/tizen-unittests/%{name}
install -m 0755 run-unittest.sh %{buildroot}%{_bindir}/tizen-unittests/%{name}/
sed -i -e 's/<NAME>/<pkg>/g' %{buildroot}%{_bindir}/tizen-unittests/%{name}/run-unittest.sh

### For multi-sub-package projects (see bundle.spec), repeat the install/sed
### per sub-package, e.g.:
# mkdir -p %{buildroot}%{_bindir}/tizen-unittests/parcel
# install -m 0755 run-unittest.sh %{buildroot}%{_bindir}/tizen-unittests/parcel/
# sed -i -e 's/<NAME>/parcel/g' %{buildroot}%{_bindir}/tizen-unittests/parcel/run-unittest.sh
