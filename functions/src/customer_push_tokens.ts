export type CustomerPushPlatform = 'android' | 'ios' | 'web';

export type CustomerPushToken = {
  platform: CustomerPushPlatform;
  token: string;
};

const supportedPlatforms = new Set<CustomerPushPlatform>([
  'android',
  'ios',
  'web',
]);
const fcmTokenPattern = /^[A-Za-z0-9_:-]+$/;

export function normalizeCustomerPushToken(
  value: unknown,
): CustomerPushToken {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('invalid_push_token_payload');
  }

  const payload = value as Record<string, unknown>;
  const keys = Object.keys(payload);
  if (
    keys.length !== 2 ||
    !keys.includes('platform') ||
    !keys.includes('token')
  ) {
    throw new Error('invalid_push_token_payload');
  }

  const platform =
    typeof payload.platform === 'string' ? payload.platform.trim() : '';
  const token = typeof payload.token === 'string' ? payload.token.trim() : '';
  if (
    !supportedPlatforms.has(platform as CustomerPushPlatform) ||
    token.length < 20 ||
    token.length > 4096 ||
    !fcmTokenPattern.test(token)
  ) {
    throw new Error('invalid_push_token_payload');
  }

  return { platform: platform as CustomerPushPlatform, token };
}
