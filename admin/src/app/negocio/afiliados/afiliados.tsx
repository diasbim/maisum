import Link from 'next/link';

import type {
  AffiliateCodeDto,
  AffiliateMetricsDto,
  MerchantAffiliateDto,
} from '@/lib/merchant-api';
import {
  affiliateCodeAvailability,
  affiliateCodeAvailabilityLabel,
  affiliateCodeAvailabilityTone,
  affiliateStanding,
  buildAffiliateShareMessage,
  buildWhatsAppShareUrl,
  canShareAffiliateCode,
  conversionRateText,
  describeBenefit,
  maskAffiliatePhone,
} from '@/lib/affiliate-form';
import {
  affiliateStatusLabel,
  affiliateStatusTone,
  benefitTypeLabel,
} from '@/lib/merchant-labels';
import { Badge, formatDateTime } from '../../admin/ui';

/**
 * The pieces every affiliate screen repeats.
 *
 * Three of them carry a rule rather than a layout, which is why they are here
 * and not inlined: what counts as "active" for an affiliate, when a code may
 * be shared at all, and what a conversion rate says when nobody has tried yet.
 * The rules themselves live in `affiliate-form.ts`, where they can be tested
 * without a browser; this file is only how they are drawn.
 */

export const AFFILIATES_PATH = '/negocio/afiliados';

export function affiliateHref(affiliateId: string): string {
  return `${AFFILIATES_PATH}/${encodeURIComponent(affiliateId)}`;
}

/**
 * How this affiliate stands with this business.
 *
 * Suspension comes from the platform and inactivity from the link, and the two
 * are told apart on purpose: an owner who reads "Suspenso" knows the decision
 * was not theirs and that reactivating here will not lift it.
 */
export function AffiliateStanding({
  affiliate,
}: {
  affiliate: MerchantAffiliateDto;
}) {
  const standing = affiliateStanding(affiliate);
  return (
    <Badge
      label={affiliateStatusLabel(standing)}
      tone={affiliateStatusTone(standing)}
    />
  );
}

export function CodeBadge({ code }: { code: AffiliateCodeDto | null }) {
  if (code === null) return <span className="muted">Sem código</span>;
  const availability = affiliateCodeAvailability(code);
  return (
    <Badge
      label={affiliateCodeAvailabilityLabel(availability)}
      tone={affiliateCodeAvailabilityTone(availability)}
    />
  );
}

/** The code itself, in the spelling it is printed and typed in. */
export function CodeText({ code }: { code: AffiliateCodeDto | null }) {
  if (code === null) return <span className="muted">—</span>;
  return <code className="inline">{code.code}</code>;
}

export function benefitText(code: AffiliateCodeDto | null): string {
  if (code === null) return '—';
  return (
    describeBenefit(code.benefit_type, code.benefit_value) ??
    benefitTypeLabel(code.benefit_type) ??
    code.benefit_type
  );
}

/** A number the owner typed, shown as a list may show it. */
export function maskedPhone(affiliate: {
  phone: string | null;
  phone_last4: string | null;
}): string {
  return maskAffiliatePhone(affiliate.phone, affiliate.phone_last4);
}

/**
 * The share control, and nothing at all when there is nothing safe to share.
 *
 * A plain link: it opens WhatsApp with the message ready and the owner chooses
 * who receives it. Nothing is sent by the portal, no JavaScript is shipped for
 * it, and a code the till would refuse — disabled, unlinked, suspended — has
 * no control rather than one that makes a promise the business cannot keep.
 */
export function ShareCode({
  affiliate,
  businessName,
  variant = 'btn-outline btn-sm',
}: {
  affiliate: MerchantAffiliateDto;
  businessName: string;
  variant?: string;
}) {
  if (!canShareAffiliateCode(affiliate) || affiliate.code === null) return null;

  const message = buildAffiliateShareMessage({
    code: affiliate.code.code,
    businessName,
    benefitType: affiliate.code.benefit_type,
    benefitValue: affiliate.code.benefit_value,
  });

  return (
    <a
      className={`btn ${variant}`}
      href={buildWhatsAppShareUrl({ message, phone: affiliate.phone })}
      rel="noopener noreferrer"
      target="_blank"
    >
      Partilhar código
      <span className="sr-only"> de {affiliate.name} no WhatsApp</span>
    </a>
  );
}

/**
 * Why a control is missing, for whoever cannot use it.
 *
 * A manager sees every one of these screens and none of the buttons. Saying so
 * out loud is the difference between a page that looks broken and a page that
 * explains whose decision this is — and the id is what lets a disabled button
 * point at the sentence rather than leaving it to be found by scrolling.
 */
export const READ_ONLY_REASON_ID = 'afiliados-somente-leitura';

export function ReadOnlyNotice({ reason }: { reason: string | null }) {
  if (reason === null) return null;
  return (
    <p className="notice notice--warn" id={READ_ONLY_REASON_ID} role="status">
      {reason}
    </p>
  );
}

/**
 * The six numbers the programme is judged on.
 *
 * `conversionRateText` is what keeps the third card honest: a business where
 * nobody has typed a code yet has no rate, and printing "0%" on the screen an
 * owner opens to find out whether anyone has tried would answer a question
 * nobody asked. Every card is a number and a word — none of them needs colour
 * to be read.
 */
export function AffiliateMetrics({
  metrics,
  heading,
}: {
  metrics: AffiliateMetricsDto;
  heading?: string;
}) {
  const number = (value: number) => value.toLocaleString('pt-PT');

  const cards: Array<[string, string, string]> = [
    [
      'Códigos validados',
      number(metrics.unique_validation_attempts),
      'Tentativas diferentes ao balcão',
    ],
    [
      'Indicações confirmadas',
      number(metrics.confirmed_attributions),
      'Clientes novos com código aceite',
    ],
    [
      'Taxa de conversão',
      conversionRateText(metrics),
      'Confirmadas por tentativa',
    ],
    [
      'Clientes que voltaram',
      number(metrics.returned_customers),
      'Segunda visita de um cliente indicado',
    ],
    [
      'Pontos por aprovar',
      number(metrics.pending_reward_points),
      `${number(metrics.pending_reward_count)} recompensas pendentes`,
    ],
    [
      'Pontos aprovados',
      number(metrics.approved_reward_points),
      `${number(metrics.approved_reward_count)} recompensas aprovadas`,
    ],
  ];

  return (
    <>
      {heading ? <p className="section-label">{heading}</p> : null}
      <div className="grid">
        {cards.map(([label, value, hint]) => (
          <div className="card" key={label}>
            <p className="metric-label">{label}</p>
            <p className="metric-value">{value}</p>
            <p className="micro">{hint}</p>
          </div>
        ))}
      </div>
      <p className="micro" role="status">
        Última atividade:{' '}
        {metrics.last_activity_at === null
          ? 'ainda sem atividade'
          : formatDateTime(metrics.last_activity_at)}
        {metrics.truncated
          ? ' · Estes números foram calculados sobre uma parte dos registos.'
          : ''}
      </p>
    </>
  );
}

/** The link back, shared by the pages that sit under the list. */
export function BackToAffiliates() {
  return (
    <Link className="btn btn-outline btn-sm" href={AFFILIATES_PATH}>
      ← Todos os afiliados
    </Link>
  );
}
