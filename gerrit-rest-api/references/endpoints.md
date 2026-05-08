# Gerrit REST Endpoint Catalog

All paths assume `/a/` prefix for authenticated calls. See `SKILL.md` for non-negotiable conventions (XSSI, auth, encoding).

## Changes — Change level

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/changes/` | Query changes (see `query-cheatsheet.md`) |
| `POST` | `/changes/` | Create a change (ChangeInput) |
| `GET` | `/changes/{id}` | ChangeInfo |
| `GET` | `/changes/{id}/detail` | ChangeInfo + labels + accounts |
| `GET/PUT` | `/changes/{id}/message` | Commit message |
| `GET/PUT/DELETE` | `/changes/{id}/topic` | Topic |
| `POST` | `/changes/{id}/abandon` | Abandon (AbandonInput) |
| `POST` | `/changes/{id}/restore` | Restore abandoned |
| `POST` | `/changes/{id}/rebase` | Rebase |
| `POST` | `/changes/{id}/move` | Move to branch |
| `POST` | `/changes/{id}/revert` | Create revert |
| `POST` | `/changes/{id}/submit` | Submit / merge |
| `GET` | `/changes/{id}/submitted_together` | Related submit set |
| `DELETE` | `/changes/{id}` | Delete |

## Changes — Revision level

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/changes/{id}/revisions/{rev}` | RevisionInfo |
| `GET` | `/changes/{id}/revisions/{rev}/commit` | CommitInfo |
| `GET` | `/changes/{id}/revisions/{rev}/files` | `{path -> FileInfo}` |
| `GET` | `/changes/{id}/revisions/{rev}/files/{path}/content` | Base64 file content |
| `GET` | `/changes/{id}/revisions/{rev}/diff/{path}` | DiffInfo (per-file) |
| `GET` | `/changes/{id}/revisions/{rev}/patch` | Unified patch (Base64) |
| `GET` | `/changes/{id}/revisions/{rev}/comments` | Published comments |
| `GET` | `/changes/{id}/revisions/{rev}/drafts` | Your drafts |
| `GET` | `/changes/{id}/revisions/{rev}/robotcomments` | Robot comments |
| **`POST`** | **`/changes/{id}/revisions/{rev}/review`** | **Submit ReviewInput** |
| `POST` | `/changes/{id}/revisions/{rev}/submit` | Submit this revision |
| `POST` | `/changes/{id}/revisions/{rev}/cherrypick` | Cherry-pick |

`{rev}` in `current` | commit SHA | patchset number.

## Changes — Reviewers / Attention

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/changes/{id}/reviewers` | List reviewers |
| `POST` | `/changes/{id}/reviewers` | Add reviewer (ReviewerInput) |
| `DELETE` | `/changes/{id}/reviewers/{account}` | Remove |
| `GET` | `/changes/{id}/reviewers/{account}/votes` | Votes |
| `GET/POST` | `/changes/{id}/attention` | AttentionSet (add) |
| `DELETE` | `/changes/{id}/attention/{account}` | Remove from AttentionSet |

## Accounts

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/accounts/self` | Calling account (bot self-identify) |
| `GET` | `/accounts/{id}` | `self` \| numeric \| username \| email \| "Full Name <email>" |
| `GET` | `/accounts/{id}/detail` | AccountDetailInfo |
| `GET/POST/DELETE` | `/accounts/{id}/sshkeys[/{seq}]` | SSH keys |
| `PUT/DELETE` | `/accounts/{id}/password.http` | HTTP password (deprecated; use auth tokens) |
| `GET` | `/accounts/{id}/oauthtoken` | OAuth token |
| `GET/POST/DELETE` | `/accounts/{id}/gpgkeys[/{key}]` | GPG keys |
| `GET/PUT` | `/accounts/{id}/status` | Status line |
| `GET/PUT` | `/accounts/{id}/preferences` | Preferences |
| `GET/PUT/DELETE` | `/accounts/{id}/starred.changes/{change-id}` | Starred |

## Projects

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/projects/` | List (params: `p`, `r`, `m`, `n`, `S`, `type`, `state`, `b`, `d`, `all`) |
| `GET` | `/projects/{name}` | ProjectInfo |
| `PUT` | `/projects/{name}` | Create |
| `GET/PUT` | `/projects/{name}/config` | ConfigInfo |
| `GET/POST` | `/projects/{name}/access` | ProjectAccessInfo (POST = diff add/remove) |
| `GET` | `/projects/{name}/check.access` | Permission check |
| `GET` | `/projects/{name}/branches/` | BranchInfo[] |
| `GET/PUT/DELETE` | `/projects/{name}/branches/{branch}` | Branch CRUD |
| `POST` | `/projects/{name}/branches:delete` | Batch delete |
| `GET` | `/projects/{name}/branches/{branch}/files/{path}/content` | File at HEAD |
| `GET` | `/projects/{name}/tags[/{tag}]` | TagInfo |
| `GET` | `/projects/{name}/commits/{sha}` | CommitInfo |
| `GET` | `/projects/{name}/commits/{sha}/in` | Branches/tags containing commit |
| `GET` | `/projects/{name}/commits/{sha}/files/` | `{path -> FileInfo}` |
| `GET/POST/DELETE` | `/projects/{name}/dashboards/{id}` | Dashboards |
| `GET` | `/projects/{name}/children/` | Child projects |

## Groups

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/groups/` | List |
| `GET` | `/groups/{id}` | GroupInfo |
| `PUT` | `/groups/{name}` | Create |
| `GET/POST` | `/groups/{id}/members` | Members |
| `DELETE` | `/groups/{id}/members/{account}` | Remove member |
| `GET/POST` | `/groups/{id}/groups` | Subgroups |

## Config / Plugins / Access

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/config/server/version` | Gerrit version |
| `GET` | `/config/server/info` | Server info |
| `GET` | `/config/server/capabilities` | Capabilities |
| `GET` | `/access/?project=...` | Access rights |
| `GET` | `/plugins/` | Installed plugins |

---

## Core entity fields

### ChangeInfo
- `id` · `project` · `branch` · `topic` · `change_id` · `_number`
- `subject` · `status` (`NEW`|`MERGED`|`ABANDONED`)
- `created` · `updated` · `submitted` · `insertions` · `deletions`
- `owner` (AccountInfo) · `submitter` · `current_revision`
- `revisions{<sha> -> RevisionInfo}` (needs `o=CURRENT_REVISION`/`ALL_REVISIONS`)
- `labels{<name> -> LabelInfo}` (needs `o=LABELS`/`DETAILED_LABELS`)
- `messages[]` (needs `o=MESSAGES`)
- `attention_set{<account> -> AttentionSetInfo}`
- `work_in_progress` · `has_review_started` · `mergeable` · `submittable`
- `_more_changes` (pagination hint on last item)

### RevisionInfo
- `_number` (patchset #) · `created` · `uploader`
- `ref` (`refs/changes/NN/NNNN/P`) · `fetch{<scheme> -> FetchInfo}`
- `commit` (CommitInfo) · `files{<path> -> FileInfo}`

### FileInfo
- `status` (`A`|`M`|`D`|`R`|`C`) · `binary` · `old_path`
- `lines_inserted` · `lines_deleted` · `size_delta` · `size`

### DiffInfo
- `meta_a`, `meta_b` (DiffFileMetaInfo: `name`, `content_type`, `lines`)
- `change_type` (`ADDED`|`MODIFIED`|`DELETED`|`RENAMED`|`COPIED`|`REWRITE`)
- `intraline_status` (`OK`|`ERROR`|`TIMEOUT`)
- `content[]` — DiffContent: `{a: string[], b: string[], ab: string[]}` (one of)
- `diff_header[]`

### CommentInfo
- `id` · `path` · `line` · `range` (CommentRange)
- `message` · `author` (AccountInfo) · `updated`
- `unresolved` · `in_reply_to` · `tag` · `side` (`PARENT`|`REVISION`)

### CommentRange
- `start_line`, `start_character`, `end_line`, `end_character` (all 1-indexed, end exclusive)

### ReviewInput (POST .../review body)
- `message` (string) · `tag` (string)
- `labels{<name> -> int}` · `comments{<path> -> CommentInput[]}` · `robot_comments{...}`
- `drafts` (`KEEP`|`PUBLISH`|`PUBLISH_ALL_REVISIONS`)
- `notify` (`NONE`|`OWNER`|`OWNER_REVIEWERS`|`ALL`) · `notify_details`
- `omit_duplicate_comments` (bool) · `on_behalf_of`
- `reviewers[]` (ReviewerInput) · `ready` · `work_in_progress`
- `add_to_attention_set[]` · `remove_from_attention_set[]`
- `ignore_automatic_attention_set_rules`

### CommentInput (inside ReviewInput.comments)
- `line` (omit for file-level) · `range` (CommentRange)
- `side` (`PARENT`|`REVISION`) · `message` · `unresolved`
- `in_reply_to` · `tag` · `fix_suggestions[]` (FixSuggestionInfo — robot_comments only)

### LabelInfo / ApprovalInfo
- LabelInfo: `all[] -> ApprovalInfo`, `values{"-2": "label", ...}`, `default_value`, `optional`
- ApprovalInfo: `_account_id`, `value`, `date`, `permitted_voting_range`, `tag`

### AccountInfo
- `_account_id` · `name` · `display_name` · `email` · `secondary_emails[]`
- `username` · `avatars[]` · `more_accounts` · `status` · `inactive`

### ProjectInfo / BranchInfo
- ProjectInfo: `id`, `name`, `parent`, `description`, `state`, `branches{}`, `labels{}`, `web_links[]`
- BranchInfo: `ref`, `revision`, `can_delete`, `web_links[]`

## HTTP status cheat sheet

| Code | Meaning |
|---|---|
| 200 | OK |
| 201 | Created (PUT new resource) |
| 204 | No Content (DELETE) |
| 400 | Bad input / malformed JSON / missing vote permission |
| 403 | Forbidden (anonymous vs `/a/`) |
| 404 | Not found or not visible |
| 405 | Method not allowed |
| 409 | Conflict (state, name collision) |
| 412 | Precondition failed (`If-None-Match: *`) |
| 422 | Unprocessable (ID cannot be resolved) |
| 429 | Quota exhausted |
