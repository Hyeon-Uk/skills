# Which smoke pattern fits this package?

Quick lookup: given a package, which of Pattern A / B / C should you use?

## Decision tree

```
Does <pkg> install/uninstall other packages
(rpk-installer, wgt-backend, tpk-backend, unified-backend, app-installers)?
│
├── Yes → Pattern B (separate smoke gtest binary)
│
└── No → Does <pkg> already have a *_unittests binary?
         │
         ├── Yes → Pattern A (run-unittest.sh wrapping the existing binary)
         │
         └── No  → Does the package have *any* C++ test infrastructure
                   (test/, tests/, unit_tests/)?
                   │
                   ├── Yes → Pattern C (single smoke_test.cc inside unit_tests/)
                   │         then add a Pattern A runner around it later.
                   │
                   └── No  → Build the unittests binary first, then Pattern A.
                             Smoke without a target binary is just a shell
                             script that does nothing useful.
```

## Examples from the workspace

| Package                      | Pattern | Reason                                                       |
|------------------------------|---------|--------------------------------------------------------------|
| `rpc-port`                   | A       | Has `rpc-port_unittests`; runner wraps it via `--gtest_filter` not currently used. |
| `aul-1`                      | A       | `aul-unittests` exists; runner is the standard heredoc.      |
| `notification`               | A       | Same shape; `notification-unittests` + heredoc.              |
| `bundle`                     | A (×6)  | Multi-sub-package; one heredoc, six `sed`-substituted installs. |
| `app-control`                | A       | `capi-appfw-app-control-unittests` + heredoc.                |
| `pkgmgr-info`                | A       | Standard pattern.                                            |
| `wgt-backend`                | B       | Installs .wgt files; smoke = real install round trip.        |
| `tpk-backend`                | B       | Installs .tpk files.                                         |
| `rpk-installer`              | B       | Installs .rpk files.                                         |
| `unified-backend`            | B       | Multi-format installer.                                      |
| `app-installers` (common)    | B       | Common helpers used by all installer-shaped smoke suites.    |
| `capmgr`                     | C       | One critical invariant: DB schema match; `unit_tests/smoke_test.cc`. |

## Borderline cases

### "My package has no `*_unittests` binary yet — do I really need to write one?"

Yes, but you can do it incrementally:

1. Create a minimal `tests/<pkg>_unittests/` with a single trivial `TEST` —
   the unit-test skill (`tizen-gtest-unit-test`) covers this.
2. Add Pattern A around it. The runner is now wrapping a one-test binary,
   which is fine — it pins the build of the test target itself.
3. Add real tests to the unit-test target over time.

A smoke runner with nothing to invoke is just dead weight. Build the target
first, then wrap it.

### "My package is a daemon — what does smoke even check?"

For daemon packages (amd, pkgmgr-server, data-provider-master), a smoke
test should confirm:

- The daemon binary launches without crashing on a fresh image.
- Its first ipc/dbus method returns an expected response.

Pattern A with a tailored `test_main` that starts the daemon, makes one
client call, and stops the daemon is the right shape. Don't try to fit
this into a `*_unittests` binary — it's intrinsically out-of-process. If
the test grows, promote to Pattern B.

### "My package ships only Rust code — does run-unittest.sh apply?"

Yes — `bundle` already does this for `tizen_bundle_unittests` and
`tizen_parcel_unittests` (see lines 287–293 of `bundle.spec`). The runner
is shell, the binary it invokes is Rust. Same Pattern A.

## When to use multiple patterns together

A package can ship more than one. A common combination:

- **A + C**: a `unit_tests/smoke_test.cc` that pins a critical in-process
  invariant, plus a `run-unittest.sh` runner that calls
  `*_unittests --gtest_filter='*Smoke*'` on device. Pattern C produces the
  test, Pattern A delivers it.
- **A + B**: a library that also ships an installer helper. Pattern A for
  the library smoke, Pattern B for the installer. Two sub-packages, two
  smoke entry points.

Resist combining for its own sake — a smoke suite that's split for no
reason just doubles the maintenance surface. Combine only when the
patterns answer different questions.
