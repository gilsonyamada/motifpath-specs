Feature: Manage learning paths
  As the MotifPath platform
  I want teachers and admins to create ordered sequences of content nodes
  So that students have a structured curriculum to follow

  Background:
    Given the Core Domain Service is operational and ready to accept requests
    And content nodes "node-01", "node-02", and "node-03" exist in the system

  # ── Happy path ─────────────────────────────────────────────────────────────

  Scenario: A teacher creates a learning path with multiple content nodes
    Given "bob" is authenticated as a teacher
    When "bob" creates a learning path titled "Beginner Guitar — Week 1" with items in order: "node-01", "node-02", "node-03"
    Then the learning path is created and assigned a stable identifier
    And the items are returned with positions 1, 2, and 3 respectively
    And the path records "bob" as the owner

  Scenario: An admin creates a learning path
    Given "admin" is authenticated as an admin
    When "admin" creates a learning path titled "Advanced Techniques — Month 1" with items in order: "node-01", "node-02"
    Then the learning path is created and assigned a stable identifier

  Scenario: A teacher retrieves a learning path by ID
    Given "bob" is authenticated as a teacher
    And a learning path "week-1-path" exists with items "node-01", "node-02", "node-03"
    When "bob" retrieves the learning path "week-1-path"
    Then the response returns the path title, owner, and ordered items

  # ── Section labels ─────────────────────────────────────────────────────────

  Scenario: A teacher creates a learning path with items grouped into sections
    Given "bob" is authenticated as a teacher
    When "bob" creates a learning path titled "Rhythm Foundations" with items in order: "node-01" in section "Open chords", "node-02" in section "Open chords", "node-03" in section "Strumming patterns"
    Then the learning path is created and assigned a stable identifier
    And "node-01" and "node-02" are returned with section_label "Open chords"
    And "node-03" is returned with section_label "Strumming patterns"

  # ── Validation failures ────────────────────────────────────────────────────

  Scenario: Creating a learning path without a title is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create learning path request with the title field omitted
    Then the request is rejected as invalid
    And the rejection identifies "title" as the source of the error

  Scenario: Creating a learning path with no items is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create learning path request with an empty items array
    Then the request is rejected as invalid
    And the rejection identifies "items" as the source of the error

  Scenario: Creating a learning path that references a non-existent content node is rejected
    Given "bob" is authenticated as a teacher
    When "bob" creates a learning path with an item referencing a content node ID that does not exist
    Then the request is rejected as invalid
    And the rejection identifies "content_node_id" as the source of the error

  # ── Authorisation failures ─────────────────────────────────────────────────

  Scenario: A student cannot create a learning path
    Given "alice" is authenticated as a student
    When "alice" attempts to create a learning path
    Then the request is refused with a forbidden error

  Scenario: A student cannot retrieve a learning path directly
    Given "alice" is authenticated as a student
    And a learning path "week-1-path" exists in the system
    When "alice" attempts to retrieve the learning path "week-1-path"
    Then the request is refused with a forbidden error

  Scenario: Creating a learning path without an authentication token is refused
    Given no authentication token is provided
    When an unauthenticated request attempts to create a learning path
    Then the request is refused with an authentication error

  # ── Not found ─────────────────────────────────────────────────────────────

  Scenario: Retrieving a learning path that does not exist returns not found
    Given "bob" is authenticated as a teacher
    When "bob" retrieves a learning path with an ID that does not exist
    Then the request is refused with a not-found error
