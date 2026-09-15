"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const survey_link_js_1 = require("./survey_link.js");
const SECRET = 'a-secret-that-only-the-server-knows';
const NOW = 1788307006310;
function token(overrides = {}) {
    return (0, survey_link_js_1.createSurveyLinkToken)({
        merchantId: 'merchant-1',
        surveyId: '9c858901-8a57-4791-81fe-4c455b099bc9',
        issuedAt: NOW,
        expiresAt: NOW + survey_link_js_1.SURVEY_LINK_TTL_MS,
        secret: SECRET,
        ...overrides,
    });
}
(0, node_test_1.default)('a link sent to one customer answers for that customer', () => {
    const verified = (0, survey_link_js_1.verifySurveyLinkToken)({
        token: token({ customerId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479' }),
        secret: SECRET,
        now: NOW + 1000,
    });
    strict_1.default.equal(verified?.merchantId, 'merchant-1');
    strict_1.default.equal(verified?.surveyId, '9c858901-8a57-4791-81fe-4c455b099bc9');
    strict_1.default.equal(verified?.customerId, 'f47ac10b-58cc-4372-a567-0e02b2c3d479');
});
(0, node_test_1.default)('a link with no customer is anonymous, not invalid', () => {
    // The poster-on-the-wall case. "Enviados ou preenchidos no local" means both
    // shapes are legitimate, and the difference lives in the token.
    const verified = (0, survey_link_js_1.verifySurveyLinkToken)({
        token: token(),
        secret: SECRET,
        now: NOW + 1000,
    });
    strict_1.default.equal(verified?.customerId, null);
    strict_1.default.equal(verified?.surveyId, '9c858901-8a57-4791-81fe-4c455b099bc9');
});
(0, node_test_1.default)('the business is carried in the token, so a verified link needs no scoping', () => {
    // Without this the route would take the merchant id from somewhere the
    // caller controls, which on an unauthenticated endpoint is every caller.
    const verified = (0, survey_link_js_1.verifySurveyLinkToken)({
        token: token({ merchantId: 'merchant-2' }),
        secret: SECRET,
        now: NOW + 1000,
    });
    strict_1.default.equal(verified?.merchantId, 'merchant-2');
});
(0, node_test_1.default)('another secret does not open the link', () => {
    strict_1.default.equal((0, survey_link_js_1.verifySurveyLinkToken)({
        token: token(),
        secret: 'not-the-secret',
        now: NOW + 1000,
    }), null);
});
(0, node_test_1.default)('rotating the secret revokes every link already sent', () => {
    const sent = [token(), token({ customerId: 'c1' }), token({ surveyId: 'survey-2' })];
    for (const one of sent) {
        strict_1.default.equal((0, survey_link_js_1.verifySurveyLinkToken)({ token: one, secret: 'rotated', now: NOW + 1 }), null);
    }
});
(0, node_test_1.default)('an edited payload fails even when the edit is plausible', () => {
    // Swapping the survey id for another of the same shape is the attack this
    // signature exists to stop: without it, one valid link opens every survey.
    const original = token();
    const [prefix, payload, signature] = original.split('.');
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    decoded.s = 'survey-somebody-elses';
    const edited = Buffer.from(JSON.stringify(decoded), 'utf8').toString('base64url');
    strict_1.default.equal((0, survey_link_js_1.verifySurveyLinkToken)({
        token: `${prefix}.${edited}.${signature}`,
        secret: SECRET,
        now: NOW + 1000,
    }), null);
});
(0, node_test_1.default)('an expired link is refused', () => {
    strict_1.default.equal((0, survey_link_js_1.verifySurveyLinkToken)({
        token: token(),
        secret: SECRET,
        now: NOW + survey_link_js_1.SURVEY_LINK_TTL_MS + 1,
    }), null);
});
(0, node_test_1.default)('a link is refused at the exact moment it expires', () => {
    strict_1.default.equal((0, survey_link_js_1.verifySurveyLinkToken)({
        token: token(),
        secret: SECRET,
        now: NOW + survey_link_js_1.SURVEY_LINK_TTL_MS,
    }), null);
    strict_1.default.ok((0, survey_link_js_1.verifySurveyLinkToken)({
        token: token(),
        secret: SECRET,
        now: NOW + survey_link_js_1.SURVEY_LINK_TTL_MS - 1,
    }));
});
(0, node_test_1.default)('a link from the future is refused', () => {
    strict_1.default.equal((0, survey_link_js_1.verifySurveyLinkToken)({ token: token(), secret: SECRET, now: NOW - 1 }), null);
});
(0, node_test_1.default)('malformed tokens are refused rather than thrown on', () => {
    const junk = [
        '',
        'sl1',
        'sl1.',
        'sl1..',
        'sl1.not-base64url!.sig',
        'cq1.abc.def',
        token().replace('sl1', 'sl2'),
        token().slice(0, -3),
    ];
    for (const one of junk) {
        strict_1.default.equal((0, survey_link_js_1.verifySurveyLinkToken)({ token: one, secret: SECRET, now: NOW + 1 }), null, `"${one}" was accepted`);
    }
});
(0, node_test_1.default)('a payload that is valid JSON but not ours is refused', () => {
    // Signed with our secret — so this is the case where only the field checks
    // stand between a caller and a survey read.
    const sneaky = Buffer.from(JSON.stringify({ v: 1, m: '', s: '../../etc', c: null, iat: NOW, exp: NOW + 1000 }), 'utf8').toString('base64url');
    const signed = (0, survey_link_js_1.createSurveyLinkToken)({
        merchantId: 'merchant-1',
        surveyId: 'survey-1',
        issuedAt: NOW,
        expiresAt: NOW + 1000,
        secret: SECRET,
    });
    const signature = signed.split('.')[2];
    strict_1.default.equal((0, survey_link_js_1.verifySurveyLinkToken)({
        token: `sl1.${sneaky}.${signature}`,
        secret: SECRET,
        now: NOW + 1,
    }), null);
});
