Feature: Manage content nodes
  As the MotifPath platform
  I want teachers and admins to create content nodes with classification
  So that students have structured lessons to follow on their learning path

  Background:
    Given the Core Domain Service is operational and ready to accept requests

  # ── Happy path ─────────────────────────────────────────────────────────────

  Scenario: A teacher creates a video content node with classification
    Given "bob" is authenticated as a teacher
    When "bob" creates a video content node titled "Introduction to Triad Shapes" with skill "triad-shapes", concept "chord-theory", and difficulty "beginner"
    Then the content node is created and assigned a stable identifier
    And the classification review state is "pending"
    And the content node records "bob" as the owner

  Scenario: A teacher creates an article content node
    Given "bob" is authenticated as a teacher
    When "bob" creates an article content node titled "Understanding Chord Theory" with skill "chord-transitions", concept "chord-theory", and difficulty "intermediate"
    Then the content node is created and assigned a stable identifier

  Scenario: An admin creates a content node
    Given "admin" is authenticated as an admin
    When "admin" creates a video content node titled "Sweep Picking Fundamentals" with skill "sweep-picking", concept "technique", and difficulty "advanced"
    Then the content node is created and assigned a stable identifier

  Scenario: Any authenticated user retrieves a content node by ID
    Given a content node "intro-to-triads" exists in the system
    And "alice" is authenticated as a student
    When "alice" retrieves the content node "intro-to-triads"
    Then the response returns the content node's title, type, and classification

  # ── Validation failures ────────────────────────────────────────────────────

  Scenario: Creating a content node without a title is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create content node request with the title field omitted
    Then the request is rejected as invalid
    And the rejection identifies "title" as the source of the error

  Scenario: Creating a content node without classification is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create content node request with the classification field omitted
    Then the request is rejected as invalid
    And the rejection identifies "classification" as the source of the error

  Scenario: Creating a content node with an unrecognised difficulty level is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create content node request with difficulty level "expert"
    Then the request is rejected as invalid
    And the rejection identifies "difficulty_level" as the source of the error

  # ── Authorisation failures ─────────────────────────────────────────────────

  Scenario: A student cannot create a content node
    Given "alice" is authenticated as a student
    When "alice" attempts to create a content node
    Then the request is refused with a forbidden error

  Scenario: Creating a content node without an authentication token is refused
    Given no authentication token is provided
    When an unauthenticated request attempts to create a content node
    Then the request is refused with an authentication error

  Scenario: Retrieving a content node that does not exist returns not found
    Given "alice" is authenticated as a student
    When "alice" retrieves a content node with an ID that does not exist
    Then the request is refused with a not-found error
