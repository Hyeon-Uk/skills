---
name: tizen-gerrit
description: Gerrit code review system operations for Tizen development. Use when working with Gerrit repositories, code reviews, or patch management including: (1) cloning repositories via HTTPS or SSH, (2) fetching specific change/patchset refs, (3) submitting code reviews with git push to refs/for/<branch>, (4) setting up SSH keys for Gerrit, (5) cherry-picking or reviewing patches from review.tizen.org or any Gerrit instance. Triggers on: "gerrit", "review.tizen.org", "refs/changes", "git review", "patchset", "fetch change", "code review", "gerrit clone".
---

# Tizen Gerrit

Gerrit is a Git-based code review system. All operations use standard `git` commands plus Gerrit-specific refs.

## Clone Repository

```bash
# HTTPS (read-only or authenticated)
git clone https://review.tizen.org/gerrit/p/<project-path>

# SSH (recommended for contribution, requires SSH key setup)
git clone ssh://<username>@review.tizen.org:29418/<project-path>
```

Example:
```bash
git clone https://review.tizen.org/gerrit/p/platform/core/appfw/pkgmgr-info
```

## Fetch a Specific Change (Patchset)

```bash
# From Gerrit UI: Change → Download → copy "Checkout" command
git fetch <remote-url> refs/changes/<XX>/<change-id>/<patchset> && git checkout FETCH_HEAD

# Example: Change 123456, patchset 3
git fetch https://review.tizen.org/gerrit/p/<project> \
  refs/changes/56/123456/3 && git checkout FETCH_HEAD
```

The `<XX>` is the last two digits of the change number.

## Submit Code for Review

```bash
# Push to refs/for/<target-branch>
git push origin HEAD:refs/for/tizen

# Push with topic
git push origin HEAD:refs/for/tizen%topic=my-feature

# Push as draft (WIP)
git push origin HEAD:refs/for/tizen%wip
```

## Install Gerrit Change-ID Hook (required for reviews)

```bash
# Run once per repo — adds commit-msg hook that appends Change-Id
scp -p -P 29418 <username>@review.tizen.org:hooks/commit-msg .git/hooks/
chmod +x .git/hooks/commit-msg
```

## SSH Key Setup

```bash
# 1. Generate key
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# 2. Copy public key
cat ~/.ssh/id_rsa.pub

# 3. Add to Gerrit: Settings → SSH Public Keys → paste

# 4. Verify connection
ssh -p 29418 <username>@review.tizen.org
```

## Useful Git Config for Gerrit

```bash
git config user.email "your-gerrit-email@example.com"
git config user.name "Your Name"

# Push alias
git config alias.review "push origin HEAD:refs/for/tizen"
```

## References

- See `references/tizen-gerrit-workflows.md` for Tizen-specific contribution workflows (fork → patch → review).
