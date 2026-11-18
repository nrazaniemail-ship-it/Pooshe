import test from "node:test";
import assert from "node:assert/strict";
import { evaluateAccess, TRIAL_DURATION_MS, isWriteActionAllowed } from "../src/access-policy.js";

const start = Date.UTC(2026, 0, 1);
test("first seven days of local trial grant access", () => {
  assert.equal(evaluateAccess({ now:start + 1, trialStartedAt:start }).active, true);
  assert.equal(evaluateAccess({ now:start + TRIAL_DURATION_MS - 1, trialStartedAt:start }).readOnly, false);
});
test("local trial expires exactly at seven days", () => {
  const s = evaluateAccess({ now:start + TRIAL_DURATION_MS, trialStartedAt:start });
  assert.equal(s.readOnly, true);
  assert.equal(s.active, false);
});
test("paid Bazaar subscription grants full access after local trial expires", () => {
  const s = evaluateAccess({ now:start + TRIAL_DURATION_MS * 3, trialStartedAt:start, activeProductIds:["pooshe_pro_monthly"] });
  assert.equal(s.paid, true);
  assert.equal(s.readOnly, false);
});
test("Bazaar trial grants access only while Bazaar reports it active", () => {
  assert.equal(evaluateAccess({ now:start + TRIAL_DURATION_MS * 3, trialStartedAt:start, activeProductIds:["trial_subscription"] }).readOnly, false);
  assert.equal(evaluateAccess({ now:start + TRIAL_DURATION_MS * 3, trialStartedAt:start }).readOnly, true);
});
test("read-only mode preserves viewing, search, settings, backup and restore", () => {
  const s = evaluateAccess({ now:start + TRIAL_DURATION_MS, trialStartedAt:start });
  for (const action of ["view","search","filter","settings","backup","restore","library"]) assert.equal(isWriteActionAllowed(s,action),true,action);
});
test("read-only mode blocks all case mutations and exports", () => {
  const s = evaluateAccess({ now:start + TRIAL_DURATION_MS, trialStartedAt:start });
  for (const action of ["create","update","delete","step","attachment","status","reminder","excel","pdf","print"]) assert.equal(isWriteActionAllowed(s,action),false,action);
});
