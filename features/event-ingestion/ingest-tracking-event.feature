Feature: Ingest student tracking events
  As the MotifPath platform
  I want to receive and durably store student tracking events emitted by the frontend
  So that the Aggregation Worker can compute accurate learning progress summaries

  Background:
    Given the Event Ingestion Service is operational and ready to accept events

  # ── Happy path ─────────────────────────────────────────────────────────────

  Scenario: Student submits a lesson.started event for a video content node
    Given student "alice" is authenticated with a valid session
    When "alice" submits a lesson.started event for video content node "intro-to-chords"
    Then the event is accepted and stored in the event log
    And the server returns the submitted event identifier and a receipt timestamp

  Scenario: Student submits a lesson.completed event with a duration
    Given student "alice" is authenticated with a valid session
    When "alice" submits a lesson.completed event for content node "intro-to-chords" with a duration of 420 seconds
    Then the event is accepted and stored in the event log
    And the server returns the submitted event identifier and a receipt timestamp

  Scenario: Student submits an exercise.answer_sent event from a challenge sequence
    Given student "alice" is authenticated with a valid session
    And "alice" has an active exercise attempt for exercise "chord-recognition-01" triggered by challenge "week-1-assessment"
    When "alice" submits an answer to the exercise as attempt number 1
    Then the event is accepted and stored in the event log
    And the server returns the submitted event identifier and a receipt timestamp

  Scenario: Student submits an exercise.ended event with a passing score
    Given student "alice" is authenticated with a valid session
    And "alice" has an active exercise attempt for exercise "chord-recognition-01"
    When "alice" submits an exercise.ended event with outcome "completed" and a final score of 85
    Then the event is accepted and stored in the event log
    And the server returns the submitted event identifier and a receipt timestamp

  Scenario: Student submits an exercise.ended event for an abandoned attempt
    Given student "alice" is authenticated with a valid session
    And "alice" has an active exercise attempt for exercise "chord-recognition-01"
    When "alice" submits an exercise.ended event with outcome "abandoned" and no final score
    Then the event is accepted and stored in the event log
    And the server returns the submitted event identifier and a receipt timestamp

  # ── Edge cases ─────────────────────────────────────────────────────────────

  Scenario: Resubmitting a previously accepted event is accepted without error
    Given student "alice" is authenticated with a valid session
    And "alice" has already submitted a lesson.started event with identifier "evt-dup-001"
    When "alice" submits the same lesson.started event again with identifier "evt-dup-001"
    Then the event is accepted without error

  Scenario: lesson.completed event submitted without an optional duration is accepted
    Given student "alice" is authenticated with a valid session
    When "alice" submits a lesson.completed event for content node "intro-to-chords" with no duration
    Then the event is accepted and stored in the event log

  Scenario: lesson.started event with additional fields in content context is accepted
    Given student "alice" is authenticated with a valid session
    When "alice" submits a lesson.started event whose content context includes an unrecognised field "playlist_id"
    Then the event is accepted and stored in the event log

  Scenario: exercise.progress event is accepted during an active exercise attempt
    Given student "alice" is authenticated with a valid session
    And "alice" has an active exercise attempt for exercise "chord-recognition-01"
    When "alice" submits an exercise.progress event with 60 elapsed seconds
    Then the event is accepted and stored in the event log

  # ── Authentication failures ─────────────────────────────────────────────────

  Scenario: Submission without an authentication token is refused
    Given no authentication token is provided
    When an unauthenticated request submits a lesson.started event
    Then the submission is refused with an authentication error

  Scenario: Submission is refused when the token belongs to a different student than the event claims
    Given student "alice" is authenticated
    When "alice" submits an event that identifies student "bob" as the author
    Then the submission is refused with an authentication error

  Scenario: Submission is refused when the caller's identity has never been registered with MotifPath
    Given a caller holds a valid token whose identity has never been registered
    When that caller submits a lesson.started event
    Then the submission is refused with an authentication error

  Scenario: Submission is refused as temporarily unavailable when the caller's identity cannot be resolved
    Given student "alice" is authenticated with a valid session
    But the caller's MotifPath identity cannot currently be resolved
    When "alice" submits a lesson.started event for video content node "intro-to-chords"
    Then the submission is refused as temporarily unavailable

  # ── Validation failures ─────────────────────────────────────────────────────

  Scenario: Event submitted without an event type is rejected
    Given student "alice" is authenticated with a valid session
    When "alice" submits an event with the event type field omitted
    Then the submission is rejected as invalid
    And the rejection identifies "event_type" as the source of the error

  Scenario: Event submitted with an unrecognised event type is rejected
    Given student "alice" is authenticated with a valid session
    When "alice" submits an event with event type "node.unlocked"
    Then the submission is rejected as invalid
    And the rejection identifies "event_type" as the source of the error

  Scenario: lesson.started event submitted without a content context is rejected
    Given student "alice" is authenticated with a valid session
    When "alice" submits a lesson.started event with the content context field omitted
    Then the submission is rejected as invalid
    And the rejection identifies "content_context" as the source of the error

  Scenario: exercise.answer_sent event submitted with attempt number zero is rejected
    Given student "alice" is authenticated with a valid session
    When "alice" submits an exercise.answer_sent event with attempt number 0
    Then the submission is rejected as invalid
    And the rejection identifies "attempt_number" as the source of the error

  Scenario: exercise.answer_sent event submitted without a trigger context is rejected
    Given student "alice" is authenticated with a valid session
    When "alice" submits an exercise.answer_sent event with the trigger context field omitted
    Then the submission is rejected as invalid
    And the rejection identifies "trigger_context" as the source of the error
