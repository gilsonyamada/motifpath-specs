# ADR-003: OpenTelemetry Instrumentation with Deferred Backend

## Status

Accepted — 2026-05-17

## Context

MotifPath at MVP consists of two Go services on EKS — a Core Domain Service backed by Postgres/`ent` and an Event Ingestion Service backed by MongoDB Atlas — fronted by a Vue 3 SPA. There is one event consumer (the Event Ingestion Service itself), no distributed call chains beyond `frontend → service → database`, and no message broker (Kafka is deferred until a second consumer exists).

The team is solo at this stage. Three constraints frame this decision:

1. **No paid observability tooling at MVP.** The existing bill (EKS, RDS, Atlas, Clerk, S3/CloudFront) is the ceiling — no new SaaS line items.
2. **Operational burden is the more expensive currency.** Self-hosting an observability stack means more stateful workloads on EKS to back up, upgrade, and debug, and that time competes directly with shipping the learning graph.
3. **Learning costs are first-class.** Operating an LGTM stack (Loki, Grafana, Tempo, Mimir) and instrumenting against managed providers are both on the learning roadmap — but neither is the right learning *now*. The right learning now is Go services, the `ent` ORM, the event taxonomy, and Vue 3.

Distributed tracing also has limited payoff at MVP scale: with one event consumer and no async fan-out, there is little call graph to visualize. Metrics and structured logs cover the operational questions that actually come up.

OpenTelemetry as the instrumentation standard is already settled — the open decision is where the telemetry lands and who operates that.

## Decision

Instrument all services with the OpenTelemetry Go SDK from day one, using standard-library exporters that write to **stdout** for all three signals (traces, metrics, logs). Container stdout is captured by EKS into CloudWatch Logs as part of existing cluster logging — no new infrastructure, no new bill line, no new service to operate.

### Concretely

- **SDK:** `go.opentelemetry.io/otel` and related packages, configured at service startup.
- **Trace exporter:** `go.opentelemetry.io/otel/exporters/stdout/stdouttrace`
- **Metric exporter:** `go.opentelemetry.io/otel/exporters/stdout/stdoutmetric`
- **Log handling:** structured logs via `slog` with the OpenTelemetry log bridge, so trace and span IDs are embedded in every log record.
- **Output format:** JSON, one structured line per span / metric / log record.
- **Collection:** none. CloudWatch Logs captures everything via EKS container log shipping.
- **Backend:** none at MVP. Ad hoc querying happens through CloudWatch Logs Insights.
- **OpenTelemetry Collector:** not deployed at MVP. Introduced as part of the upgrade path below.

### Instrumentation expectations

Every service must emit:

- **Spans** around HTTP request handlers (middleware-instrumented), database calls (`ent`/Postgres and MongoDB driver), and named domain operations — threshold evaluation, node unlock, event ingestion.
- **Metrics** for request count, request duration, error count, event ingestion rate, and node unlocks. Counters and histograms only at MVP — no exotic instruments.
- **Structured logs** with trace and span IDs embedded, so any log line can be correlated to its originating request even without a tracing UI.

### Upgrade path

The deliberate point of instrumenting the same way one would for a production backend is that the upgrade is a configuration change, not a code change. When the upgrade trigger fires:

1. Deploy the OpenTelemetry Collector as a DaemonSet on EKS via Terraform.
2. Point the SDK at the Collector via OTLP gRPC (one environment variable per service: `OTEL_EXPORTER_OTLP_ENDPOINT`).
3. Configure the Collector with whichever exporters the destination backend requires.

No application code changes. The instrumentation written today is the instrumentation that flows into the eventual backend.

**Upgrade trigger:** the earlier of —

- **(a)** Kafka introduction with a second event consumer creating real distributed flows worth tracing, or
- **(b)** the first production incident where CloudWatch Logs Insights proves insufficient for root-cause analysis.

Backend selection at that point will be its own ADR. The leading candidate is Grafana Cloud's free tier (10k metrics, 50 GB logs, 50 GB traces) — OTel-native, no operational burden, and the learning is in writing PromQL / LogQL / TraceQL rather than operating Prometheus / Loki / Tempo. Self-hosted LGTM on EKS remains a viable option once operational maturity warrants it.

## Consequences

### Positive

- Zero marginal observability cost at MVP.
- Zero new operational surface — no new services to keep healthy.
- Instrumentation code is permanent: services do not change when the backend is added later.
- The OpenTelemetry Collector and backend learning is *postponed*, not foreclosed — it happens when there is real load and real flows to make sense of.
- Trace and span IDs in structured logs give correlation even without a tracing UI.

### Negative

- **No time-series metric dashboards.** Metric records emitted to stdout are queryable through CloudWatch Logs Insights but not aggregated into a TSDB. Alerting on metric thresholds requires CloudWatch Metric Filters, or accepting that alerting itself is post-MVP.
- **No trace waterfall UI.** Spans are stored as JSON log lines. Reconstructing a distributed flow means querying by trace ID and reading log entries in order — workable for two services and one consumer, painful as the topology grows.
- **CloudWatch Logs Insights is the only query interface.** Adequate for ad hoc debugging, but not for proactive observability work — no dashboards, no shared views, no incident review tooling.
- **Log ingestion cost risk.** Verbose stdout instrumentation can grow CloudWatch Logs ingestion costs faster than expected. Mitigation: trace sampling at 10% from day one, monthly cost review.

### Neutral

- LLM observability (PromptFoo runs, Claude model calls, prompt versions, eval scores) is explicitly **out of scope** for this ADR. It is handled today by PromptFoo's own outputs and golden-set evaluation. A dedicated ADR will be written when LLM telemetry needs to flow through the same pipeline as service telemetry.

## Alternatives Considered

### 1. Grafana Cloud free tier (OTel-native managed)

Strong technical fit. OTLP endpoints out of the box, generous free tier sufficient for MVP volume, no operational burden, dashboards and tracing UI from day one.

**Deferred** because (a) it introduces a SaaS account, credentials, and a vendor relationship before there is a real operational need, and (b) it bypasses the deliberate constraint that observability tooling not become a learning distraction at MVP. Selected as the leading candidate for the upgrade ADR.

### 2. Self-hosted LGTM stack on EKS

Best for transferable learning — Prometheus, Loki, Tempo, and Grafana are widely used across the industry.

**Rejected for MVP** because operating four new stateful services is a significant time investment that competes directly with shipping the learning graph. Remains a viable option for a later stage when operational maturity warrants it.

### 3. AWS-native (CloudWatch Metrics + X-Ray)

Already in the AWS bill, no new vendor.

**Rejected** because X-Ray is not OpenTelemetry-idiomatic — it uses its own SDK semantics and trace propagation format, which would either lock in AWS at the SDK layer or require a translation step. The point of choosing OpenTelemetry is portability; pairing it with a non-OTel-native backend defeats that.

### 4. SigNoz Cloud / Honeycomb

Both are credible OTel-native SaaS options with free tiers.

**Deferred** for the same reason as Grafana Cloud — the MVP does not need a backend yet. If the upgrade ADR finds a specific reason to prefer either (Honeycomb for tracing-first ergonomics, SigNoz for unified UI), they remain on the table.

## References

- Platform Architecture — MVP (Notion): `35e9ccc1-102f-8134-8918-d8d853b81f9c`
- OpenTelemetry Go SDK: <https://opentelemetry.io/docs/languages/go/>
- OpenTelemetry Collector: <https://opentelemetry.io/docs/collector/>
- Grafana Cloud free tier: <https://grafana.com/products/cloud/>
