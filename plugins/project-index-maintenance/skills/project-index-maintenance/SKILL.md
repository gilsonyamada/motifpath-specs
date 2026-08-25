---
name: project-index-maintenance
version: 1.0.0
description: >
  Use this skill when Gilson explicitly asks to update the MotifPath Project Index
  page in Notion. Trigger on phrases like "update the project index", "log this
  session", "run the index check", "wrap up the session", "close out the session",
  or similar invocations referring to the Project Index, the session log, or
  end-of-session bookkeeping. This skill reconciles the Project Index page
  (Notion ID 3679ccc1-102f-8184-83a7-e328e0d8cbfc) against what actually happened
  in the session — updating the Current Focus section, Decided ADRs table,
  Backlog Snapshot table, and Last-updated timestamp. Do NOT auto-trigger from
  conversation cues alone — wait for an explicit user invocation.
---

# Project Index Maintenance

## Purpose

The MotifPath Project Index page is the canonical pointer to current focus, decided ADRs, and backlog state. Without active maintenance it drifts out of sync with reality, making the next session's bootstrap slow and error-prone. This skill performs the reconciliation: read the page, compare it against what happened this session, propose changes, get confirmation, write them.

## When to Trigger

This skill runs on explicit user invocation only. Listen for phrases like:

- "update the project index"
- "log this session" / "log the session"
- "run the index check" / "run the index update"
- "wrap up the session" / "close out the session"
- "session close" / "end of session bookkeeping"

Do NOT trigger from implicit conversation cues (a session winding down, work seemingly finishing). Gilson controls when this runs.

If nothing has changed this session, still acknowledge the invocation — but report cleanly that no updates are needed rather than skipping silently.

---

## Workflow

The workflow is six steps. Do not skip any of them. The confirm step is non-negotiable: nothing gets written to Notion before Gilson sees the plan and approves it.

### Step 1: Fetch the current Project Index

Use `notion-fetch` against page ID `3679ccc1-102f-8184-83a7-e328e0d8cbfc` to retrieve the current state of the page. Read it carefully. Note especially:

- The current "Latest session note" link and date
- The current "Active item" and its status
- The current "Last updated" timestamp
- The rows currently in the Decided ADRs table
- The rows currently in the Backlog Snapshot table and their statuses

Without this step, you are operating blind. The entire reconciliation depends on knowing what the page actually says right now.

### Step 2: Inventory what changed this session

Look back over the conversation history of the current session. Build a concrete inventory of:

- **Session note**: Was a new session note page created in Notion (typically as a subpage under a backlog item like PB-8)? If so, capture its URL.
- **Active backlog item**: Did work focus shift from one backlog item to another? Did the active item's status change (e.g., "Ready to Build" → "In Progress", "Discovery" → "In Progress")?
- **ADRs**: Were any ADRs decided or finalized? Capture the ADR number and topic.
- **Backlog snapshot changes**: Did any backlog item change status, priority, or get added/removed?

Reference specific PB-X IDs and ADR-X numbers from the conversation. Do not infer changes that weren't explicitly discussed.

### Step 3: Reconcile against the five checks

Run these five lenses against `(inventory ∩ current page state)` to determine what actually needs to change. The check is **divergence**, not **event** — if a session note was created but the page already points to it, no update is needed.

1. **Session note check**: Does "Latest session note" on the page point to the most recent session note from the inventory?
2. **Active item check**: Does "Active item" on the page match the focus of this session? Does its status match?
3. **ADR check**: Are all newly-decided ADRs from the inventory present as rows in the Decided ADRs table?
4. **Backlog snapshot check**: Do all rows in the snapshot match the current statuses from the inventory?
5. **Timestamp check**: If any of checks 1–4 will result in a write, the "Last updated" date should be updated to today.

If all five checks pass (page already matches reality), there's nothing to do. Report this and stop.

### Step 4: Present the plan and request confirmation

Format the plan as a clear, structured proposal. Example:

```
Here's what I plan to update on the Project Index:

1. Latest session note → [new session note URL from today]
2. Active item: PB-8 (Ready to Build) → PB-9 (In Progress)
3. Decided ADRs: add row | ADR-006 | Content versioning strategy | Decided |
4. Backlog Snapshot: PB-8 status "Ready to Build" → "In Progress"
5. Last updated → 2026-05-21

Confirm to proceed, or tell me what to adjust.
```

Wait for explicit confirmation. Do not write anything to Notion before Gilson responds.

If Gilson asks for adjustments ("skip #3", or "the active item should be PB-7, not PB-9"), update the plan and re-present it for confirmation. Do not write partial sets without seeing the full plan re-confirmed.

### Step 5: Execute writes

Once confirmed, execute the writes using `notion-update-page`. Describe each write by intent — the right tool-call shape depends on the structure of the blocks returned by `notion-fetch` in Step 1. For example:

- "Update the 'Latest session note' line to point to the new URL"
- "Add a new row to the Decided ADRs table with ADR-006"
- "Update the 'Last updated' value to today's date"

Use the block IDs and structures observed in Step 1 to construct correct update calls. If a particular write fails, do not abort the whole sequence — continue with the rest, then report failures in Step 6.

### Step 6: Report results

After all writes are attempted, report concisely.

Successful run:

```
✅ Project Index updated:
- Latest session note → [new link]
- Active item → PB-9 (In Progress)
- Decided ADRs: +ADR-006
- Last updated → 2026-05-21
```

Partial failure:

```
⚠️ Partial update:
- ✅ Latest session note updated
- ✅ Last updated timestamp set
- ❌ Failed to add ADR-006 row to Decided ADRs table (reason: ...)
```

Nothing changed:

```
ℹ️ Project Index unchanged — no backlog, ADR, or session note updates needed this session.
```

---

## What NOT to Update

Even if it looks tempting, leave these alone:

- **Active English Patterns** — owned by the `english-fluency-coach` skill. Touch nothing here.
- **Repo Structure** — only changes for genuine architectural moves; not a routine maintenance target.
- **Methodology** — same.
- **Historical session notes** — only the "Latest session note" pointer moves; older note links are preserved by Notion's own page tree.
- **Speculative future ADRs** — only Decided ADRs go into the table. Drafts and proposals do not.

If you find yourself wanting to "tidy up" any of these sections, stop. That's scope creep and not what this skill is for.

---

## Coordination with english-fluency-coach

Both this skill and `english-fluency-coach` are part of the session-close ritual. Gilson invokes them separately and controls the order. There is no shared state and no required sequencing — but if Gilson asks to run both, do them sequentially (one fully completes, including its confirm-write cycle, before the next starts). Do not interleave.

---

## Edge Cases

**Two backlog items became active in one session.** Ask Gilson which one should be the "Active item" going forward. Don't guess.

**An ADR was discussed but Gilson said "let me think about it more."** It's not decided. Do not add it to the Decided ADRs table.

**The Notion fetch returns an unexpected page structure** (sections missing, table headers renamed). Stop. Report the discrepancy rather than trying to autocorrect. The skill assumes a stable page structure; if that's broken, a human needs to look.

**Gilson invokes the skill mid-session, not at session close.** That's fine — the workflow is the same. Reconcile against whatever has happened so far. Nothing about the workflow actually requires "end of session" to be true.

**The session was entirely discussion, no concrete changes.** Step 3 will show all five checks passing. Report "Project Index unchanged" and stop. This is a feature, not a failure mode.

**Gilson declines to confirm at Step 4.** Don't write anything. Acknowledge and stop. The page stays as it was.

---

## Page Reference

- **Project Index page ID**: `3679ccc1-102f-8184-83a7-e328e0d8cbfc`
- This is the only Notion page this skill writes to. Any other Notion writes are out of scope.
