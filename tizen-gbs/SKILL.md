---
name: tizen-gbs
description: Use when the user asks about Tizen GBS (Git Build System), `gbs build`, `.gbs.conf` configuration, building Tizen packages or full Tizen images, repo manifest sync for Tizen, OBS repository URLs, or troubleshooting Tizen RPM builds. Covers single-package and full-platform builds, profile/repo sections, architecture flags, clean/incremental modes, and snapshot URL patterns. Sources: docs.tizen.org/platform/developing/building, /building-all, /reference/gbs/gbs.conf, /reference/gbs/gbs-build.
---

# Tizen GBS (Git Build System) — Reference Skill

This skill is a distilled, hands-on reference for using `gbs` and authoring `.gbs.conf`. Apply it whenever the user is working on Tizen packages, OBS-backed builds, or full Tizen platform builds.

---

## 1. When this skill applies

Trigger on any of:
- Mentions of `gbs`, `.gbs.conf`, `GBS-ROOT`, OBS, `repo init -u .../scm/manifest`, `tizen.org`, `Tizen:Base`, `Tizen:Unified`.
- Files: `packaging/*.spec`, `*_build.conf`, manifests under `.repo/manifests/`.
- Commands the user wants to run on a Tizen source tree (`gbs build`, `gbs export`, `gbs remotebuild`, `gbs submit`, `gbs chroot`, `gbs clone`, `gbs import`, `gbs changelog`, `gbs devel`).

If the user is on a non-Tizen RPM project, this skill is **not** applicable.

---

## 2. Mental model

```
project source (git, with packaging/*.spec)
        │
        ▼
gbs build  ──reads──►  .gbs.conf  ──references──►  [profile.X] ──► [repo.Y] URLs (remote OBS snapshots)
        │                                                   └──► local repo ~/GBS-ROOT/local/repos/<profile>/<arch>
        ▼
build root: ~/GBS-ROOT/local/BUILD-ROOTS/scratch.<arch>.<N>
        │
        ▼
output RPM/SRPM/log: ~/GBS-ROOT/local/repos/<profile>/<arch>/{RPMS,SRPMS,logs}
```

Key rule: **output of one build feeds the next** — local repo is consulted automatically before remote.

---

## 3. `.gbs.conf` — complete reference

### 3.1 File precedence (highest first)
1. `$PWD/.gbs.conf` (project)
2. `~/.gbs.conf` (user)
3. `/etc/gbs.conf` (system)
4. Override anything with `gbs -c <path>`.

If none exists, GBS auto-generates `~/.gbs.conf` on first run.

### 3.2 Section types

| Section | Purpose |
|---|---|
| `[general]` | Global defaults; selects active profile |
| `[profile.<name>]` | Named build target (combines repos + options) |
| `[repo.<name>]` | A package repository (URL + auth) |
| `[obs.<name>]` | A remote OBS server (for `gbs remotebuild`/`submit`) |

### 3.3 `[general]` keys

| Key | Meaning |
|---|---|
| `profile` | Active profile (must equal a `[profile.X]` section name, including the `profile.` prefix) |
| `tmpdir` | Scratch dir for GBS internals |
| `work_dir` | Working directory; usable as `${work_dir}` elsewhere |
| `upstream_branch` | Default upstream branch for git-buildpackage style trees |
| `upstream_tag` | Default tag pattern (e.g. `upstream/%(version)s`) |
| `packaging_dir` | Default `packaging/` location inside each project |
| `buildroot` | Default build root path (overridden by profile) |
| `native` | `true`/`false` — native vs non-native packaging |
| `fallback_to_native` | Permit non-native packages to fall back |
| `optional_keyfiles` | Comma-separated GPG keyfiles for repo verification |

### 3.4 `[profile.<name>]` keys

| Key | Meaning |
|---|---|
| `repos` | Ordered comma-separated list of `[repo.X]` section names; **later entries override earlier** |
| `obs` | Reference to an `[obs.X]` section for remotebuild/submit |
| `buildroot` | Override per-profile build root |
| `buildconf` | Path to a `*_build.conf` (project build config) |
| `exclude_packages` | Comma-separated package names to skip |
| `user`, `passwd` | Default credentials applied to child repos/obs |
| `packaging_branch` | Branch holding spec/changelog |

### 3.5 `[repo.<name>]` keys

| Key | Meaning |
|---|---|
| `url` | Repo root containing `repodata/` (HTTP, HTTPS, or `file://`) |
| `user`, `passwd` | Optional auth (cleartext on first run) |
| `passwdx` | Auto-encoded form of `passwd`; overwrite by re-setting `passwd` |

### 3.6 `[obs.<name>]` keys (for `gbs remotebuild`/`submit`)

| Key | Meaning |
|---|---|
| `url` | OBS API endpoint (e.g. `https://api.tizen.org`) |
| `user`, `passwd` | OBS credentials (encoded as `passwdx`) |
| `base_prj` | Base project (e.g. `Tizen:Unified`) |
| `target_prj` | Submission target |

### 3.7 Variable expansion (GBS ≥ 0.17)
`[general]` keys are usable as `${name}` shell-style refs in any section.

```ini
[general]
work_dir = /home/me/tizen
buildconf = ${work_dir}/scm/meta/build-config/9.0/unified/standard_build.conf
```

### 3.8 Password handling
Plain `passwd = secret` is rewritten as `passwdx = <base64-encoded>` after first run. To rotate, delete `passwdx` and re-add `passwd`.

### 3.9 Snapshot URL pattern (Tizen)
```
http://download.tizen.org/{snapshots|releases/daily}/tizen/<profile>/<release_id>/repos/<repository>/packages/
```
- `<profile>`: `unified`, `base`, `iot-headed`, `iot-headless`, `tv`, `da`, `mobile`, ...
- `<repository>`: `standard`, `emulator`, `wayland`, ...
- `<release_id>`: e.g. `tizen-unified_20260417.1` or `latest`.

Pin to a dated `<release_id>` for reproducibility; use `latest` only to track HEAD.

### 3.10 Canonical example

```ini
[general]
profile = profile.unified_standard
work_dir = /home/me/tizen
upstream_branch = upstream
upstream_tag = upstream/%(version)s

[profile.unified_standard]
repos = repo.base_standard, repo.base_standard_debug, repo.unified_standard
buildconf = ${work_dir}/scm/meta/build-config/9.0/unified/standard_build.conf
exclude_packages = some-broken-pkg

[repo.base_standard]
url = http://download.tizen.org/snapshots/tizen/base/latest/repos/standard/packages/

[repo.base_standard_debug]
url = http://download.tizen.org/snapshots/tizen/base/latest/repos/standard/debug/

[repo.unified_standard]
url = http://download.tizen.org/snapshots/tizen/unified/latest/repos/standard/packages/

[obs.tizen]
url    = https://api.tizen.org
user   = myuser
passwd = mypass        # becomes passwdx after first run
```

---

## 4. `gbs build` — complete reference

### 4.1 Architecture & dist
| Flag | Use |
|---|---|
| `-A, --arch` | `x86_64`, `i586`, `armv7l`, `armv7hl`, `aarch64`, `armv6l`, `mips`, `mipsel` |
| `--dist` | Distro/profile name override |
| `-D` | Custom project build-config file |
| `-P, --profile` | Profile from `.gbs.conf` (use bare name, GBS adds `profile.` prefix) |
| `-c <file>` | Use a non-default `.gbs.conf` |

### 4.2 Build-root management
| Flag | Use |
|---|---|
| `-B, --buildroot` | Custom build root (overrides `$TIZEN_BUILD_ROOT`) |
| `--clean` | Wipe build root **every package** (use after repo URL change) |
| `--clean-once` | Wipe build root **once** at start (recommended for fresh runs) |
| `--clean-repos` | Drop `~/GBS-ROOT/local/repos/<profile>/<arch>` cache |
| `--keep-packs` | Keep installed packages in build root between packages |
| `--noinit` | Offline mode: reuse existing build root, skip dep resolution |

### 4.3 Package selection
| Flag | Use |
|---|---|
| `--binary-list=a,b,c` | Build only these |
| `--binary-from-file=PATH` | Same, from file |
| `--exclude=a,b` / `--exclude-from-file=PATH` | Skip these |
| `--deps` | Include forward deps of selection |
| `--rdeps` | Include reverse deps |
| `--overwrite` | Rebuild packages that already exist in local repo |

### 4.4 Source/spec handling
| Flag | Use |
|---|---|
| `--include-all` | Include uncommitted + untracked changes |
| `--commit=<sha>` | Build at specific commit |
| `--spec=PATH` | Use non-default spec |
| `--packaging-dir=PATH` | Override `packaging/` |
| `--upstream-branch=`, `--upstream-tag=` | Override gbp settings |
| `--squash-patches-until=<sha>` | Collapse patches |
| `--define='macro value'` | Inject RPM macro |
| `--skip-srcrpm` | Don't write SRPM |

### 4.5 Performance
| Flag | Use |
|---|---|
| `--threads=N` | Worker count for parallel package builds |
| `--jobs=N` | `make -jN` inside each package |
| `--ccache` | Enable ccache |
| `--icecream=N` | Distributed compile via icecc |
| `--kvm` | Use KVM-accelerated build VM |

### 4.6 Variants & verification
| Flag | Use |
|---|---|
| `--debuginfo` | Emit `*-debuginfo` RPMs |
| `--baselibs` | Build baselibs |
| `--no-verify` | Skip GPG signature checks (avoid unless necessary) |
| `--skip-conf-repos` | Ignore `repos=` from `.gbs.conf`; use only `-R` |
| `-R, --repository=PATH` | Add extra repo (URL or local dir) |
| `--extra-packs=a,b` | Pre-install in build root |

### 4.7 Incremental dev loop
```bash
gbs build -A armv7l --incremental                 # initial
# edit source...
gbs build -A armv7l --incremental --noinit        # fast rebuild, no dep recheck
gbs build -A armv7l --incremental --no-configure  # skip autogen/configure
```
Restrictions: single-package builds only; ensure clean packaging.

---

## 5. Standard workflows

### 5.1 Single package (most common)
```bash
cd path/to/<package>            # has packaging/<pkg>.spec
gbs build -A armv7l --include-all
# rebuild without cache:
gbs build -A armv7l --clean-repos
# after changing .gbs.conf URLs:
gbs build -A armv7l --clean
```

### 5.2 Full Tizen platform build
```bash
mkdir -p ~/tizen && cd ~/tizen

# read-only (HTTPS)
repo init -u https://git.tizen.org/cgit/scm/manifest \
          -b tizen -m unified_standard.xml
# OR contributor (SSH)
repo init -u ssh://<user>@review.tizen.org:29418/scm/manifest \
          -b tizen -m unified_standard.xml

# (optional) pin to a snapshot
wget <Snapshot_Manifest_URL> -O .repo/manifests/unified/standard/projects.xml

repo sync -j4                   # produces .gbs.conf + scm/meta/build-config/...
gbs build -A armv7l --threads=4 --clean-once
```

Manifest naming convention: `<profile>_<repository>.xml` (e.g. `unified_standard.xml`, `unified_emulator.xml`, `base_standard.xml`).

Branch options:
- `tizen` — latest
- `tizen_X.Y` — specific version (e.g. `tizen_9.0`)

### 5.3 Switching to HTTPS after SSH init
```bash
sed -i 's|ssh://review.tizen.org|https://git.tizen.org/cgit|' \
    .repo/manifests/_remote.xml
```

### 5.4 Submitting upstream
```bash
gbs remotebuild -T <obs_target_project>     # OBS pre-check
gbs submit -m "fix: ..." -c <commit>        # tag + push to gerrit
```

---

## 6. Performance tips

- **tmpfs build root** (≥ 8 GB RAM):
  ```bash
  mkdir -p ~/GBS-ROOT/local/BUILD-ROOTS
  sudo mount -t tmpfs -o size=16G tmpfs ~/GBS-ROOT/local/BUILD-ROOTS
  ```
- Combine `--threads` (parallel packages) with `--jobs` (per-package make).
- Use `--ccache` for iterative work on the same package.
- `--keep-packs --noinit` for back-to-back builds in identical environments.

---

## 7. Build artifact layout

```
~/GBS-ROOT/
├── local/
│   ├── BUILD-ROOTS/
│   │   └── scratch.<arch>.<N>/        # transient chroot
│   ├── cache/                         # downloaded remote RPMs
│   └── repos/
│       └── <profile>/
│           └── <arch>/
│               ├── RPMS/              # output binary RPMs
│               ├── SRPMS/             # output source RPMs
│               └── logs/              # per-package build logs
└── ...
```

---

## 8. Troubleshooting playbook

| Symptom | Likely cause | Action |
|---|---|---|
| `nothing provides X` | Missing repo or stale snapshot | Add `[repo.X]` for `Tizen:Base` snapshot; `--clean` |
| `cycle detected` | Cyclic deps from Base project | Ensure base_standard repo is listed **before** unified |
| Hangs on `Init build root` | Stale build root after URL change | `--clean` (not just `--clean-repos`) |
| `signature verification failed` | Outdated key | Refresh `optional_keyfiles` or temporarily `--no-verify` |
| Old binary used | Local repo cache shadowing remote | `--clean-repos` |
| `*-x64` accelerator conflict (Tizen <2.3) | Pre-built cross-compilers | `--exclude=<pkg>-x64` |
| `passwdx` keeps reverting | `passwd` still in file | Remove plaintext `passwd` after first encode |

---

## 9. Recipes (copy-paste)

**Reproducible nightly build pinned to a snapshot:**
```ini
[general]
profile = profile.unified_std_pinned

[profile.unified_std_pinned]
repos = repo.base, repo.unified

[repo.base]
url = http://download.tizen.org/snapshots/tizen/base/tizen-base_20260417.1/repos/standard/packages/
[repo.unified]
url = http://download.tizen.org/snapshots/tizen/unified/tizen-unified_20260417.1/repos/standard/packages/
```
```bash
gbs build -A aarch64 --threads=8 --jobs=8 --clean-once --ccache
```

**Local-only build (air-gapped) using on-disk repo:**
```ini
[repo.local_base]
url = file:///srv/tizen-mirror/base/standard/packages/
```

**Build current package + everything that depends on it:**
```bash
gbs build -A armv7l --binary-list=$(basename $PWD) --rdeps
```

**Skip `.gbs.conf` repos and use a one-off URL:**
```bash
gbs build -A armv7l --skip-conf-repos \
  -R http://download.tizen.org/snapshots/tizen/unified/latest/repos/standard/packages/
```

---

## 10. Behavioral guidance for the agent

When the user asks to "build", "fix gbs error", or "set up `.gbs.conf`":
1. Inspect the working tree — check for `.gbs.conf`, `packaging/*.spec`, `.repo/manifest.xml` to confirm context.
2. Identify whether it's a **single-package** (project subdir with `packaging/`) or **full platform** (top of `repo sync` tree) build.
3. Show the **exact command** with `-A`, profile, and clean flags chosen by the diagnosis matrix in §8.
4. Edit `.gbs.conf` only after confirming the snapshot URL exists (suggest verifying via `curl -I <url>repodata/repomd.xml`).
5. Never blindly add `--no-verify` — first try refreshing keys.
6. For reproducible builds, pin `<release_id>` rather than `latest`.

---

## 11. Source links
- https://docs.tizen.org/platform/developing/building/
- https://docs.tizen.org/platform/developing/building-all/
- https://docs.tizen.org/platform/reference/gbs/gbs.conf/
- https://docs.tizen.org/platform/reference/gbs/gbs-build/
- https://docs.tizen.org/platform/reference/gbs/gbs-reference/
