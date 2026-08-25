# Platform adapter — GitHub

The core speaks in **abstract operations**. This file says how to run them on the forge MotifPath
actually uses: GitHub, across all four repos (`motifpath/motifpath-core`, `motifpath/motifpath-web`,
`motifpath/motifpath-infra`, `motifpath/motifpath-specs`).

Prefer the `gh` CLI (already permitted in this project's settings) for anything the core needs
during a review. Fall back to the `mcp__github__*` tools when `gh` can't express the operation
(e.g. posting a single review with N inline comments in one call).

## Required operations

| Operation | What it must return | Used in |
|---|---|---|
| `read_metadata` | title, description, base/head branch, author, state | Phase 2 |
| `list_files` | changed paths (to detect scope) | Phase 0 |
| `read_diff` | full diff, with anchorable line numbers | Phase 3 |
| `list_discussion` | **all** line comments, general comments, and reviews — bot and human, resolved and open, **paginated** | Phase 3 |
| `publish_single_review` | publishes N anchored comments in **one** review | Phase 7 |
| `reply_in_thread` | replies to an existing comment by its id | Phase 7 |
| `list_open_changes` | other PRs open in the same repo (item 20) | Phase 4 |

## Command mapping

```
read_metadata:        gh pr view <PR> --json title,body,baseRefName,headRefName,author,state
list_files:            gh pr diff <PR> --name-only
read_diff:              gh pr diff <PR>
list_discussion:        gh api graphql --paginate -f query='...' (issue comments + review threads + reviews)
                        — never rely on the API's page-size default; page until the response is empty.
publish_single_review:  gh api repos/{owner}/{repo}/pulls/{PR}/reviews -X POST
                        --input review.json   # { "event": "COMMENT", "body": "", "comments": [...] }
                        — one call, N inline comments, empty top-level body.
reply_in_thread:        gh api repos/{owner}/{repo}/pulls/{PR}/comments/{comment_id}/replies -X POST -f body='...'
list_open_changes:      gh pr list --repo motifpath/<repo> --state open --json number,title,headRefName
```

`mcp__github__get_pull_request`, `mcp__github__get_pull_request_files`,
`mcp__github__get_pull_request_comments`, `mcp__github__get_pull_request_reviews`, and
`mcp__github__create_pull_request_review` cover the same ground when available and are acceptable
substitutes — `create_pull_request_review` also supports one review with multiple inline comments
in a single call, which is the operation that matters most for the "one review, not N loose
comments" invariant.

## Invariants any adapter must guarantee

1. **One review, not N loose comments.** The author gets one coherent block, not a stream of
   individual notifications.
2. **Every finding inline, empty review body.** If the platform requires a non-empty body, send a
   neutral one sentence — never the review summary from `FINDING.md`'s Phase 6 presentation.
3. **Full, paginated listing.** Never the API's default page, never a date filter — the criterion is
   "thread without a reply." A thread audit that trusts the default pagination has already lost a
   batch of comments without noticing.
4. **Reinforcement goes as a thread reply**, never as a new comment (item 19).
5. **The anchor must exist in the diff.** If GitHub rejects the line, re-anchor to the nearest valid
   hunk and **say so** — never move the comment silently.
6. **No write before Phase 6 approval.** The draft stays in chat / a local scratch file until the
   user confirms.

## Cross-repo lookups (Phase 4d)

Because MotifPath is four separate repos, not one monorepo, a cross-repo coherence check may need
`gh pr list --repo motifpath/<other-repo>` or `gh search prs` to find the sibling PR (e.g. the
`motifpath-core` PR that consumes a `motifpath-specs` OpenAPI change). Ask the user for the sibling
reference if it isn't obvious from the PR description — don't guess which PR is the counterpart.

## Without a platform

If the change arrives as a local diff, a branch, or a working tree with no open PR yet (this is
effectively dry-run mode, see `SKILL.md`):

- `list_files` / `read_diff` → local diff against the base branch (`git diff dev...HEAD` or
  equivalent);
- `list_discussion` → empty (record that no dedup was possible);
- `publish_*` → doesn't exist: hand the findings report to the user and end at Phase 6.

The review is still valid — only publishing goes away.
