"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_templates_js_1 = require("./prospecting_templates.js");
function company(overrides = {}) {
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
function person(overrides = {}) {
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
const service = new prospecting_templates_js_1.TemplateOutreachService();
/* ------------------------------------------------------------- variables */
(0, node_test_1.default)('placeholders are found whatever spacing an operator types', () => {
    strict_1.default.deepEqual((0, prospecting_templates_js_1.variablesUsed)('{{business_name}} e {{ city }}').sort(), [
        'business_name',
        'city',
    ]);
});
(0, node_test_1.default)('the worst case prices each placeholder at its maximum length', () => {
    // Not a sample: a template that passes this cannot be cut for any business
    // whose name fits the stated maximum.
    strict_1.default.equal((0, prospecting_templates_js_1.worstCaseLength)('ola {{business_name}}'), 4 + 60);
    strict_1.default.equal((0, prospecting_templates_js_1.worstCaseLength)('sem variaveis'), 13);
});
/* ------------------------------------------------------------- validation */
(0, node_test_1.default)('every default template is valid', () => {
    for (const template of prospecting_templates_js_1.DEFAULT_TEMPLATES) {
        strict_1.default.deepEqual((0, prospecting_templates_js_1.validateTemplate)(template), [], `${template.id} should be valid`);
    }
});
(0, node_test_1.default)('a template using an unknown variable is refused at save time', () => {
    // A typo becomes a refusal while the operator is editing, rather than a
    // literal `{{bussiness_name}}` in a message to a stranger.
    const problems = (0, prospecting_templates_js_1.validateTemplate)({
        id: 'x',
        channel: 'WHATSAPP',
        businessType: null,
        subject: null,
        body: 'Olá {{bussiness_name}}',
    });
    strict_1.default.equal(problems.length, 1);
    strict_1.default.equal(problems[0].code, 'UNKNOWN_VARIABLE');
    strict_1.default.equal(problems[0].detail, 'bussiness_name');
});
(0, node_test_1.default)('a template that could exceed the channel limit is refused', () => {
    const problems = (0, prospecting_templates_js_1.validateTemplate)({
        id: 'x',
        channel: 'SMS',
        businessType: null,
        subject: null,
        body: 'x'.repeat(prospecting_config_js_1.OUTREACH_MAX_CHARS.SMS + 1),
    });
    strict_1.default.ok(problems.some((problem) => problem.code === 'TOO_LONG'));
});
(0, node_test_1.default)('the limit is checked against the worst case, not the template source', () => {
    // Short enough as written, too long once a sixty-character business name
    // lands in it. This is the case a naive `body.length` check would pass.
    const body = `${'x'.repeat(prospecting_config_js_1.OUTREACH_MAX_CHARS.SMS - 20)}{{business_name}}`;
    strict_1.default.ok(body.length < prospecting_config_js_1.OUTREACH_MAX_CHARS.SMS);
    const problems = (0, prospecting_templates_js_1.validateTemplate)({
        id: 'x',
        channel: 'SMS',
        businessType: null,
        subject: null,
        body,
    });
    strict_1.default.ok(problems.some((problem) => problem.code === 'TOO_LONG'));
});
(0, node_test_1.default)('email needs a subject and the other channels must not have one', () => {
    strict_1.default.ok((0, prospecting_templates_js_1.validateTemplate)({
        id: 'x',
        channel: 'EMAIL',
        businessType: null,
        subject: '  ',
        body: 'Bom dia',
    }).some((problem) => problem.code === 'SUBJECT_REQUIRED'));
    strict_1.default.ok((0, prospecting_templates_js_1.validateTemplate)({
        id: 'x',
        channel: 'WHATSAPP',
        businessType: null,
        subject: 'Assunto',
        body: 'Bom dia',
    }).some((problem) => problem.code === 'SUBJECT_NOT_ALLOWED'));
});
(0, node_test_1.default)('validation reports every problem, not just the first', () => {
    const problems = (0, prospecting_templates_js_1.validateTemplate)({
        id: 'x',
        channel: 'EMAIL',
        businessType: null,
        subject: null,
        body: '{{nope}}'.concat('x'.repeat(prospecting_config_js_1.OUTREACH_MAX_CHARS.EMAIL)),
    });
    const codes = problems.map((problem) => problem.code);
    strict_1.default.ok(codes.includes('UNKNOWN_VARIABLE'));
    strict_1.default.ok(codes.includes('TOO_LONG'));
    strict_1.default.ok(codes.includes('SUBJECT_REQUIRED'));
});
/* -------------------------------------------------------------- selection */
(0, node_test_1.default)('a trade-specific template beats the generic one', () => {
    const chosen = (0, prospecting_templates_js_1.selectTemplate)({
        channel: 'WHATSAPP',
        businessType: 'barbershop',
        templates: prospecting_templates_js_1.DEFAULT_TEMPLATES,
    });
    strict_1.default.equal(chosen?.id, 'barbershop-whatsapp-v1');
});
(0, node_test_1.default)('a trade with no template of its own falls back to the generic', () => {
    const chosen = (0, prospecting_templates_js_1.selectTemplate)({
        channel: 'WHATSAPP',
        businessType: 'car_wash',
        templates: prospecting_templates_js_1.DEFAULT_TEMPLATES,
    });
    strict_1.default.equal(chosen?.id, 'generic-whatsapp-v1');
});
(0, node_test_1.default)('no template for the channel is null, never another channel', () => {
    // Sending a WhatsApp message because no SMS template existed would be a
    // channel nobody chose.
    strict_1.default.equal((0, prospecting_templates_js_1.selectTemplate)({
        channel: 'SMS',
        businessType: 'barbershop',
        templates: prospecting_templates_js_1.DEFAULT_TEMPLATES,
    }), null);
});
/* -------------------------------------------------------------- rendering */
(0, node_test_1.default)('a missing variable aborts the render rather than leaving a gap', () => {
    // The whole rule of this module: "Olá 👋, encontrei o vosso espaço" with the
    // name missing is worse than no message.
    strict_1.default.throws(() => (0, prospecting_templates_js_1.renderTemplate)('Olá {{business_name}} de {{city}}', {
        business_name: 'Barbearia X',
        city: null,
        category: null,
        contact_first_name: null,
    }), (error) => error instanceof prospecting_templates_js_1.TemplateError && error.code === 'MISSING_VARIABLE');
});
(0, node_test_1.default)('every missing variable is named at once', () => {
    try {
        (0, prospecting_templates_js_1.renderTemplate)('{{city}} {{category}}', {
            business_name: 'X',
            city: null,
            category: null,
            contact_first_name: null,
        });
        strict_1.default.fail('should have thrown');
    }
    catch (error) {
        strict_1.default.ok(error instanceof prospecting_templates_js_1.TemplateError);
        strict_1.default.ok(error.detail.includes('city'));
        strict_1.default.ok(error.detail.includes('category'));
    }
});
(0, node_test_1.default)('the category is the human label, never the source taxonomy string', () => {
    // "hair_care" in a WhatsApp message is worse than no message.
    const values = (0, prospecting_templates_js_1.templateValues)({ company: company({ industry: 'salon' }), contact: null });
    strict_1.default.equal(values.category, 'Salão de beleza');
});
(0, node_test_1.default)('an unmapped trade has no category, which aborts a template that needs one', () => {
    const values = (0, prospecting_templates_js_1.templateValues)({
        company: company({ industry: null, industry_raw: 'bank' }),
        contact: null,
    });
    strict_1.default.equal(values.category, null);
});
(0, node_test_1.default)('whitespace-only values count as missing, not as empty strings', () => {
    const values = (0, prospecting_templates_js_1.templateValues)({ company: company({ city: '   ' }), contact: null });
    strict_1.default.equal(values.city, null);
});
/* ---------------------------------------------------------------- service */
(0, node_test_1.default)('a barbershop in Maputo gets the barbershop template, filled', () => {
    const draft = service.generate({
        channel: 'WHATSAPP',
        company: company(),
        contact: null,
        status: 'READY_TO_CONTACT',
    });
    strict_1.default.equal(draft.templateId, 'barbershop-whatsapp-v1');
    strict_1.default.ok(draft.body.includes('Barbearia Exemplo'));
    strict_1.default.ok(draft.body.includes('Maputo'));
    strict_1.default.equal(draft.subject, null);
    strict_1.default.equal(draft.truncated, false);
    strict_1.default.ok(draft.body.length <= prospecting_config_js_1.OUTREACH_MAX_CHARS.WHATSAPP);
});
(0, node_test_1.default)('DO_NOT_CONTACT and OPTED_OUT produce no draft, free or not', () => {
    // The rule was never about cost, so a free render does not relax it.
    for (const status of ['DO_NOT_CONTACT', 'OPTED_OUT']) {
        strict_1.default.throws(() => service.generate({
            channel: 'WHATSAPP',
            company: company(),
            contact: null,
            status,
        }), (error) => error instanceof prospecting_templates_js_1.OutreachBlockedError);
    }
});
(0, node_test_1.default)('a lead with no city cannot be written to, and says so', () => {
    strict_1.default.throws(() => service.generate({
        channel: 'WHATSAPP',
        company: company({ city: null }),
        contact: null,
        status: 'READY_TO_CONTACT',
    }), (error) => error instanceof prospecting_templates_js_1.TemplateError && error.code === 'MISSING_VARIABLE');
});
(0, node_test_1.default)('a pinned template is used, and an unknown id is refused', () => {
    const draft = service.generate({
        channel: 'WHATSAPP',
        company: company(),
        contact: null,
        status: 'READY_TO_CONTACT',
        templateId: 'generic-whatsapp-v1',
    });
    strict_1.default.equal(draft.templateId, 'generic-whatsapp-v1');
    // Silently serving v1 to somebody who asked for v2 would attribute v1's
    // reply to v2 — the one thing the A/B exists to get right.
    strict_1.default.throws(() => service.generate({
        channel: 'WHATSAPP',
        company: company(),
        contact: null,
        status: 'READY_TO_CONTACT',
        templateId: 'barbershop-whatsapp-v9',
    }), (error) => error instanceof prospecting_templates_js_1.TemplateError && error.code === 'NO_TEMPLATE');
});
(0, node_test_1.default)('a channel with no template is refused rather than switched', () => {
    strict_1.default.throws(() => service.generate({
        channel: 'LINKEDIN',
        company: company(),
        contact: null,
        status: 'READY_TO_CONTACT',
    }), (error) => error instanceof prospecting_templates_js_1.TemplateError && error.code === 'NO_TEMPLATE');
});
(0, node_test_1.default)('an invalid stored template is refused at render, not just at save', () => {
    // Templates live in a settings document, so they can reach the renderer
    // without ever having passed through the console.
    const bad = {
        id: 'broken-whatsapp-v1',
        channel: 'WHATSAPP',
        businessType: null,
        subject: null,
        body: 'Olá {{nope}}',
    };
    strict_1.default.throws(() => new prospecting_templates_js_1.TemplateOutreachService([bad]).generate({
        channel: 'WHATSAPP',
        company: company(),
        contact: null,
        status: 'READY_TO_CONTACT',
    }), (error) => error instanceof prospecting_templates_js_1.TemplateError && error.code === 'INVALID_TEMPLATE');
});
(0, node_test_1.default)('the email template carries a filled subject', () => {
    const draft = service.generate({
        channel: 'EMAIL',
        company: company({ industry: 'cafe', name: 'Café Exemplo' }),
        contact: null,
        status: 'READY_TO_CONTACT',
    });
    strict_1.default.equal(draft.templateId, 'generic-email-v1');
    strict_1.default.ok(draft.subject !== null && draft.subject.includes('Maputo'));
    strict_1.default.ok(draft.body.includes('Café e pastelaria'));
});
(0, node_test_1.default)('a known contact name is what the draft is addressed to', () => {
    const draft = service.generate({
        channel: 'WHATSAPP',
        company: company(),
        contact: person(),
        status: 'READY_TO_CONTACT',
    });
    strict_1.default.equal(draft.addressedTo, 'Arlindo');
});
(0, node_test_1.default)('with no contact, the draft is addressed to the business, never invented', () => {
    const draft = service.generate({
        channel: 'WHATSAPP',
        company: company(),
        contact: null,
        status: 'READY_TO_CONTACT',
    });
    strict_1.default.equal(draft.addressedTo, 'Barbearia Exemplo');
});
(0, node_test_1.default)('no default template addresses a person by name', () => {
    // Discovery reads a shop listing, and a shop listing carries no owner name.
    // A default that assumed one would abort on every lead the pipeline can
    // currently produce.
    for (const template of prospecting_templates_js_1.DEFAULT_TEMPLATES) {
        strict_1.default.ok(!(0, prospecting_templates_js_1.variablesUsed)(template.body).includes('contact_first_name'), `${template.id} must not require a contact name`);
    }
});
(0, node_test_1.default)('the backstop cut fires and reports itself', () => {
    // Should be unreachable after validation; it exists for data longer than
    // the assumed worst case, and it never cuts silently.
    const long = {
        id: 'long-sms-v1',
        channel: 'SMS',
        businessType: null,
        subject: null,
        body: '{{business_name}}',
    };
    const draft = new prospecting_templates_js_1.TemplateOutreachService([long]).generate({
        channel: 'SMS',
        company: company({ name: 'N'.repeat(prospecting_config_js_1.OUTREACH_MAX_CHARS.SMS + 50) }),
        contact: null,
        status: 'READY_TO_CONTACT',
    });
    strict_1.default.equal(draft.truncated, true);
    strict_1.default.equal(draft.body.length, prospecting_config_js_1.OUTREACH_MAX_CHARS.SMS);
});
