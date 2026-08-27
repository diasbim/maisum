import { createHmac, timingSafeEqual } from 'crypto';

type CustomerQrPayload = {
  v: 1;
  sub: string;
  iat: number;
  exp: number;
};

export type VerifiedCustomerQrToken = {
  subject: string;
  issuedAt: number;
  expiresAt: number;
};

function sign(encodedPayload: string, secret: string): string {
  return createHmac('sha256', secret).update(`customer-qr-v1.${encodedPayload}`).digest(
    'base64url',
  );
}

export function createCustomerQrToken(input: {
  subject: string;
  issuedAt: number;
  expiresAt: number;
  secret: string;
}): string {
  const payload: CustomerQrPayload = {
    v: 1,
    sub: input.subject,
    iat: input.issuedAt,
    exp: input.expiresAt,
  };
  const encodedPayload = Buffer.from(JSON.stringify(payload), 'utf8').toString(
    'base64url',
  );
  return `cq1.${encodedPayload}.${sign(encodedPayload, input.secret)}`;
}

export function verifyCustomerQrToken(input: {
  token: string;
  secret: string;
  now: number;
}): VerifiedCustomerQrToken | null {
  const parts = input.token.split('.');
  if (parts.length !== 3 || parts[0] !== 'cq1' || !parts[1] || !parts[2]) {
    return null;
  }

  const expectedSignature = sign(parts[1], input.secret);
  const receivedSignature = parts[2];
  const expected = Buffer.from(expectedSignature);
  const received = Buffer.from(receivedSignature);
  if (
    expected.length !== received.length ||
    !timingSafeEqual(expected, received)
  ) {
    return null;
  }

  let payload: CustomerQrPayload;
  try {
    payload = JSON.parse(
      Buffer.from(parts[1], 'base64url').toString('utf8'),
    ) as CustomerQrPayload;
  } catch {
    return null;
  }
  if (
    payload.v !== 1 ||
    typeof payload.sub !== 'string' ||
    !/^[A-Za-z0-9_-]{16,128}$/.test(payload.sub) ||
    !Number.isSafeInteger(payload.iat) ||
    !Number.isSafeInteger(payload.exp) ||
    payload.iat > input.now ||
    payload.exp <= input.now ||
    payload.exp <= payload.iat
  ) {
    return null;
  }

  return {
    subject: payload.sub,
    issuedAt: payload.iat,
    expiresAt: payload.exp,
  };
}
