# BUG-053 — Checker outcome was not persisted

## Symptom

The privacy audit proved that a plaintext reasoning record was sent to the
configured checker, but after the UI closed there was no durable evidence of
whether the provider returned an alert, a clean verdict, or an error.

## Cause

`PrivacyAudit` recorded only `external_reasoning_request`. The completion path
updated in-memory UI state but wrote no paired audit event.

## Fix

Every provider attempt now receives a request ID. The audit writes a paired
`external_reasoning_result` containing the request ID, provider, source, record
type, status (`alert`, `clean`, or `error`), optional alert boolean, and latency.
It remains content-free: instructions, evidence, model output, and credentials
are not written to the audit.

## Verification

The privacy-audit self-test requires a request/result pair with the same ID and
asserts that no sensitive fixture content is present.
