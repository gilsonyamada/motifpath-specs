Feature: Manual remediation of failed event publishes
  As a MotifPath operator
  I want to retry or resolve tracking events that failed to reach the event stream
  So that a delivery outage does not permanently lose learning-progress data

  Background:
    Given the Event Ingestion Service is operational and ready to accept events
    And a lesson.started event "evt-stuck-001" failed every delivery attempt and is now dead-lettered

  # ── Happy path ─────────────────────────────────────────────────────────────

  Scenario: An administrator retries a dead-lettered event and delivery succeeds
    Given the caller is authenticated and the platform recognises them as an administrator
    And the event stream is reachable again
    When the caller asks to retry delivery of event "evt-stuck-001"
    Then the event is delivered to the event stream
    And the delivery is confirmed as complete

  Scenario: An administrator resolves a dead-lettered event without redelivering it
    Given the caller is authenticated and the platform recognises them as an administrator
    When the caller resolves event "evt-stuck-001" with the reason "delivered out of band"
    Then the entry is recorded as manually resolved
    And no delivery to the event stream is attempted

  # ── Edge cases ─────────────────────────────────────────────────────────────

  Scenario: Retrying an already-delivered event changes nothing
    Given the caller is authenticated and the platform recognises them as an administrator
    And event "evt-stuck-001" has already been delivered to the event stream
    When the caller asks to retry delivery of event "evt-stuck-001"
    Then the delivery is confirmed as complete
    And no further delivery to the event stream is attempted

  Scenario: Resolving a dead-lettered event without giving a reason is accepted
    Given the caller is authenticated and the platform recognises them as an administrator
    When the caller resolves event "evt-stuck-001" without a reason
    Then the entry is recorded as manually resolved

  Scenario: Remediating an event that was never received reports that nothing is awaiting delivery
    Given the caller is authenticated and the platform recognises them as an administrator
    When the caller asks to retry delivery of event "evt-never-seen-999"
    Then the platform reports that no such event is awaiting delivery

  # ── Authorization failures ─────────────────────────────────────────────────

  Scenario: A student may not remediate a failed publish
    Given the caller is authenticated and the platform recognises them as a student
    When the caller asks to retry delivery of event "evt-stuck-001"
    Then the remediation is refused because the caller is not an administrator
    And no delivery to the event stream is attempted

  Scenario: A caller whose token asserts the administrator role but whose profile does not is refused
    Given the caller is authenticated and their token asserts the administrator role
    But the platform recognises them as a teacher
    When the caller asks to retry delivery of event "evt-stuck-001"
    Then the remediation is refused because the caller is not an administrator

  Scenario: A caller who has never registered may not remediate a failed publish
    Given the caller is authenticated but has never registered with the platform
    When the caller resolves event "evt-stuck-001" with the reason "cleanup"
    Then the remediation is refused because the caller is not an administrator

  Scenario: Remediation is unavailable when the caller's role cannot be established
    Given the caller is authenticated
    But the platform cannot currently establish the caller's role
    When the caller asks to retry delivery of event "evt-stuck-001"
    Then the remediation is refused as temporarily unavailable
    And no delivery to the event stream is attempted

  Scenario: An unauthenticated request may not remediate a failed publish
    Given no authentication token is provided
    When an unauthenticated request asks to retry delivery of event "evt-stuck-001"
    Then the remediation is refused with an authentication error
