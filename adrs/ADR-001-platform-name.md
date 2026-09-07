# ADR-001: Platform Name — MotifPath

Date: 2026-05-17
Status: Accepted

---

## Context

The platform needed a name before repository creation and public branding work
could begin. The name had to satisfy three constraints simultaneously:

1. **Musical resonance** — the term must come from music theory and carry meaning
   that maps naturally to the platform's mechanics
2. **Product legibility** — the name must communicate what the platform does
   without requiring explanation
3. **Domain availability** — `.com` domain must be registrable

Early candidate: **Cadenza** (the virtuosic solo passage in a concerto). Rejected
after research revealed an active, NSF-funded music education product (MetaMusic Inc.)
using the Cadenza trademark in the same space. Multiple domains also occupied:
`cadenza.work`, `getcadenza.app`, `getcadenzai.com`.

Second candidate: **Motif** (a short recurring musical idea that gets developed and
transformed throughout a composition). Strong semantic fit — maps directly to the
platform's concept node mechanic. Rejected because `motif.com` is not available.

Compound names were explored: `motifpath`, `buildmotif`, `motiflab`, `noteforge`.
`motiflab.com` rejected — collision with an established bioinformatics research tool.

---

## Decision

The platform is named **MotifPath**, with domain `motifpath.com`.

The name carries two readings that reinforce each other:

**Musical reading:** a motif path is the structural journey a motif takes through a
composition — how a short idea develops, transforms, and compounds into something larger.
This maps to the student experience: a concept node (motif) practiced through multiple
modalities until it becomes vocabulary.

**Product reading:** a path built from motifs — the teacher-constructed learning path
where every concept node arrives pre-equipped with practice resources. The curriculum
system itself.

Both readings are simultaneously true. A musician understands the musical reference.
A teacher or student understands the product description.

---

## Consequences

**Positive:**
- Domain available and registered: `motifpath.com`
- No trademark conflicts identified in music education space
- Name is self-describing for both supply side (teacher builds paths) and
  demand side (student walks the motif path)
- Compound structure means GitHub org, npm packages, and Go module paths
  are all cleanly available under the `motifpath` namespace

**Negative:**
- "Motif" alone has some noise from unrelated tech products (Amazon discontinued
  a photography product named Motif; a Unix GUI toolkit exists). The compound form
  `motifpath` avoids this collision entirely.

**Neutral:**
- All repositories follow the naming convention: `motifpath-{purpose}`
  (motifpath-specs, motifpath-core, motifpath-web, motifpath-infra)
- Go module paths: `github.com/motifpath/{repo}`
