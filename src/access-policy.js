const PAID = new Set(["pooshe_pro_yearly","pooshe_pro_6_months","pooshe_pro_3_months","pooshe_pro_monthly"]);
export const TRIAL_DURATION_MS = 7 * 24 * 60 * 60 * 1000;
export function evaluateAccess({ now, trialStartedAt, activeProductIds = [] }) {
  const ids = new Set(activeProductIds);
  const paid = [...ids].some(id => PAID.has(id));
  const bazaarTrial = ids.has("trial_subscription");
  const localTrial = Number.isFinite(Number(trialStartedAt)) && Number(trialStartedAt) > 0 &&
    now >= Number(trialStartedAt) && now < Number(trialStartedAt) + TRIAL_DURATION_MS;
  const trial = !paid && (bazaarTrial || localTrial);
  return { active: paid || trial, paid, trial, bazaarTrial, localTrial, readOnly: !(paid || trial) };
}
export function isWriteActionAllowed(access, action) {
  const allowedInReadOnly = new Set(["view","search","filter","settings","backup","restore","library"]);
  return !access.readOnly || allowedInReadOnly.has(action);
}
