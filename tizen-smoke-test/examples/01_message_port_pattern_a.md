# Example — adding Pattern A smoke to message-port

This is the most common scenario: the package has an existing
`*_unittests` binary, and you want to add the standard
`tizen-unittests/<pkg>/run-unittest.sh` post-install runner.

## Phase 1 — Worksheet

```
Package:           message-port
Failure mode:      "the message-port-unittests binary doesn't run on a freshly-
                   installed image because the spec forgot to package one of
                   the .so files it links against"
Pattern selected:  A — post-install runner wrapping message-port_unittests
Signal:            /usr/bin/message-port_unittests exits 0
Pass criterion:    exit code 0
Fail criterion:    any non-zero exit
Time budget:       under 30 seconds
Boundary:          in-process; the unit tests already mock everything they need
```

Checklist:
- [x] Failure mode written in one sentence.
- [x] Time budget bounded.
- [x] No reliance on network / specific user / non-default services.
- [x] No `bash`isms (script will be `/bin/sh`).

## Phase 2 — `.spec` edits

**Inside `%install`, after `%make_install`:**

```spec
cat << EOF > run-unittest.sh
#!/bin/sh
setup() {
    echo "setup start"
}

test_main() {
    echo "test_main start"
    /usr/bin/<NAME>_unittests
}

teardown() {
    echo "teardown start"
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
sed -i -e 's/<NAME>/message-port/g' %{buildroot}%{_bindir}/tizen-unittests/%{name}/run-unittest.sh
```

**Add to `%files unittests`:**

```spec
%files unittests
%{_bindir}/message-port_unittests
%{_bindir}/tizen-unittests/%{name}/run-unittest.sh
```

## Phase 3 — Build + run

```bash
cd ~/.openclaw/workspace/gerrit/message-port
gbs build -A x86_64 --include-all

# After install on the device:
sdb root on
sdb shell /usr/bin/tizen-unittests/message-port/run-unittest.sh
echo $?    # 0 = pass
```

If the runner exits non-zero, look at:

```bash
sdb shell dlogutil -d MESSAGE_PORT
```

…the actual diagnostic almost always lives in dlog, not in the runner's stdout.
