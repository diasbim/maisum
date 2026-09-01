/**
 * The `details` payload of an audit event, collapsed by default.
 *
 * These carry the before/after of an override, which is the part that answers
 * "what actually changed" — but expanded inline it would push a table of
 * twenty-five events over several screens. A native `<details>` keeps it one
 * click away with no JavaScript, so it works in a printed page too.
 */
export function AuditDetails({ details }: { details: Record<string, unknown> }) {
  const keys = Object.keys(details ?? {});
  if (keys.length === 0) return <span className="muted">—</span>;

  return (
    <details>
      <summary
        style={{
          cursor: 'pointer',
          fontSize: '0.76rem',
          color: 'var(--g500)',
          fontWeight: 600,
        }}
      >
        {keys.length} campo{keys.length === 1 ? '' : 's'}
      </summary>
      <pre className="output" style={{ marginTop: 8, maxWidth: 460 }}>
        {JSON.stringify(details, null, 2)}
      </pre>
    </details>
  );
}
