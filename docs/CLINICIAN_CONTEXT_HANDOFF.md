# Clinician Context Handoff

This document defines the privacy-safe context the Aura mobile application can
prepare for the central clinician backend. It is intentionally separate from
multimodal risk fusion.

## Why this exists

A single model score is less useful to a clinician than the surrounding context:
what the participant reported, what they were doing, whether they tried an
intervention, whether they felt better at follow-up, whether a behavioural
pattern changed relative to their own baseline, and whether the sensing data had
enough coverage.

The mobile app therefore prepares a descriptive clinician-context payload while
preserving the existing safety decision for Component 2.

## Current transport status

The mobile app **builds and caches** this payload under
`clinician_insight_handoff_v1`. It is not automatically transmitted yet because
the central backend does not currently expose a dedicated participant check-in
context endpoint.

The team should agree and implement that endpoint before enabling network
transport. Do not overload a fusion endpoint with this payload.

## Payload shape

```json
{
  "schema_version": "clinician_context_v1",
  "app_user_id": "P_...",
  "generated_at": "2026-08-25T09:00:00Z",
  "check_ins": {
    "seven_day": {
      "events": 4,
      "answered": 4,
      "confirmed_anxiety": 3,
      "not_confirmed": 1,
      "response_rate": 1.0,
      "confirmation_rate": 0.75,
      "common_context": "Studying or working",
      "intervention_attempts": 2,
      "followups_answered": 2,
      "felt_better_count": 1,
      "felt_better_rate": 0.5,
      "most_helpful_action": "2-minute paced breathing"
    },
    "thirty_day": {},
    "recent_events": [
      {
        "detected_at": "...",
        "source": "physiological_forecast",
        "participant_confirmed_anxiety": true,
        "context": "Studying or working",
        "action_taken": "2-minute paced breathing",
        "guided_intervention_completed": true,
        "followup_at": "...",
        "felt_better_at_followup": true
      }
    ]
  },
  "behavioral_context": {
    "status": "not_validated",
    "fusion_eligible": false,
    "score": null,
    "baseline_ready": true,
    "reportable": true,
    "patterns": [
      {
        "label": "Screen activity",
        "direction": "above",
        "within_person_z": 1.4
      }
    ],
    "change_detection": {
      "detected": true,
      "feature": "screen activity",
      "direction": "above",
      "ewma_z": 2.1
    },
    "data_quality": {
      "days_enrolled": 60,
      "baseline_days_required": 28,
      "baseline_usable_days": 26,
      "recent_usable_days": 7
    }
  }
}
```

## Clinician interpretation

Useful context includes:

- participant response to each Aura check-in (`felt anxious`, `did not feel anxious`, or unanswered);
- activity/context at the time of the check-in;
- intervention/action attempted;
- five-minute participant-reported outcome;
- 7-day and 30-day response/confirmation patterns;
- common context and most frequently helpful action;
- descriptive within-person behavioural directions;
- sustained behavioural change detection when the Day-57+ backend rule is met;
- baseline/data-quality coverage.

These fields should support clinical conversation, not replace assessment.

## Explicit exclusions

The handoff must not contain:

- exact GPS coordinates;
- raw location trails;
- individual app/package names;
- SMS/call content or contact identifiers;
- a Component 2 clinical risk probability;
- a fabricated zero score for Component 2;
- synthetic PP2 fixture values in production.

Component 2 remains `status = not_validated`, `fusion_eligible = false`, and
`score = null`. The central backend may display its descriptive behavioural
context, but it must not use that context as a numerical contribution to the
composite unless future validation supports a new deployment decision.
