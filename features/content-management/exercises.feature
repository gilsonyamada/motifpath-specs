Feature: Manage exercises
  As the MotifPath platform
  I want teachers and admins to create pre-defined exercises within challenges
  So that students can complete practice interactions and the SPA can reference
  exercises by their stable IDs in tracking events

  Background:
    Given the Core Domain Service is operational and ready to accept requests
    And a content node "intro-to-triads" exists in the system
    And a challenge "triad-challenge" exists for content node "intro-to-triads"

  # ── Happy path ─────────────────────────────────────────────────────────────

  Scenario: A teacher creates a fretboard region exercise
    Given "bob" is authenticated as a teacher
    When "bob" creates a fretboard_region exercise for "triad-challenge" with prompt "Identify the root position of a C major triad"
    Then the exercise is created and assigned a stable identifier
    And the exercise records "triad-challenge" as its parent challenge

  Scenario: An admin creates an exercise
    Given "admin" is authenticated as an admin
    When "admin" creates a fretboard_region exercise for "triad-challenge" with prompt "Tap the first inversion of a G major triad"
    Then the exercise is created and assigned a stable identifier

  Scenario: A teacher creates multiple exercises within the same challenge
    Given "bob" is authenticated as a teacher
    When "bob" creates three fretboard_region exercises for "triad-challenge"
    Then three distinct exercise identifiers are returned

  Scenario: Any authenticated user retrieves an exercise by ID
    Given an exercise "triad-exercise-01" exists within "triad-challenge"
    And "alice" is authenticated as a student
    When "alice" retrieves the exercise "triad-exercise-01"
    Then the response returns the exercise's type, prompt, and parent challenge

  # ── Validation failures ────────────────────────────────────────────────────

  Scenario: Creating an exercise without an exercise type is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create exercise request with the exercise_type field omitted
    Then the request is rejected as invalid
    And the rejection identifies "exercise_type" as the source of the error

  Scenario: Creating an exercise without a prompt is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create exercise request with the prompt field omitted
    Then the request is rejected as invalid
    And the rejection identifies "prompt" as the source of the error

  Scenario: Creating an exercise with an unrecognised type is rejected
    Given "bob" is authenticated as a teacher
    When "bob" submits a create exercise request with exercise_type "multiple_choice"
    Then the request is rejected as invalid
    And the rejection identifies "exercise_type" as the source of the error

  # ── Not found ─────────────────────────────────────────────────────────────

  Scenario: Creating an exercise for a non-existent challenge returns not found
    Given "bob" is authenticated as a teacher
    When "bob" creates an exercise for a challenge ID that does not exist
    Then the request is refused with a not-found error

  Scenario: Retrieving an exercise that does not exist returns not found
    Given "alice" is authenticated as a student
    When "alice" retrieves an exercise with an ID that does not exist
    Then the request is refused with a not-found error

  # ── Authorisation failures ─────────────────────────────────────────────────

  Scenario: A student cannot create an exercise
    Given "alice" is authenticated as a student
    When "alice" attempts to create an exercise for "triad-challenge"
    Then the request is refused with a forbidden error

  Scenario: Creating an exercise without an authentication token is refused
    Given no authentication token is provided
    When an unauthenticated request attempts to create an exercise
    Then the request is refused with an authentication error
