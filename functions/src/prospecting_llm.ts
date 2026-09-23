import Anthropic from '@anthropic-ai/sdk';

import type { LlmPort } from './prospecting_analysis.js';

/**
 * The model, behind the port.
 *
 * `LeadAnalysisService` and `OutreachService` know only `complete(system, user)
 * -> string`. Everything that makes this a particular model — the SDK, the
 * key, the effort setting, the error taxonomy — is here, which is why the
 * whole analysis layer is testable with a three-line stub and why swapping the
 * model is a change to this file alone.
 *
 * Two choices worth stating.
 *
 * **Effort is `low`.** Reading a business's public data and writing four
 * paragraphs about it is not a reasoning-heavy task, and this module is one
 * whose whole point is not spending silently. Effort is the first lever that
 * trades quality for cost, and the low end is where a task like this belongs;
 * raising it is a deliberate change with a measurable bill attached.
 *
 * **The reply is parsed by `parseAnalysis`, not trusted.** The prompt asks for
 * JSON and the validator treats whatever comes back as untrusted input —
 * clamping scores, dropping unsourced claims, refusing a malformed body. That
 * is deliberate belt-and-braces: a structured-output constraint would remove
 * the malformed-JSON case but not the fabricated-evidence one, which is the
 * case that actually matters here.
 */

/** The model this module is written against. */
export const PROSPECTING_MODEL = 'claude-opus-5';

/** Bounded so one reply cannot run away with a month's budget. */
const MAX_OUTPUT_TOKENS = 2_000;

export type AnthropicLlmOptions = {
  apiKey: string | undefined;
  model?: string;
  /** Injected in tests; the SDK's own client otherwise. */
  client?: Pick<Anthropic['messages'], 'create'>;
};

export class AnthropicLlm implements LlmPort {
  readonly key = 'anthropic';
  readonly model: string;
  private readonly apiKey: string | undefined;
  private readonly injected: AnthropicLlmOptions['client'];
  private cached: Anthropic | null = null;

  constructor(options: AnthropicLlmOptions) {
    this.apiKey = options.apiKey;
    this.model = options.model ?? PROSPECTING_MODEL;
    this.injected = options.client;
  }

  isConfigured(): boolean {
    return (
      this.injected !== undefined ||
      (typeof this.apiKey === 'string' && this.apiKey.trim() !== '')
    );
  }

  private messages(): Pick<Anthropic['messages'], 'create'> {
    if (this.injected !== undefined) return this.injected;
    if (this.cached === null) {
      this.cached = new Anthropic({ apiKey: this.apiKey });
    }
    return this.cached.messages;
  }

  /**
   * One completion, as text.
   *
   * Errors are rethrown with the SDK's own message rather than wrapped here:
   * `LeadAnalysisService` turns anything thrown into an `AnalysisError`, and
   * the route turns that into one of three explanations. Adding a fourth layer
   * of translation here would only make the log harder to read.
   *
   * The response is assembled from the text blocks and nothing else. A
   * `thinking` block is not an answer, and concatenating one into the reply
   * would feed the validator prose that was never meant to be JSON.
   */
  async complete(input: {
    system: string;
    user: string;
    maxOutputTokens: number;
  }): Promise<string> {
    const response = await this.messages().create({
      model: this.model,
      max_tokens: Math.min(MAX_OUTPUT_TOKENS, Math.max(256, input.maxOutputTokens)),
      system: input.system,
      output_config: { effort: 'low' },
      messages: [{ role: 'user', content: input.user }],
    });

    // A policy refusal is not a malformed reply, and it must not be retried as
    // one. It reaches the caller as an empty body, which the validator refuses
    // with `INVALID_SCHEMA` and the route explains as "could not be read" —
    // which is what it is, from the operator's side.
    if (response.stop_reason === 'refusal') return '';

    return response.content
      .filter((block): block is Anthropic.TextBlock => block.type === 'text')
      .map((block) => block.text)
      .join('\n')
      .trim();
  }
}

/**
 * A model that refuses, for an installation with no key.
 *
 * The same shape as `NotConfiguredProvider`: the surfaces stay mounted, the
 * routes answer "nenhum modelo configurado" rather than 500, and the portal
 * can say what is missing instead of looking broken.
 */
export class NotConfiguredLlm implements LlmPort {
  readonly key = 'none';
  readonly model = 'none';

  isConfigured(): boolean {
    return false;
  }

  async complete(): Promise<string> {
    throw new Error('no model configured');
  }
}

/** The model for this process, or the refusing stand-in. */
export function resolveLlm(environment: Record<string, string | undefined>): LlmPort {
  const apiKey = environment.ANTHROPIC_API_KEY;
  if (typeof apiKey !== 'string' || apiKey.trim() === '') return new NotConfiguredLlm();
  return new AnthropicLlm({
    apiKey,
    model: environment.PROSPECTING_MODEL?.trim() || PROSPECTING_MODEL,
  });
}
