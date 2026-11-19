/**
 * Pure rules engine (addendum §B, master prompt rule 5).
 * No I/O, no clock access, no randomness: time is always passed in. Enforced by eslint.config.js.
 * Real logic arrives in M4 (step generation) and M6 (step status, risk, alerts, score).
 */
export const RULES_PACKAGE_VERSION = '0.0.0';
