import { NextResponse, type NextRequest } from 'next/server';

export const runtime = 'nodejs';

/**
 * Where the sign-in form goes when JavaScript never took hold.
 *
 * The form signs in from the browser — it needs the Firebase SDK to get an ID
 * token before this server ever hears about the attempt — so there is no
 * no-script path that can actually sign anyone in. What matters is where the
 * credentials go in the meantime.
 *
 * A `<form>` with no `method` submits as a GET, which puts whatever was typed
 * into the query string: the address bar, the browser history, this server's
 * access log, and the `Referer` of every request the page makes afterwards.
 * Pointing the form here, as a POST, keeps the password in a request body that
 * is then discarded unread.
 *
 * The redirect is a 303 so the browser follows it with a GET and the body does
 * not travel any further.
 */
export async function POST(request: NextRequest) {
  const destino = new URL('/login', request.nextUrl.origin);
  destino.searchParams.set('erro', 'sem-javascript');

  // `next` is the only thing worth carrying across: it names a page, never a
  // credential, and losing it would send the operator to the wrong place once
  // they get back in.
  const next = request.nextUrl.searchParams.get('next');
  if (next !== null && next.startsWith('/')) {
    destino.searchParams.set('next', next);
  }

  return NextResponse.redirect(destino, 303);
}
