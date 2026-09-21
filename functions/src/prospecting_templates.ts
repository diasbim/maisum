import {
  findIcpIndustry,
  OUTREACH_MAX_CHARS,
  DEFAULT_OUTREACH_LOCALE,
} from './prospecting_config.js';
import {
  blocksOutreach,
  type OutreachChannel,
  type ProspectStatus,
} from './prospecting_contracts.js';
import type { CompanyRecord, PersonRecord } from './prospecting_providers.js';

/**
 * Messages from templates, not from a model.
 *
 * A model invents, which is why `prospecting_analysis.ts` wraps every claim in
 * a source and refuses a reply it cannot validate. A template cannot invent —
 * but it has its own failure, and it is quieter: it interpolates *nothing*.
 * "Olá 👋, encontrei o vosso espaço no Google" with the name missing reads as
 * a bulk mailer that could not be bothered, and it is the first impression a
 * business gets of MaisUm.
 *
 * So the rule here is the counterpart of the anti-fabrication rule over there:
 *
 *   **A missing variable aborts the render. It never produces a partial
 *   message.**
 *
 * The second difference from the model path is where length is enforced. The
 * model was asked for 600 characters and checked afterwards, because a model
 * asked for 600 will sometimes write 900. A template's length is knowable
 * before it is ever used, so `validateTemplate` runs when the template is
 * *saved* and the operator is told "excede 600 caracteres para WhatsApp" while
 * they are still editing — rather than discovering a truncated sentence in a
 * message that has already gone out. The runtime cut stays as a backstop for
 * data longer than the assumed worst case, and reports itself when it fires.
 */

/* ------------------------------------------------------------- variables */

/**
 * Every variable a template may use, and the longest each is assumed to be.
 *
 * A whitelist rather than "whatever is on the company record", for two
 * reasons. A typo in a template becomes a refusal at save time instead of a
 * literal `{{bussiness_name}}` in a message to a stranger. And the lengths
 * make the channel limit checkable before the template is ever rendered — a
 * worst case that is stated rather than hoped for.
 */
export const TEMPLATE_VARIABLES = {
  business_name: 60,
  city: 30,
  category: 30,
  contact_first_name: 30,
} as const;

export type TemplateVariable = keyof typeof TEMPLATE_VARIABLES;

export function isTemplateVariable(name: string): name is TemplateVariable {
  return Object.prototype.hasOwnProperty.call(TEMPLATE_VARIABLES, name);
}

/** `{{ business_name }}`, tolerant of the spaces an operator will type. */
const PLACEHOLDER = /\{\{\s*([a-z_]+)\s*\}\}/g;

export function variablesUsed(text: string): string[] {
  const found = new Set<string>();
  for (const match of text.matchAll(PLACEHOLDER)) {
    if (match[1] !== undefined) found.add(match[1]);
  }
  return [...found];
}

/* ------------------------------------------------------------- the model */

export type OutreachTemplate = {
  /** `barbershop-whatsapp-v1`. Stored on the activity, so A/B is measurable. */
  id: string;
  channel: OutreachChannel;
  /** An ICP `businessType`, or null for the one that fits any trade. */
  businessType: string | null;
  subject: string | null;
  body: string;
};

export type TemplateProblem =
  | { code: 'UNKNOWN_VARIABLE'; detail: string }
  | { code: 'TOO_LONG'; detail: string }
  | { code: 'SUBJECT_REQUIRED'; detail: string }
  | { code: 'SUBJECT_NOT_ALLOWED'; detail: string }
  | { code: 'EMPTY'; detail: string };

export const TEMPLATE_PROBLEM_MESSAGE: Record<TemplateProblem['code'], string> = {
  UNKNOWN_VARIABLE: 'O template usa uma variável que não existe.',
  TOO_LONG: 'O template excede o limite de caracteres do canal.',
  SUBJECT_REQUIRED: 'Uma mensagem de email precisa de assunto.',
  SUBJECT_NOT_ALLOWED: 'Este canal não tem assunto.',
  EMPTY: 'O template está vazio.',
};

/**
 * What a template costs at its longest, before anyone uses it.
 *
 * Each placeholder is priced at the maximum length its variable is allowed to
 * be, so the answer is an upper bound rather than a sample. A template that
 * passes this cannot be cut at render time for any business whose name fits in
 * sixty characters — which is the promise the save-time check is making.
 */
export function worstCaseLength(body: string): number {
  return body.replace(PLACEHOLDER, (match, name: string) =>
    isTemplateVariable(name) ? 'x'.repeat(TEMPLATE_VARIABLES[name]) : match,
  ).length;
}

/**
 * Whether a template may be saved.
 *
 * Returns every problem rather than the first, because an operator editing a
 * message should not have to fix one thing, save, and be told about the next.
 */
export function validateTemplate(template: OutreachTemplate): TemplateProblem[] {
  const problems: TemplateProblem[] = [];

  if (template.body.trim() === '') {
    problems.push({ code: 'EMPTY', detail: 'body' });
  }

  for (const name of [
    ...variablesUsed(template.body),
    ...variablesUsed(template.subject ?? ''),
  ]) {
    if (!isTemplateVariable(name)) {
      problems.push({ code: 'UNKNOWN_VARIABLE', detail: name });
    }
  }

  const limit = OUTREACH_MAX_CHARS[template.channel];
  const worst = worstCaseLength(template.body);
  if (worst > limit) {
    problems.push({
      code: 'TOO_LONG',
      detail: `${worst} > ${limit}`,
    });
  }

  // The subject rule is per channel and absolute: an email with no subject
  // goes to spam, and a WhatsApp message with one has nowhere to put it.
  if (template.channel === 'EMAIL' && (template.subject ?? '').trim() === '') {
    problems.push({ code: 'SUBJECT_REQUIRED', detail: template.id });
  }
  if (template.channel !== 'EMAIL' && (template.subject ?? '').trim() !== '') {
    problems.push({ code: 'SUBJECT_NOT_ALLOWED', detail: template.id });
  }

  return problems;
}

/* ------------------------------------------------------------ the defaults */

/**
 * The starting set, in the voice the rest of the product uses.
 *
 * Four templates, not forty: one per tier-1 trade where the pitch genuinely
 * differs, and a generic that covers everything else. A/B testing starts by
 * adding `-v2` beside one of these, not by writing a template per industry
 * before a single reply has come back.
 *
 * None of them address a person by name. Discovery reads a shop listing, and
 * a shop listing does not carry the owner's name — a template that assumed one
 * would abort on every lead the pipeline can currently produce.
 */
export const DEFAULT_TEMPLATES: readonly OutreachTemplate[] = [
  {
    id: 'barbershop-whatsapp-v1',
    channel: 'WHATSAPP',
    businessType: 'barbershop',
    subject: null,
    body: [
      'Olá {{business_name}} 👋',
      '',
      'Encontrei o vosso espaço enquanto procurava barbearias em {{city}}.',
      '',
      'Ajudamos negócios como o vosso a transformar clientes ocasionais em',
      'clientes habituais, com um sistema simples de fidelização por pontos.',
      '',
      'Posso mostrar-lhe como funciona, em cinco minutos?',
    ].join('\n'),
  },
  {
    id: 'salon-whatsapp-v1',
    channel: 'WHATSAPP',
    businessType: 'salon',
    subject: null,
    body: [
      'Olá {{business_name}} 👋',
      '',
      'Vi o vosso salão em {{city}} e reparei no cuidado com o espaço.',
      '',
      'Trabalhamos com salões que querem que a cliente volte no mês seguinte:',
      'pontos por visita, histórico de serviços e lembretes de regresso.',
      '',
      'Faz sentido mostrar-lhe como funciona?',
    ].join('\n'),
  },
  {
    id: 'generic-whatsapp-v1',
    channel: 'WHATSAPP',
    businessType: null,
    subject: null,
    body: [
      'Olá {{business_name}} 👋',
      '',
      'Encontrei o vosso negócio enquanto procurava {{category}} em {{city}}.',
      '',
      'A MaisUm ajuda pequenos negócios a transformar clientes ocasionais em',
      'clientes habituais, com fidelização simples por pontos.',
      '',
      'Posso mostrar-lhe como funciona?',
    ].join('\n'),
  },
  {
    id: 'generic-email-v1',
    channel: 'EMAIL',
    businessType: null,
    subject: 'Clientes que voltam, em {{city}}',
    body: [
      'Bom dia,',
      '',
      'Encontrei a {{business_name}} enquanto procurava {{category}} em {{city}}.',
      '',
      'A MaisUm ajuda pequenos negócios a transformar clientes ocasionais em',
      'clientes habituais: fidelização por pontos, perfis de cliente e',
      'recuperação de clientes que deixaram de aparecer.',
      '',
      'Se fizer sentido, mostro-lhe como funciona numa chamada curta.',
      '',
      'Com os melhores cumprimentos,',
      'Equipa MaisUm',
    ].join('\n'),
  },
];

/* ------------------------------------------------------------ the selection */

/**
 * The template for a trade and a channel, most specific first.
 *
 * A trade-specific template beats the generic one; no template for the channel
 * at all is null, and the caller reports it rather than falling back to another
 * channel. Sending a WhatsApp message because no email template existed would
 * be a channel nobody chose.
 */
export function selectTemplate(input: {
  channel: OutreachChannel;
  businessType: string | null;
  templates: readonly OutreachTemplate[];
}): OutreachTemplate | null {
  const forChannel = input.templates.filter(
    (entry) => entry.channel === input.channel,
  );
  const specific = forChannel.find(
    (entry) =>
      entry.businessType !== null && entry.businessType === input.businessType,
  );
  return specific ?? forChannel.find((entry) => entry.businessType === null) ?? null;
}

/**
 * The channels that can actually produce a message.
 *
 * Intersected with the channels a lead is *reachable* on before anything is
 * offered. Being reachable by SMS and having an SMS template are different
 * facts, and offering a channel with no template behind it means an operator
 * picks it, waits, and is told the message could not be written — a dead end
 * the screen could have avoided showing.
 */
export function channelsWithTemplate(
  templates: readonly OutreachTemplate[] = DEFAULT_TEMPLATES,
): OutreachChannel[] {
  return [...new Set(templates.map((entry) => entry.channel))];
}

/* -------------------------------------------------------------- rendering */

export class TemplateError extends Error {
  readonly code: 'NO_TEMPLATE' | 'MISSING_VARIABLE' | 'INVALID_TEMPLATE';
  readonly detail: string;

  constructor(code: TemplateError['code'], detail: string) {
    super(`${code}: ${detail}`);
    this.name = 'TemplateError';
    this.code = code;
    this.detail = detail;
  }
}

export class OutreachBlockedError extends Error {
  readonly status: ProspectStatus;

  constructor(status: ProspectStatus) {
    super(`outreach blocked for status ${status}`);
    this.name = 'OutreachBlockedError';
    this.status = status;
  }
}

export type TemplateRequest = {
  channel: OutreachChannel;
  company: CompanyRecord;
  contact: PersonRecord | null;
  status: ProspectStatus;
  locale?: string;
  templates?: readonly OutreachTemplate[];
  /** Pins one template, for regenerating a specific A/B arm. */
  templateId?: string | null;
};

export type TemplateDraft = {
  channel: OutreachChannel;
  locale: string;
  subject: string | null;
  body: string;
  /** The template that produced it. Stored, so reply rates attach to a version. */
  templateId: string;
  /** What the message was addressed to. Never invented. */
  addressedTo: string | null;
  /** True when the backstop cut fired. Should never happen after validation. */
  truncated: boolean;
};

/**
 * The values a template may interpolate, from what is actually stored.
 *
 * Every one is null when it is not known, and null is what makes the render
 * abort. `category` is the ICP label rather than the source's raw trade string,
 * because "hair_care" in a WhatsApp message is worse than no message.
 */
export function templateValues(input: {
  company: CompanyRecord;
  contact: PersonRecord | null;
}): Record<TemplateVariable, string | null> {
  const icp = findIcpIndustry(input.company.industry);
  const clean = (value: string | null): string | null => {
    if (value === null) return null;
    const trimmed = value.replace(/\s+/g, ' ').trim();
    return trimmed === '' ? null : trimmed;
  };

  return {
    business_name: clean(input.company.name),
    city: clean(input.company.city),
    category: clean(icp?.label ?? null),
    contact_first_name: clean(input.contact?.first_name ?? null),
  };
}

/**
 * One pass, or nothing.
 *
 * Collects every missing variable before throwing rather than failing on the
 * first, so the console can say "falta a cidade e a categoria" instead of
 * making an operator discover them one at a time.
 */
export function renderTemplate(
  text: string,
  values: Record<TemplateVariable, string | null>,
): string {
  const missing: string[] = [];

  const rendered = text.replace(PLACEHOLDER, (match, name: string) => {
    if (!isTemplateVariable(name)) {
      missing.push(name);
      return match;
    }
    const value = values[name];
    if (value === null) {
      missing.push(name);
      return match;
    }
    return value;
  });

  if (missing.length > 0) {
    throw new TemplateError('MISSING_VARIABLE', [...new Set(missing)].join(', '));
  }
  return rendered;
}

/**
 * A draft, or a refusal.
 *
 * The status check is first and unconditional, exactly as it was on the model
 * path: a lead that is `DO_NOT_CONTACT` or `OPTED_OUT` produces no draft. That
 * the render is now free changes nothing about it — the rule was never about
 * cost.
 */
export class TemplateOutreachService {
  private readonly templates: readonly OutreachTemplate[];

  constructor(templates: readonly OutreachTemplate[] = DEFAULT_TEMPLATES) {
    this.templates = templates;
  }

  generate(request: TemplateRequest): TemplateDraft {
    if (blocksOutreach(request.status)) {
      throw new OutreachBlockedError(request.status);
    }

    const templates = request.templates ?? this.templates;
    const pinned =
      request.templateId === undefined || request.templateId === null
        ? null
        : (templates.find((entry) => entry.id === request.templateId) ?? null);

    if (request.templateId !== undefined && request.templateId !== null && pinned === null) {
      throw new TemplateError('NO_TEMPLATE', request.templateId);
    }

    const template =
      pinned ??
      selectTemplate({
        channel: request.channel,
        businessType: request.company.industry,
        templates,
      });

    if (template === null) {
      throw new TemplateError('NO_TEMPLATE', request.channel);
    }

    // A template that would not pass the save-time check must not be used
    // either. Templates come from a settings document, which means they can
    // reach here without having gone through the console.
    const problems = validateTemplate(template);
    if (problems.length > 0) {
      throw new TemplateError(
        'INVALID_TEMPLATE',
        problems.map((problem) => `${problem.code}(${problem.detail})`).join(', '),
      );
    }

    const values = templateValues(request);
    const subject =
      template.subject === null ? null : renderTemplate(template.subject, values);
    const rendered = renderTemplate(template.body, values);

    const limit = OUTREACH_MAX_CHARS[request.channel];
    const truncated = rendered.length > limit;

    return {
      channel: request.channel,
      locale: request.locale ?? DEFAULT_OUTREACH_LOCALE,
      subject,
      body: truncated ? `${rendered.slice(0, limit - 1).trimEnd()}…` : rendered,
      templateId: template.id,
      addressedTo: values.contact_first_name ?? values.business_name,
      truncated,
    };
  }
}
