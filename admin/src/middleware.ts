import { NextResponse, type NextRequest } from 'next/server';

import { SESSION_COOKIE } from '@/lib/session-cookie';

/**
 * Cheap gate only: it redirects when no session cookie is present, so signed-out
 * visitors do not render a protected shell before bouncing.
 *
 * It deliberately does NOT verify the token. Middleware cannot be the only
 * authorization check — every protected page calls `getAdminSession()`, which
 * verifies the token and the admin claim server-side. Treat this as a
 * redirect optimization, not security.
 */
export function middleware(request: NextRequest) {
  const hasCookie = request.cookies.has(SESSION_COOKIE);
  const { pathname, search } = request.nextUrl;

  if (!hasCookie) {
    const login = new URL('/login', request.url);
    if (pathname !== '/') {
      login.searchParams.set('next', `${pathname}${search}`);
    }
    return NextResponse.redirect(login);
  }

  return NextResponse.next();
}

export const config = {
  // Everything except the login page, the session endpoint, and static assets.
  matcher: ['/((?!login|api/session|_next/static|_next/image|favicon.ico|robots.txt).*)'],
};
