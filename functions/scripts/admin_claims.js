#!/usr/bin/env node
/**
 * Grant, revoke and list the internal admin claim.
 *
 * There was previously no tooling for this anywhere in the repository, so the
 * admin portal had no supported way to onboard an operator.
 *
 * The claim set granted here must stay consistent with:
 *   - functions/src/admin_access.ts  -> hasAdminClaims()
 *   - firestore.rules                -> isAdmin()
 *   - lib/features/auth/presentation/auth_controller.dart
 *
 * Usage (run from functions/, with credentials for the target project):
 *
 *   node scripts/admin_claims.js --list
 *   node scripts/admin_claims.js --grant  --email ops@example.com --yes
 *   node scripts/admin_claims.js --revoke --email ops@example.com --yes
 *   node scripts/admin_claims.js --grant  --uid abc123 --yes
 *
 * Credentials come from Application Default Credentials:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 * or `gcloud auth application-default login`.
 *
 * Mutations require --yes so a mistyped command cannot change production
 * access. Revoking also revokes refresh tokens, so access ends within about an
 * hour rather than when the current ID token happens to expire.
 */

const admin = require('firebase-admin');
// Compiled output of src/admin_access.ts — run `npm run build` first if this
// throws. Importing it keeps the granted claim and the predicate that reads it
// from drifting apart.
const {
  PRIMARY_ADMIN_CLAIM,
  hasAdminClaims,
  withAdminClaim,
} = require('../lib/admin_access.js');

function parseArgs(argv) {
  const args = { action: null, email: null, uid: null, confirmed: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case '--grant':
      case '--revoke':
      case '--list':
        if (args.action) fail(`Specify only one of --grant, --revoke, --list.`);
        args.action = arg.slice(2);
        break;
      case '--email':
        args.email = argv[++i] ?? null;
        break;
      case '--uid':
        args.uid = argv[++i] ?? null;
        break;
      case '--yes':
        args.confirmed = true;
        break;
      case '--help':
      case '-h':
        printUsage();
        process.exit(0);
        break;
      default:
        fail(`Unknown argument: ${arg}`);
    }
  }
  return args;
}

function printUsage() {
  process.stdout.write(
    'Usage:\n' +
      '  node scripts/admin_claims.js --list\n' +
      '  node scripts/admin_claims.js --grant  (--email <e> | --uid <u>) --yes\n' +
      '  node scripts/admin_claims.js --revoke (--email <e> | --uid <u>) --yes\n',
  );
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  printUsage();
  process.exit(1);
}

async function resolveUser(auth, { email, uid }) {
  if (uid) return auth.getUser(uid);
  if (email) return auth.getUserByEmail(email);
  return fail('Provide --email or --uid.');
}

async function listAdmins(auth) {
  const admins = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      const claims = user.customClaims ?? {};
      if (hasAdminClaims(claims)) {
        admins.push({
          uid: user.uid,
          email: user.email ?? '(no email)',
          claims: JSON.stringify(claims),
        });
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);

  if (admins.length === 0) {
    process.stdout.write('No users currently hold an admin claim.\n');
    return;
  }
  process.stdout.write(`${admins.length} user(s) with admin access:\n`);
  for (const entry of admins) {
    process.stdout.write(`  ${entry.email}  uid=${entry.uid}  ${entry.claims}\n`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.action) {
    fail('Specify --grant, --revoke or --list.');
  }

  // Checked before touching credentials or the network, so a mistyped command
  // fails immediately and locally.
  if (args.action !== 'list') {
    if (!args.email && !args.uid) {
      fail('Provide --email or --uid.');
    }
    if (!args.confirmed) {
      fail(`Refusing to ${args.action} admin access without --yes.`);
    }
  }

  admin.initializeApp();
  const auth = admin.auth();
  const projectId =
    process.env.GOOGLE_CLOUD_PROJECT ??
    process.env.GCLOUD_PROJECT ??
    admin.app().options.projectId ??
    '(unknown project)';

  if (args.action === 'list') {
    process.stdout.write(`Project: ${projectId}\n`);
    await listAdmins(auth);
    return;
  }

  const grant = args.action === 'grant';
  const user = await resolveUser(auth, args);
  const before = user.customClaims ?? {};
  const after = withAdminClaim(before, grant);
  await auth.setCustomUserClaims(user.uid, after);

  if (!grant) {
    // Existing ID tokens stay valid until they expire; revoking refresh tokens
    // bounds that window instead of leaving it open.
    await auth.revokeRefreshTokens(user.uid);
  }

  // Printed so the operator can record the change in the admin audit trail.
  // Server-side persistence to admin_audit_events is deferred until the
  // PostgreSQL question (Q2 in docs/web_admin_portal_code_plan.md) is settled.
  process.stdout.write(
    `AUDIT ${new Date().toISOString()} ` +
      `action=${grant ? 'admin_claim_granted' : 'admin_claim_revoked'} ` +
      `project=${projectId} uid=${user.uid} email=${user.email ?? ''} ` +
      `before=${JSON.stringify(before)} after=${JSON.stringify(after)}\n`,
  );
  process.stdout.write(
    grant
      ? `Granted "${PRIMARY_ADMIN_CLAIM}". The user must obtain a fresh ID ` +
          'token before the portal recognizes it (sign out and back in).\n'
      : 'Revoked, and refresh tokens invalidated.\n',
  );
}

main().catch((error) => {
  process.stderr.write(`${error?.message ?? error}\n`);
  process.exit(1);
});
