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

import fs from "node:fs";
const mainSource = fs.readFileSync("src/main.js", "utf8");
const accessSource = fs.readFileSync("src/access-control.js", "utf8");
const nativeSource = fs.readFileSync("native/android/CafeBazaarBillingPlugin.kt.tpl", "utf8");
const androidSetup = fs.readFileSync("scripts/configure-android-backup.mjs", "utf8");

test("all approved Pooshe SKUs are present in JS and native allowlist", () => {
  for (const sku of ["trial_subscription","pooshe_pro_yearly","pooshe_pro_6_months","pooshe_pro_3_months","pooshe_pro_monthly"]) {
    assert.ok(accessSource.includes('id: "' + sku + '"'), "JS catalog missing " + sku);
    assert.ok(nativeSource.includes('"' + sku + '"'), "Native allowlist missing " + sku);
  }
});
test("case mutations, exports and judicial printing have central access guards", () => {
  for (const token of [
    'function newCase(){if(!requireWriteAccess',
    'function caseForm(c){if(!requireWriteAccess',
    'function stepForm(c,s){if(!requireWriteAccess',
    'function addStepFiles(c,s,files){if(!requireWriteAccess',
    'function exportSheet(title,headers,rows){if(!requireWriteAccess',
    'function printReport(title,headers,rows){if(!requireWriteAccess',
    'function printJudicialForm(c,s,f,data){if(!requireWriteAccess'
  ]) assert.ok(mainSource.includes(token), "missing guard: " + token);
  assert.ok(mainSource.includes("poosheWriteClickSelector"), "event-boundary write guard missing");
  assert.ok(mainSource.includes("initializeAccessControl(S,save"), "entitlement initialization missing");
});
test("native build configuration registers Poolakey plugin and Bazaar permission", () => {
  assert.ok(androidSetup.includes("CafeBazaarBillingPlugin.class"));
  assert.ok(androidSetup.includes("poolakey:2.1.0"));
  assert.ok(androidSetup.includes("PAY_THROUGH_BAZAAR"));
});
