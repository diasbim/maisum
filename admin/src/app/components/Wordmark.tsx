/**
 * The MaisUm brand mark.
 *
 * Used by the signed-in topbar (on navy) and the signed-out auth screens (on
 * white), which previously each hand-rolled the same dot-plus-name markup
 * with inline styles. `tone` picks the one thing that actually differs.
 *
 * `area` names the surface after the brand. "Operações" is the internal
 * console; a business owner is not in it, and being told they are is the kind
 * of small wrongness that makes people doubt the rest of the screen.
 */
export function Wordmark({
  tone,
  area = 'Operações',
}: {
  tone: 'onDark' | 'onLight';
  area?: string | null;
}) {
  return (
    <span className={`wordmark wordmark--${tone}`}>
      <span className="wordmark__dot" aria-hidden="true" />
      <span className="wordmark__name">
        {area ? `MaisUm · ${area}` : 'MaisUm'}
      </span>
    </span>
  );
}
