import Link from 'next/link';

/**
 * The parts every list screen in the business area repeats.
 *
 * A plain GET form rather than a client component: the filtered view is then a
 * real URL that survives a reload and can be pasted into a message, and the
 * screen ships no JavaScript to do it.
 */

export function SearchForm({
  action,
  label,
  placeholder,
  value,
  keep,
}: {
  action: string;
  label: string;
  placeholder: string;
  value: string;
  /** Filters to carry through the submit, so searching does not clear them. */
  keep?: Record<string, string | undefined>;
}) {
  return (
    <form className="record-search" method="get" action={action}>
      {Object.entries(keep ?? {}).map(([name, kept]) =>
        kept ? <input key={name} type="hidden" name={name} value={kept} /> : null,
      )}
      <input
        className="input"
        type="search"
        name="search"
        aria-label={label}
        placeholder={placeholder}
        defaultValue={value}
      />
      <button className="btn btn-navy" type="submit">
        Procurar
      </button>
      {value ? (
        <Link className="btn btn-outline" href={action}>
          Limpar
        </Link>
      ) : null}
    </form>
  );
}

/**
 * Says when a list is not the whole list.
 *
 * A business past the read cap would otherwise see a page that looks complete
 * and quietly is not — worse than a number that admits its own limit.
 */
export function TruncationNotice({ truncated }: { truncated: boolean }) {
  if (!truncated) return null;
  return (
    <p className="notice notice--warn" role="status">
      Esta lista é grande demais para mostrar de uma vez. Está a ver a primeira
      parte — use a procura para chegar ao que precisa.
    </p>
  );
}

/** Row count, phrased so that zero and one do not read as bugs. */
export function ResultCount({
  total,
  singular,
  plural,
}: {
  total: number;
  singular: string;
  plural: string;
}) {
  return (
    <p className="micro" role="status">
      {total === 0
        ? `Nenhum ${singular}`
        : total === 1
          ? `1 ${singular}`
          : `${total.toLocaleString('pt-PT')} ${plural}`}
    </p>
  );
}
