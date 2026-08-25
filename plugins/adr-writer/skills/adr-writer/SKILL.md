---
name: adr-writer
version: 1.0.0
description: >
  Write, review, and update Architecture Decision Records (ADRs) for the MotifPath project. Trigger
  whenever an architectural decision needs to be documented, revisited, or revised — even if the user
  doesn't explicitly say "write an ADR". Signals include: a new technology being adopted, a design
  trade-off being resolved, an existing decision being superseded, or a question like "how do we
  handle X?" that results in a durable architectural choice. Always produce ADR files in the correct
  format, correct location, and on the correct branch. Never let an architectural decision leave a
  session without a committed ADR.
---

# ADR Writer — MotifPath

## Purpose

Produce well-structured, durable ADR documents that record *why* a decision was made, not just *what*
was decided. ADRs are the audit trail for every architectural choice in MotifPath. A weak ADR causes
future teams to re-litigate settled decisions.

---

## Repository Location

All ADRs live in:

```
motifpath-specs/
  adrs/
    ADR-001-platform-naming.md
    ADR-003-observability-stack.md
    ADR-004-deployment-pipeline.md
    ADR-005-ent-migration-strategy.md
    ADR-006-kafka-topology.md
    ...
```

**Note:** ADR-002 is reserved. Do not assign it without checking the directory first.

---

## File Naming Convention

```
ADR-NNN-short-description.md
```

- `NNN`: Zero-padded three-digit number. Check the `adrs/` directory for the next available number.
- `short-description`: Lowercase, hyphen-separated, 3–6 words. Describes the *decision*, not the problem.

**Examples:**
- `ADR-006-kafka-topology.md` ✅
- `ADR-006-message-broker-decision-for-event-streaming.md` ❌ (too long)
- `ADR-006-Kafka.md` ❌ (too vague)

---

## ADR Template

```markdown
# ADR-NNN: [Short Title]

**Status:** Proposed
**Date:** YYYY-MM-DD
**Deciders:** [Names or roles involved in the decision]

---

## Context

[2–4 paragraphs. Describe the problem or force that requires a decision. Include:
- What triggered this decision (a product requirement, a scaling concern, a new dependency)
- What constraints exist (team size, budget, existing stack)
- What alternatives were considered at a high level
Do NOT include the decision here.]

## Decision

[1–2 paragraphs. State the decision clearly and directly. Start with: "We will..." or "MotifPath will..."
Be specific enough that a new engineer can implement without ambiguity.]

## Rationale

[Explain WHY this decision was made over the alternatives. Reference trade-offs explicitly.
This is the most important section — the "why" is what gets lost over time.]

## Consequences

### Positive
- [List concrete benefits]

### Negative / Trade-offs
- [List concrete costs, risks, or constraints introduced]

### Neutral
- [Side effects that are neither clearly good nor bad]

## Related ADRs

- [ADR-NNN: Title — how it relates]

---

*This ADR was decided on [date]. To revise, create a new ADR with Status: Supersedes ADR-NNN.*
```

---

## Status Values

| Status | Meaning |
|---|---|
| `Proposed` | Draft — not yet agreed upon |
| `Accepted` | Agreed and active |
| `Deprecated` | No longer relevant but not replaced |
| `Superseded by ADR-NNN` | Replaced by a newer decision |

Always set `Status: Proposed` when creating. Change to `Accepted` after review. Never delete an ADR.

---

## Git Workflow for ADRs

ADRs are spec changes. They follow the standard MotifPath branching model:

```bash
# Branch from dev
git checkout dev
git pull origin dev
git checkout -b feat/MTP-XXX/adr-NNN-short-description

# Create the file
touch motifpath-specs/adrs/ADR-NNN-short-description.md

# Commit
git add motifpath-specs/adrs/ADR-NNN-short-description.md
git commit -m "feat(adrs): add ADR-NNN — short description [MTP-XXX]"

# Push and open PR targeting dev
git push origin feat/MTP-XXX/adr-NNN-short-description
```

Task code (`MTP-XXX`) is mandatory on every branch and commit. If no task exists yet, create one before branching.

---

## Quality Criteria

An ADR is ready to merge when:

- [ ] Context explains the *problem*, not just the solution
- [ ] Decision is stated unambiguously — no hedging language like "we might" or "possibly"
- [ ] Rationale references at least one rejected alternative with a reason for rejection
- [ ] Consequences lists at least one negative trade-off (if there are no trade-offs, the decision is trivial and may not need an ADR)
- [ ] Related ADRs are linked if any exist
- [ ] Status is `Proposed` (reviewer sets it to `Accepted`)
- [ ] File name follows the convention
- [ ] Branch follows the `feat/MTP-XXX/adr-NNN-description` pattern

---

## Existing ADRs — Quick Reference

| ADR | Title | Status |
|---|---|---|
| ADR-001 | Platform naming — MotifPath | Accepted |
| ADR-003 | Observability — OpenTelemetry + CloudWatch Logs (Kafka deferred) | Accepted |
| ADR-004 | Deployment pipeline — dev → staging → production, blue/green | Accepted |
| ADR-005 | Database migration — Atlas + ent, startup lock | Accepted |
| ADR-006 | Kafka topology — single topic, student_id partition, Aggregation Worker as service | Accepted |

Always check the `adrs/` directory for the authoritative list before assigning a new number.

---

## Anti-Patterns to Avoid

- **Decision without context:** Stating what was decided without explaining what problem it solves.
- **Rationale without alternatives:** "We chose X because it is good" — always name what was rejected and why.
- **Missing trade-offs:** Every real architectural decision has costs. If the consequences section has no negatives, it's incomplete.
- **Vague status:** ADRs without a clear status confuse future readers about whether the decision is active.
- **Post-hoc documentation:** ADRs written weeks after implementation tend to rationalize rather than record. Write them at decision time.
