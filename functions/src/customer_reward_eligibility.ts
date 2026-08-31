export function isCustomerRewardExpired(
  reward: Record<string, unknown>,
  now = Date.now(),
): boolean {
  const raw = reward.expires_at ?? reward.expiresAt;
  return typeof raw === 'number' &&
    Number.isFinite(raw) &&
    raw > 0 &&
    raw <= now;
}
