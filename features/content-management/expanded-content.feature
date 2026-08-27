Feature: Manage expanded content
  As the MotifPath platform
  I want teachers and admins to attach expositive media items to content nodes
  So that students see supporting images and GIFs at the right moment during
  video lessons and article reading

  Background:
    Given the Core Domain Service is operational and ready to accept requests

  # ── Video content node — happy path ────────────────────────────────────────

  Scenario: A teacher adds an image to a video lesson at a specific timestamp
    Given "bob" is authenticated as a teacher
    And a video content node "intro-to-triads" exists in the system
    When "bob" adds an image to "intro-to-triads" with trigger_at_seconds 150 and hide_at_seconds 165
    Then the expanded content item is created and assigned a stable identifier
    And the item records "intro-to-triads" as its parent content node

  Scenario: A teacher adds a GIF to a video lesson
    Given "bob" is authenticated as a teacher
    And a video content node "intro-to-triads" exists in the system
    When "bob" adds a GIF to "intro-to-triads" with trigger_at_seconds 90 and hide_at_seconds 100
    Then the expanded content item is created and assigned a stable identifier

  Scenario: A teacher adds multiple expanded content items to a video lesson
    Given "bob" is authenticated as a teacher
    And a video content node "intro-to-triads" exists in the system
    When "bob" adds three images to "intro-to-triads" at different timestamps
    Then three distinct expanded content identifiers are returned

  Scenario: Listing expanded content for a video node returns items ordered by trigger timestamp
    Given a video content node "intro-to-triads" has expanded content items at seconds 90, 150, and 210
    And "alice" is authenticated as a student
    When "alice" lists the expanded content for "intro-to-triads"
    Then the items are returned ordered by trigger_at_seconds ascending

  # ── Article content node — happy path ──────────────────────────────────────

  Scenario: A teacher adds an image to an article at a specific paragraph
    Given "bob" is authenticated as a teacher
    And an article content node "chord-theory-explained" exists in the system
    When "bob" adds an image to "chord-theory-explained" with trigger_at_paragraph 3 and duration_ms 8000
    Then the expanded content item is created and assigned a stable identifier

  Scenario: A teacher adds a GIF to an article at the first paragraph
    Given "bob" is authenticated as a teacher
    And an article content node "chord-theory-explained" exists in the system
    When "bob" adds a GIF to "chord-theory-explained" with trigger_at_paragraph 1 and duration_ms 5000
    Then the expanded content item is created and assigned a stable identifier

  Scenario: Listing expanded content for an article returns items ordered by paragraph
    Given an article content node "chord-theory-explained" has expanded content at paragraphs 1, 3, and 7
    And "alice" is authenticated as a student
    When "alice" lists the expanded content for "chord-theory-explained"
    Then the items are returned ordered by trigger_at_paragraph ascending

  Scenario: Any authenticated user retrieves a specific expanded content item by ID
    Given an expanded content item "triad-diagram" exists for "intro-to-triads"
    And "alice" is authenticated as a student
    When "alice" retrieves the expanded content item "triad-diagram"
    Then the response returns the item's type, media URL, trigger, and hide fields

  # ── Validation failures — missing required fields ──────────────────────────

  Scenario: Creating an expanded content item without a content type is rejected
    Given "bob" is authenticated as a teacher
    And a video content node "intro-to-triads" exists in the system
    When "bob" submits a create expanded content request with the content_type field omitted
    Then the request is rejected as invalid
    And the rejection identifies "content_type" as the source of the error

  Scenario: Creating an expanded content item without a media URL is rejected
    Given "bob" is authenticated as a teacher
    And a video content node "intro-to-triads" exists in the system
    When "bob" submits a create expanded content request with the media_url field omitted
    Then the request is rejected as invalid
    And the rejection identifies "media_url" as the source of the error

  # ── Validation failures — video trigger/hide rules ─────────────────────────

  Scenario: Adding expanded content to a video node without trigger_at_seconds is rejected
    Given "bob" is authenticated as a teacher
    And a video content node "intro-to-triads" exists in the system
    When "bob" submits a create expanded content request with trigger_at_paragraph 3 and duration_ms 5000 for a video content node
    Then the request is rejected as invalid
    And the rejection identifies "trigger_at_seconds" as the source of the error

  Scenario: Adding expanded content to a video node where hide_at_seconds is not greater than trigger_at_seconds is rejected
    Given "bob" is authenticated as a teacher
    And a video content node "intro-to-triads" exists in the system
    When "bob" submits a create expanded content request with trigger_at_seconds 150 and hide_at_seconds 150
    Then the request is rejected as invalid
    And the rejection identifies "hide_at_seconds" as the source of the error

  # ── Validation failures — article trigger/hide rules ──────────────────────

  Scenario: Adding expanded content to an article node without trigger_at_paragraph is rejected
    Given "bob" is authenticated as a teacher
    And an article content node "chord-theory-explained" exists in the system
    When "bob" submits a create expanded content request with trigger_at_seconds 90 and hide_at_seconds 100 for an article content node
    Then the request is rejected as invalid
    And the rejection identifies "trigger_at_paragraph" as the source of the error

  Scenario: Adding expanded content to an article node with trigger_at_paragraph zero is rejected
    Given "bob" is authenticated as a teacher
    And an article content node "chord-theory-explained" exists in the system
    When "bob" submits a create expanded content request with trigger_at_paragraph 0
    Then the request is rejected as invalid
    And the rejection identifies "trigger_at_paragraph" as the source of the error

  Scenario: Adding expanded content to an article node without duration_ms is rejected
    Given "bob" is authenticated as a teacher
    And an article content node "chord-theory-explained" exists in the system
    When "bob" submits a create expanded content request with trigger_at_paragraph 3 and duration_ms omitted
    Then the request is rejected as invalid
    And the rejection identifies "duration_ms" as the source of the error

  # ── Not found ──────────────────────────────────────────────────────────────

  Scenario: Adding expanded content to a non-existent content node returns not found
    Given "bob" is authenticated as a teacher
    When "bob" adds expanded content to a content node ID that does not exist
    Then the request is refused with a not-found error

  Scenario: Retrieving an expanded content item that does not exist returns not found
    Given "alice" is authenticated as a student
    When "alice" retrieves an expanded content item with an ID that does not exist
    Then the request is refused with a not-found error

  # ── Authorisation failures ─────────────────────────────────────────────────

  Scenario: A student cannot add expanded content to a content node
    Given "alice" is authenticated as a student
    And a video content node "intro-to-triads" exists in the system
    When "alice" attempts to add expanded content to "intro-to-triads"
    Then the request is refused with a forbidden error

  Scenario: Adding expanded content without an authentication token is refused
    Given no authentication token is provided
    When an unauthenticated request attempts to add expanded content
    Then the request is refused with an authentication error
