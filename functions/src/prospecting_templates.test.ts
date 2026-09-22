import assert from 'node:assert/strict';
import test from 'node:test';

import { OUTREACH_MAX_CHARS } from './prospecting_config.js';
import {
  DEFAULT_TEMPLATES,
  OutreachBlockedError,
  renderTemplate,
  selectTemplate,
  TemplateError,
  TemplateOutreachService,
  templateValues,
  validateTemplate,
  variablesUsed,
  worstCaseLength,
  type OutreachTemplate,
} from './prospecting_templates.js';
import type { CompanyRecord, PersonRecord } from './prospecting_providers.js';

function company(overrides: Partial<CompanyRecord> = {}): CompanyRecord {
  return {
    name: 'Barbearia Exemplo',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'barbershop',
    latitude: null,
    longitude: null,
    industry_raw: 'barber_shop',
    employee_count: null,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: null,
    phone: '+258840000101',
    email: null,
    linkedin_url: null,
    instagram_url: null,
    facebook_url: null,
    whatsapp: null,
    rating: 4.6,
    review_count: 87,
    has_opening_hours: true,
    has_photos: true,
    business_status: 'OPERATIONAL',
    source: 'places',
    source_reference: 'places/x',
    provider_org_id: 'places/x',
    ...overrides,
  };
}

function person(overrides: Partial<PersonRecord> = {}): PersonRecord {
  return {
    first_name: 'Arlindo',
    last_name: null,
    job_title: 'Proprietário',
    seniority: 'OWNER',
    email: null,
    email_status: 'UNKNOWN',
    phone: null,
    linkedin_url: null,
    provider_person_id: null,
    confidence_score: null,
    ...overrides,
  };
}

const service = new TemplateOutreachService();

/* ------------------------------------------------------------- variables */

test('placeholders are found whatever spacing an operator types', () => {
  assert.deepEqual(variablesUsed('{{business_name}} e {{ city }}').sort(), [
    'business_name',
    'city',
  ]);
});

test('the worst case prices each placeholder at its maximum length', () => {
  // Not a sample: a template that passes this cannot be cut for any business
  // whose name fits the stated maximum.
  assert.equal(worstCaseLength('ola {{business_name}}'), 4 + 60);
  assert.equal(worstCaseLength('sem variaveis'), 13);
});

/* ------------------------------------------------------------- validation */

test('every default template is valid', () => {
  for (const template of DEFAULT_TEMPLATES) {
    assert.deepEqual(
      validateTemplate(template),
      [],
      `${template.id} should be valid`,
    );
  }
});

test('a template using an unknown variable is refused at save time', () => {
  // A typo becomes a refusal while the operator is editing, rather than a
  // literal `{{bussiness_name}}` in a message to a stranger.
  const problems = validateTemplate({
    id: 'x',
    channel: 'WHATSAPP',
    businessType: null,
    subject: null,
    body: 'Olá {{bussiness_name}}',
  });
  assert.equal(problems.length, 1);
  assert.equal(problems[0]!.code, 'UNKNOWN_VARIABLE');
  assert.equal(problems[0]!.detail, 'bussiness_name');
});

test('a template that could exceed the channel limit is refused', () => {
  const problems = validateTemplate({
    id: 'x',
    channel: 'SMS',
    businessType: null,
    subject: null,
    body: 'x'.repeat(OUTREACH_MAX_CHARS.SMS + 1),
  });
  assert.ok(problems.some((problem) => problem.code === 'TOO_LONG'));
});

test('the limit is checked against the worst case, not the template source', () => {
  // Short enough as written, too long once a sixty-character business name
  // lands in it. This is the case a naive `body.length` check would pass.
  const body = `${'x'.repeat(OUTREACH_MAX_CHARS.SMS - 20)}{{business_name}}`;
  assert.ok(body.length < OUTREACH_MAX_CHARS.SMS);

  const problems = validateTemplate({
    id: 'x',
    channel: 'SMS',
    businessType: null,
    subject: null,
    body,
  });
  assert.ok(problems.some((problem) => problem.code === 'TOO_LONG'));
});

test('email needs a subject and the other channels must not have one', () => {
  assert.ok(
    validateTemplate({
      id: 'x',
      channel: 'EMAIL',
      businessType: null,
      subject: '  ',
      body: 'Bom dia',
    }).some((problem) => problem.code === 'SUBJECT_REQUIRED'),
  );

  assert.ok(
    validateTemplate({
      id: 'x',
      channel: 'WHATSAPP',
      businessType: null,
      subject: 'Assunto',
      body: 'Bom dia',
    }).some((problem) => problem.code === 'SUBJECT_NOT_ALLOWED'),
  );
});

test('validation reports every problem, not just the first', () => {
  const problems = validateTemplate({
    id: 'x',
    channel: 'EMAIL',
    businessType: null,
    subject: null,
    body: '{{nope}}'.concat('x'.repeat(OUTREACH_MAX_CHARS.EMAIL)),
  });
  const codes = problems.map((problem) => problem.code);
  assert.ok(codes.includes('UNKNOWN_VARIABLE'));
  assert.ok(codes.includes('TOO_LONG'));
  assert.ok(codes.includes('SUBJECT_REQUIRED'));
});

/* -------------------------------------------------------------- selection */

test('a trade-specific template beats the generic one', () => {
  const chosen = selectTemplate({
    channel: 'WHATSAPP',
    businessType: 'barbershop',
    templates: DEFAULT_TEMPLATES,
  });
  assert.equal(chosen?.id, 'barbershop-whatsapp-v1');
});

test('a trade with no template of its own falls back to the generic', () => {
  const chosen = selectTemplate({
    channel: 'WHATSAPP',
    businessType: 'car_wash',
    templates: DEFAULT_TEMPLATES,
  });
  assert.equal(chosen?.id, 'generic-whatsapp-v1');
});

test('no template for the channel is null, never another channel', () => {
  // Sending a WhatsApp message because no SMS template existed would be a
  // channel nobody chose.
  assert.equal(
    selectTemplate({
      channel: 'SMS',
      businessType: 'barbershop',
      templates: DEFAULT_TEMPLATES,
    }),
    null,
  );
});

/* -------------------------------------------------------------- rendering */

test('a missing variable aborts the render rather than leaving a gap', () => {
  // The whole rule of this module: "Olá 👋, encontrei o vosso espaço" with the
  // name missing is worse than no message.
  assert.throws(
    () =>
      renderTemplate('Olá {{business_name}} de {{city}}', {
        business_name: 'Barbearia X',
        city: null,
        category: null,
        contact_first_name: null,
      }),
    (error: unknown) =>
      error instanceof TemplateError && error.code === 'MISSING_VARIABLE',
  );
});

test('every missing variable is named at once', () => {
  try {
    renderTemplate('{{city}} {{category}}', {
      business_name: 'X',
      city: null,
      category: null,
      contact_first_name: null,
    });
    assert.fail('should have thrown');
  } catch (error) {
    assert.ok(error instanceof TemplateError);
    assert.ok(error.detail.includes('city'));
    assert.ok(error.detail.includes('category'));
  }
});

test('the category is the human label, never the source taxonomy string', () => {
  // "hair_care" in a WhatsApp message is worse than no message.
  const values = templateValues({ company: company({ industry: 'salon' }), contact: null });
  assert.equal(values.category, 'Salão de beleza');
});

test('an unmapped trade has no category, which aborts a template that needs one', () => {
  const values = templateValues({
    company: company({ industry: null, industry_raw: 'bank' }),
    contact: null,
  });
  assert.equal(values.category, null);
});

test('whitespace-only values count as missing, not as empty strings', () => {
  const values = templateValues({ company: company({ city: '   ' }), contact: null });
  assert.equal(values.city, null);
});

/* ---------------------------------------------------------------- service */

test('a barbershop in Maputo gets the barbershop template, filled', () => {
  const draft = service.generate({
    channel: 'WHATSAPP',
    company: company(),
    contact: null,
    status: 'READY_TO_CONTACT',
  });

  assert.equal(draft.templateId, 'barbershop-whatsapp-v1');
  assert.ok(draft.body.includes('Barbearia Exemplo'));
  assert.ok(draft.body.includes('Maputo'));
  assert.equal(draft.subject, null);
  assert.equal(draft.truncated, false);
  assert.ok(draft.body.length <= OUTREACH_MAX_CHARS.WHATSAPP);
});

test('DO_NOT_CONTACT and OPTED_OUT produce no draft, free or not', () => {
  // The rule was never about cost, so a free render does not relax it.
  for (const status of ['DO_NOT_CONTACT', 'OPTED_OUT'] as const) {
    assert.throws(
      () =>
        service.generate({
          channel: 'WHATSAPP',
          company: company(),
          contact: null,
          status,
        }),
      (error: unknown) => error instanceof OutreachBlockedError,
    );
  }
});

test('a lead with no city cannot be written to, and says so', () => {
  assert.throws(
    () =>
      service.generate({
        channel: 'WHATSAPP',
        company: company({ city: null }),
        contact: null,
        status: 'READY_TO_CONTACT',
      }),
    (error: unknown) =>
      error instanceof TemplateError && error.code === 'MISSING_VARIABLE',
  );
});

test('a pinned template is used, and an unknown id is refused', () => {
  const draft = service.generate({
    channel: 'WHATSAPP',
    company: company(),
    contact: null,
    status: 'READY_TO_CONTACT',
    templateId: 'generic-whatsapp-v1',
  });
  assert.equal(draft.templateId, 'generic-whatsapp-v1');

  // Silently serving v1 to somebody who asked for v2 would attribute v1's
  // reply to v2 — the one thing the A/B exists to get right.
  assert.throws(
    () =>
      service.generate({
        channel: 'WHATSAPP',
        company: company(),
        contact: null,
        status: 'READY_TO_CONTACT',
        templateId: 'barbershop-whatsapp-v9',
      }),
    (error: unknown) => error instanceof TemplateError && error.code === 'NO_TEMPLATE',
  );
});

test('a channel with no template is refused rather than switched', () => {
  assert.throws(
    () =>
      service.generate({
        channel: 'LINKEDIN',
        company: company(),
        contact: null,
        status: 'READY_TO_CONTACT',
      }),
    (error: unknown) => error instanceof TemplateError && error.code === 'NO_TEMPLATE',
  );
});

test('an invalid stored template is refused at render, not just at save', () => {
  // Templates live in a settings document, so they can reach the renderer
  // without ever having passed through the console.
  const bad: OutreachTemplate = {
    id: 'broken-whatsapp-v1',
    channel: 'WHATSAPP',
    businessType: null,
    subject: null,
    body: 'Olá {{nope}}',
  };

  assert.throws(
    () =>
      new TemplateOutreachService([bad]).generate({
        channel: 'WHATSAPP',
        company: company(),
        contact: null,
        status: 'READY_TO_CONTACT',
      }),
    (error: unknown) =>
      error instanceof TemplateError && error.code === 'INVALID_TEMPLATE',
  );
});

test('the email template carries a filled subject', () => {
  const draft = service.generate({
    channel: 'EMAIL',
    company: company({ industry: 'cafe', name: 'Café Exemplo' }),
    contact: null,
    status: 'READY_TO_CONTACT',
  });

  assert.equal(draft.templateId, 'generic-email-v1');
  assert.ok(draft.subject !== null && draft.subject.includes('Maputo'));
  assert.ok(draft.body.includes('Café e pastelaria'));
});

test('a known contact name is what the draft is addressed to', () => {
  const draft = service.generate({
    channel: 'WHATSAPP',
    company: company(),
    contact: person(),
    status: 'READY_TO_CONTACT',
  });
  assert.equal(draft.addressedTo, 'Arlindo');
});

test('with no contact, the draft is addressed to the business, never invented', () => {
  const draft = service.generate({
    channel: 'WHATSAPP',
    company: company(),
    contact: null,
    status: 'READY_TO_CONTACT',
  });
  assert.equal(draft.addressedTo, 'Barbearia Exemplo');
});

test('no default template addresses a person by name', () => {
  // Discovery reads a shop listing, and a shop listing carries no owner name.
  // A default that assumed one would abort on every lead the pipeline can
  // currently produce.
  for (const template of DEFAULT_TEMPLATES) {
    assert.ok(
      !variablesUsed(template.body).includes('contact_first_name'),
      `${template.id} must not require a contact name`,
    );
  }
});

test('the backstop cut fires and reports itself', () => {
  // Should be unreachable after validation; it exists for data longer than
  // the assumed worst case, and it never cuts silently.
  const long: OutreachTemplate = {
    id: 'long-sms-v1',
    channel: 'SMS',
    businessType: null,
    subject: null,
    body: '{{business_name}}',
  };
  const draft = new TemplateOutreachService([long]).generate({
    channel: 'SMS',
    company: company({ name: 'N'.repeat(OUTREACH_MAX_CHARS.SMS + 50) }),
    contact: null,
    status: 'READY_TO_CONTACT',
  });

  assert.equal(draft.truncated, true);
  assert.equal(draft.body.length, OUTREACH_MAX_CHARS.SMS);
});
