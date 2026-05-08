# Gerrit Query Cheatsheet

For `GET /a/changes/?q=<expr>`. Expressions compose with implicit AND; use `-` to negate, `OR` for union, parentheses to group.

## Change state

| Operator | Matches |
|---|---|
| `status:open` | NEW changes |
| `status:merged` | MERGED |
| `status:abandoned` | ABANDONED |
| `status:closed` | merged + abandoned |
| `status:new` | alias of open |
| `is:wip` | work-in-progress |
| `is:submittable` | all submit requirements met |
| `is:merged` / `is:open` / `is:closed` | alias form |
| `is:private` | private changes (visible to you) |
| `is:watched` | in your watched list |
| `is:starred` | you starred it |
| `is:reviewed` | has any non-zero vote |
| `has:draft` | you have draft comments |
| `has:unresolved` | unresolved comments exist |
| `has:edit` | you have an edit in progress |

## Location

| Operator | Matches |
|---|---|
| `project:foo` | exact project |
| `projects:foo` | project prefix (matches foo, foo/bar) |
| `parentproject:foo` | under parent project |
| `branch:master` | exact branch |
| `intopic:release` | topic contains substring |
| `topic:exact-topic` | exact topic |
| `ref:refs/heads/stable` | full ref |
| `hashtag:release` | hashtag |

## People

`{user}` = `self`, numeric id, username, email, `"Full Name <email>"`, or group name (group:NAME).

| Operator | Matches |
|---|---|
| `owner:{user}` | author |
| `author:{user}` | commit author (may differ from owner) |
| `committer:{user}` | commit committer |
| `reviewer:{user}` | any role reviewer |
| `assignee:{user}` | assignee (legacy; replaced by attention set) |
| `attention:{user}` | on attention set |
| `cc:{user}` | on CC list |
| `reviewedby:{user}` | someone voted |
| `ownerin:{group}` / `reviewerin:{group}` | owner/reviewer is in group |

## Labels & votes

| Operator | Matches |
|---|---|
| `label:Code-Review=+2` | exact vote |
| `label:Code-Review>=+1` | range |
| `label:Code-Review=+2,user=alice` | vote by specific user |
| `label:Verified=-1` | fail |
| `label:Code-Review=MAX` / `=MIN` | symbolic |

## Age

| Operator | Matches |
|---|---|
| `age:1d` | updated at least N ago |
| `age:2h` | hours |
| `before:2026-04-21` / `until:...` | updated before date |
| `after:2026-04-01` / `since:...` | updated after date |
| `mergedbefore:2026-04-01` / `mergedafter:...` | merged date |

## Content

| Operator | Matches |
|---|---|
| `message:"fix bug"` | commit message substring |
| `file:src/foo.c` | file path |
| `path:src/foo.c` | alias |
| `ext:java` | extension |
| `footer:Fixes=ABC-123` | commit footer |
| `added:"TODO"` / `deleted:"FIXME"` | added/removed text |

## Size

| Operator | Matches |
|---|---|
| `added:>100` | lines added |
| `deleted:>50` | lines deleted |
| `size:L` | size bucket |

## Combining

```
status:open project:foo -is:wip -age:7d
owner:self OR reviewer:self
(branch:master OR branch:release-*) label:Verified>=0
```

Wildcards: `branch:release-*`, `topic:feat-*`, `file:^.*\.java$` (regex with `^`).

---

## Output Options (`o` parameter, repeatable)

| Option | Adds to response |
|---|---|
| `LABELS` | `labels` dict with approval summary |
| `DETAILED_LABELS` | `labels` + `permitted_voting_range` |
| `CURRENT_REVISION` | `current_revision` + `revisions{current_sha}` |
| `ALL_REVISIONS` | `revisions{}` for every patchset |
| `CURRENT_COMMIT` | commit message + author/committer on current rev |
| `ALL_COMMITS` | same for all revisions |
| `CURRENT_FILES` | `files{}` on current rev |
| `ALL_FILES` | `files{}` on every rev |
| `DETAILED_ACCOUNTS` | adds `email`, `username` to all AccountInfo |
| `REVIEWER_UPDATES` | reviewer add/remove history |
| `MESSAGES` | change messages list |
| `CURRENT_ACTIONS` | available actions on current rev |
| `CHANGE_ACTIONS` | available actions on change |
| `REVIEWED` | whether you've reviewed |
| `SUBMITTABLE` | `submittable` bool |
| `WEB_LINKS` | `web_links[]` |
| `CHECK` | consistency check results |
| `COMMIT_FOOTERS` | rendered commit with footers |
| `PUSH_CERTIFICATES` | signed push certs |
| `TRACKING_IDS` | cross-system tracking IDs |
| `NO_LIMIT` | disable result cap (also `&no-limit`) |
| `SKIP_MERGEABLE` | skip mergeability computation (faster) |
| `SKIP_DIFFSTAT` | skip insertions/deletions (faster) |

## Common bundles for bots

**Minimum for polling (light):**
```
o=CURRENT_REVISION
```

**Polling with file list (medium):**
```
o=CURRENT_REVISION&o=CURRENT_FILES&o=DETAILED_ACCOUNTS
```

**Full review context (heavy — use sparingly):**
```
o=CURRENT_REVISION&o=CURRENT_COMMIT&o=CURRENT_FILES
&o=DETAILED_LABELS&o=DETAILED_ACCOUNTS&o=MESSAGES&o=SUBMITTABLE
```

**Backfill / history reconstruction:**
```
o=ALL_REVISIONS&o=ALL_COMMITS&o=ALL_FILES&o=MESSAGES&o=REVIEWER_UPDATES
```
