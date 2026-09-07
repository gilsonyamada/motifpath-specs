Feature: Assign learning paths to students
  As the MotifPath platform
  I want teachers and admins to assign a learning path to a student
  So that the student has an active curriculum to follow

  Background:
    Given the Core Domain Service is operational and ready to accept requests
    And a learning path "beginner-guitar-path" exists in the system
    And student "alice" is registered in the system

  # ── Happy path ─────────────────────────────────────────────────────────────

  Scenario: A teacher assigns a learning path to a student
    Given "bob" is authenticated as a teacher
    When "bob" assigns "beginner-guitar-path" to student "alice"
    Then an assignment record is created and returned
    And the assignment records "bob" as the assigner and "alice" as the student

  Scenario: An admin assigns a learning path to a student
    Given "admin" is authenticated as an admin
    When "admin" assigns "beginner-guitar-path" to student "alice"
    Then an assignment record is created and returned

  Scenario: Assigning a new path to a student who already has an active assignment replaces it
    Given "bob" is authenticated as a teacher
    And "alice" already has "beginner-guitar-path" assigned
    And a second learning path "fingerstyle-basics-path" exists in the system
    When "bob" assigns "fingerstyle-basics-path" to student "alice"
    Then a new assignment record is returned for "fingerstyle-basics-path"
    And "alice"'s active path is now "fingerstyle-basics-path"

  # ── Not found ─────────────────────────────────────────────────────────────

  Scenario: Assigning a path to a non-existent student returns not found
    Given "bob" is authenticated as a teacher
    When "bob" assigns "beginner-guitar-path" to a student ID that does not exist
    Then the request is refused with a not-found error

  Scenario: Assigning a non-existent path to a student returns not found
    Given "bob" is authenticated as a teacher
    When "bob" assigns a learning path ID that does not exist to student "alice"
    Then the request is refused with a not-found error

  Scenario: Assigning a path to a user with role teacher returns not found
    Given "bob" is authenticated as a teacher
    And "carol" is registered as a teacher
    When "bob" assigns "beginner-guitar-path" to "carol"
    Then the request is refused with a not-found error

  # ── Authorisation failures ─────────────────────────────────────────────────

  Scenario: A student cannot assign a learning path
    Given "alice" is authenticated as a student
    When "alice" attempts to assign "beginner-guitar-path" to herself
    Then the request is refused with a forbidden error

  Scenario: Assigning a path without an authentication token is refused
    Given no authentication token is provided
    When an unauthenticated request attempts to assign a learning path
    Then the request is refused with an authentication error
