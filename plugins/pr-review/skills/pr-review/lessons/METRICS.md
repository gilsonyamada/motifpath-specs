# Metrics per review

One line per review, written at Phase 8. They exist to decide promotion and pruning from data
instead of impression (`LEARNING.md` §6).

```
YYYY-MM-DD | <PR ref> | scope: <repo/service> | published: N | confirmed: N | rejected: N | escaped: N | heuristics: [n,...]
```

- `confirmed` / `rejected`: `-` at publish time; fill in once the author responds.
- `escaped`: fill in if a defect from that change later shows up in production — the only way to
  measure recall.
- `heuristics`: checklist items (or lesson ids) that produced a **published** finding.

## Periodic read (every ~10 reviews)

- An item with no hit across the reviews that activated it → pruning candidate.
- An item with rejection > 50% → its trigger condition is probably too broad.
- Repeated `escaped` on the same axis → that axis is missing a question.
- Reorder items within each axis by hit rate.

## Records

<!-- first line lands on the next review -->
