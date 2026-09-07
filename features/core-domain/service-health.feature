Feature: Core Domain Service health and readiness
  As the deployment platform
  I want to probe the Core Domain Service for liveness and readiness
  So that traffic is only routed to instances that can serve the domain

  # ── Liveness ───────────────────────────────────────────────────────────────

  Scenario: Liveness probe confirms the service process is running
    Given the Core Domain Service process is running
    When the liveness probe is checked
    Then the service reports itself as alive

  # ── Readiness — happy path ─────────────────────────────────────────────────

  Scenario: Readiness probe confirms the service is ready when both stores are reachable
    Given the learning-graph store is reachable
    And the completion-state store is reachable
    When the readiness probe is checked
    Then the service reports itself as ready
    And all dependency checks report "ok"

  # ── Readiness — a dependency is unavailable ────────────────────────────────

  Scenario: Readiness probe reports not ready when the learning-graph store is unreachable
    Given the learning-graph store is unreachable
    And the completion-state store is reachable
    When the readiness probe is checked
    Then the service reports itself as not ready
    And the "learning_graph" dependency check reports "fail"
    And the "completion_state" dependency check reports "ok"

  Scenario: Readiness probe reports not ready when the completion-state store is unreachable
    Given the learning-graph store is reachable
    And the completion-state store is unreachable
    When the readiness probe is checked
    Then the service reports itself as not ready
    And the "completion_state" dependency check reports "fail"
    And the "learning_graph" dependency check reports "ok"

  Scenario: Readiness probe reports not ready when both stores are unreachable
    Given the learning-graph store is unreachable
    And the completion-state store is unreachable
    When the readiness probe is checked
    Then the service reports itself as not ready
    And the "learning_graph" dependency check reports "fail"
    And the "completion_state" dependency check reports "fail"

  # ── Readiness — recovery ──────────────────────────────────────────────────

  Scenario: Readiness probe returns to ready once an unreachable store recovers
    Given the learning-graph store is unreachable
    And the completion-state store is reachable
    And the readiness probe reports the service as not ready
    When the learning-graph store becomes reachable again
    And the readiness probe is checked
    Then the service reports itself as ready
    And all dependency checks report "ok"
