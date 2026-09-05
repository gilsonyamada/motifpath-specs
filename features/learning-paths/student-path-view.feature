Feature: Student path view
  As the MotifPath platform
  I want students to retrieve their active learning path with progress state
  So that the SPA can display what to do next and how far the student has come

  Background:
    Given the Core Domain Service is operational and ready to accept requests
    And content nodes "node-01", "node-02", "node-03" exist in the system
    And a learning path "week-1-path" exists with items "node-01", "node-02", "node-03"
    And student "alice" is registered in the system

  # ── Happy path ─────────────────────────────────────────────────────────────

  Scenario: A student with a fresh assignment sees all items as not_started except the first
    Given "alice" is authenticated as a student
    And "alice" has "week-1-path" assigned with no progress recorded
    When "alice" retrieves her current path
    Then the response contains all three items in order
    And "node-01" has status "not_started"
    And "node-02" has status "locked"
    And "node-03" has status "locked"
    And the current_position is 1

  Scenario: A student who has completed the first node sees it as completed and the second as not_started
    Given "alice" is authenticated as a student
    And "alice" has "week-1-path" assigned
    And "alice" has completed "node-01"
    When "alice" retrieves her current path
    Then "node-01" has status "completed"
    And "node-02" has status "not_started"
    And "node-03" has status "locked"
    And the current_position is 2

  Scenario: A student who has started but not finished the second node sees it as in_progress
    Given "alice" is authenticated as a student
    And "alice" has "week-1-path" assigned
    And "alice" has completed "node-01"
    And "alice" has started but not completed "node-02"
    When "alice" retrieves her current path
    Then "node-01" has status "completed"
    And "node-02" has status "in_progress"
    And "node-03" has status "locked"
    And the current_position is 2

  Scenario: A student who has completed all nodes sees the full path as completed
    Given "alice" is authenticated as a student
    And "alice" has "week-1-path" assigned
    And "alice" has completed "node-01", "node-02", and "node-03"
    When "alice" retrieves her current path
    Then all three items have status "completed"
    And the current_position is 3

  Scenario: The path view includes each item's title and content type
    Given "alice" is authenticated as a student
    And "alice" has "week-1-path" assigned
    When "alice" retrieves her current path
    Then each item in the response includes a title and content_type

  # ── Section labels ─────────────────────────────────────────────────────────

  Scenario: The path view has no section labels when the path defines none
    Given "alice" is authenticated as a student
    And "alice" has "week-1-path" assigned
    When "alice" retrieves her current path
    Then none of the items have a section_label

  Scenario: The path view includes each item's section label when the path defines one
    Given "alice" is authenticated as a student
    And a learning path "rhythm-foundations-path" exists with "node-01" and "node-02" in section "Open chords" and "node-03" in section "Strumming patterns"
    And "alice" has "rhythm-foundations-path" assigned
    When "alice" retrieves her current path
    Then "node-01" and "node-02" have section_label "Open chords"
    And "node-03" has section_label "Strumming patterns"

  # ── Not found ─────────────────────────────────────────────────────────────

  Scenario: A student with no active assignment gets not found
    Given "alice" is authenticated as a student
    And "alice" has no active path assignment
    When "alice" retrieves her current path
    Then the request is refused with a not-found error

  # ── Authorisation failures ─────────────────────────────────────────────────

  Scenario: A teacher cannot access the student path view endpoint
    Given "bob" is authenticated as a teacher
    When "bob" requests GET /students/me/path
    Then the request is refused with a forbidden error

  Scenario: An admin cannot access the student path view endpoint
    Given "admin" is authenticated as an admin
    When "admin" requests GET /students/me/path
    Then the request is refused with a forbidden error

  Scenario: Retrieving the student path view without an authentication token is refused
    Given no authentication token is provided
    When an unauthenticated request attempts to retrieve the student path view
    Then the request is refused with an authentication error
