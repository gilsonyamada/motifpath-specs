Feature: Manage challenges
  As the MotifPath platform
  I want teachers and admins to create challenges attached to content nodes
  So that the recommendation engine has subject tags and thresholds to act on

  Background:
    Given the Core Domain Service is operational and ready to accept requests
    And a content node "intro-to-triads" exists in the system

  # ── Happy path ─────────────────────────────────────────────────────────────

  Scenario: A teacher creates a challenge with a subject tag and pass threshold
    Given "bob" is authenticated as a teacher
    When "bob" creates a challenge for "intro-to-triads" with subject tag "triad-shapes" and pass threshold 70
    Then the challenge is created and assigned a stable identifier
    And the challenge records "intro-to-triads" as its parent content node

  Scenario: A teacher creates a challenge with a remediation target
    Given "bob" is authenticated as a teacher
    And a content node "triad-remediation" exists in the system
    When "bob" creates a challenge for "intro-to-triads" with subject tag "triad-shapes", pass threshold 70, and remediation target "triad-remediation"
    Then the challenge is created with the remediation target recorded

  Scenario: An admin creates a challenge
    Given "admin" is authenticated as an admin
    When "admin" creates a challenge for "intro-to-triads" with subject tag "chord-theory" and pass threshold 80
    Then the challenge is created and assigned a stable identifier

  Scenario: Any authenticated user retrieves a challenge by ID
    Given a challenge "triad-challenge" exists for content node "intro-to-triads"
    And "alice" is authenticated as a student
    When "alice" retrieves the challenge "triad-challenge"
    Then the response returns the challenge's subject tag, threshold, and parent content node

  # ── Validation failures ────────────────────────────────────────────────────

  Scenario: Creating a challenge without a subject tag is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create challenge request with the subject_tag field omitted
    Then the request is rejected as invalid
    And the rejection identifies "subject_tag" as the source of the error

  Scenario: Creating a challenge without a pass threshold is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create challenge request with the pass_threshold field omitted
    Then the request is rejected as invalid
    And the rejection identifies "pass_threshold" as the source of the error

  Scenario: Creating a challenge with a pass threshold of zero is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create challenge request with pass_threshold 0
    Then the request is rejected as invalid
    And the rejection identifies "pass_threshold" as the source of the error

  # ── Not found ─────────────────────────────────────────────────────────────

  Scenario: Creating a challenge for a non-existent content node returns not found
    Given "bob" is authenticated as a teacher
    When "bob" creates a challenge for a content node ID that does not exist
    Then the request is refused with a not-found error

  Scenario: Retrieving a challenge that does not exist returns not found
    Given "alice" is authenticated as a student
    When "alice" retrieves a challenge with an ID that does not exist
    Then the request is refused with a not-found error

  # ── Authorisation failures ─────────────────────────────────────────────────

  Scenario: A student cannot create a challenge
    Given "alice" is authenticated as a student
    When "alice" attempts to create a challenge for "intro-to-triads"
    Then the request is refused with a forbidden error

  Scenario: Creating a challenge without an authentication token is refused
    Given no authentication token is provided
    When an unauthenticated request attempts to create a challenge
    Then the request is refused with an authentication error
