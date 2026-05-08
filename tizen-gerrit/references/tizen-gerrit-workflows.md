# Tizen Gerrit Contribution Workflows

## 1. First-Time Setup

```bash
# Clone your target repo
git clone ssh://<username>@review.tizen.org:29418/<project>
cd <project>

# Install commit-msg hook (required for Change-Id generation)
scp -p -P 29418 <username>@review.tizen.org:hooks/commit-msg .git/hooks/
chmod +x .git/hooks/commit-msg

# Set identity matching your Gerrit account
git config user.email "gerrit-registered-email@example.com"
git config user.name "Your Name"
```

## 2. Standard Contribution Flow

```bash
# 1. Start from the latest upstream
git fetch origin
git checkout -b my-fix origin/tizen

# 2. Make changes and commit
git add <files>
git commit -m "Fix: brief description of the change"
# commit-msg hook auto-appends Change-Id

# 3. Submit for review
git push origin HEAD:refs/for/tizen

# 4. Gerrit UI shows the review at:
#    https://review.tizen.org/gerrit/#/c/<change-id>/
```

## 3. Update an Existing Patchset (Amend)

```bash
# Make additional changes
git add <files>
git commit --amend   # Keep the same Change-Id — DO NOT change it

# Push the updated patchset
git push origin HEAD:refs/for/tizen
# Gerrit automatically creates Patchset 2, 3, etc.
```

## 4. Review and Apply Someone Else's Change

```bash
# From Gerrit UI: Copy "Checkout" command from Download section
git fetch https://review.tizen.org/gerrit/p/<project> \
  refs/changes/<XX>/<change-id>/<patchset>
git checkout FETCH_HEAD

# Or cherry-pick into current branch
git fetch https://review.tizen.org/gerrit/p/<project> \
  refs/changes/<XX>/<change-id>/<patchset>
git cherry-pick FETCH_HEAD
```

## 5. Working with TizenFX Fork on GitHub + Gerrit

```bash
# Clone from GitHub fork
git clone https://github.com/Hyeon-Uk/TizenFX.git
cd TizenFX

# Add upstream Tizen Gerrit as remote
git remote add tizen ssh://<username>@review.tizen.org:29418/platform/core/csapi/tizenfx

# Sync with Tizen upstream
git fetch tizen
git rebase tizen/tizen

# Submit upstream contribution
git push tizen HEAD:refs/for/tizen
```

## 6. Common Gerrit Query Patterns (CLI)

```bash
# Install gerrit-query or use SSH
ssh -p 29418 <username>@review.tizen.org gerrit query \
  --format JSON status:open project:<project-name> limit:10

# List open changes for a project
ssh -p 29418 <username>@review.tizen.org gerrit query \
  --format JSON "project:platform/core/appfw/pkgmgr-info status:open"
```

## Key URLs

| Resource | URL |
|----------|-----|
| Tizen Gerrit | https://review.tizen.org/gerrit |
| Tizen Git | https://git.tizen.org |
| Tizen Dev Docs | https://docs.tizen.org |
