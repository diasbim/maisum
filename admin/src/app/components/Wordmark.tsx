/**
 * The "MaisUm · Operações" brand mark.
 *
 * Used by the signed-in topbar (on navy) and the signed-out auth screens (on
 * white), which previously each hand-rolled the same dot-plus-name markup
 * with inline styles. `tone` picks the one thing that actually differs.
 */
export function Wordmark({ tone }: { tone: 'onDark' | 'onLight' }) {
  return (
    <span className={`wordmark wordmark--${tone}`}>
      <span className="wordmark__dot" aria-hidden="true" />
      <span className="wordmark__name">MaisUm · Operações</span>
    </span>
  );
}
