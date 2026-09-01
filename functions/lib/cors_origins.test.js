"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const cors_origins_js_1 = require("./cors_origins.js");
(0, node_test_1.default)('defaults to the known production origins', () => {
    const origins = (0, cors_origins_js_1.allowedOrigins)({}, false);
    strict_1.default.deepEqual(origins, [...cors_origins_js_1.DEFAULT_ALLOWED_ORIGINS]);
    strict_1.default.ok(origins.includes(cors_origins_js_1.PRIMARY_SITE_ORIGIN));
});
(0, node_test_1.default)('localhost is never allowed off the emulator', () => {
    // The whole point of the lockdown. localhost is an origin an attacker can
    // serve from the victim's own machine, so it must not survive into a deploy.
    const deployed = (0, cors_origins_js_1.allowedOrigins)({}, false);
    strict_1.default.equal(deployed.some((origin) => origin instanceof RegExp), false);
    const local = (0, cors_origins_js_1.allowedOrigins)({}, true);
    strict_1.default.ok(local.some((origin) => origin instanceof RegExp));
});
(0, node_test_1.default)('the local pattern matches dev servers and nothing that merely looks like one', () => {
    for (const origin of [
        'http://localhost',
        'http://localhost:3200',
        'http://127.0.0.1:5099',
    ]) {
        strict_1.default.ok(cors_origins_js_1.LOCAL_ORIGIN_PATTERN.test(origin), origin);
    }
    for (const origin of [
        'http://localhost.evil.com',
        'https://localhost.attacker.io',
        'http://127.0.0.1.evil.com',
        'http://notlocalhost',
    ]) {
        strict_1.default.equal(cors_origins_js_1.LOCAL_ORIGIN_PATTERN.test(origin), false, origin);
    }
});
(0, node_test_1.default)('configuration replaces the defaults instead of adding to them', () => {
    // Adding would leave a deployment on another hostname still trusting this
    // one, which is the opposite of what configuring it is for.
    const origins = (0, cors_origins_js_1.allowedOrigins)({ CORS_ALLOWED_ORIGINS: 'https://outro.example' }, false);
    strict_1.default.deepEqual(origins, ['https://outro.example']);
    strict_1.default.equal(origins.includes(cors_origins_js_1.PRIMARY_SITE_ORIGIN), false);
});
(0, node_test_1.default)('configuration accepts a list and normalizes it', () => {
    const origins = (0, cors_origins_js_1.allowedOrigins)({
        CORS_ALLOWED_ORIGINS: ' https://a.example/ , https://b.example ,, https://c.example//  ',
    }, false);
    strict_1.default.deepEqual(origins, [
        'https://a.example',
        'https://b.example',
        'https://c.example',
    ]);
});
(0, node_test_1.default)('a blank or malformed setting falls back to the defaults rather than to nothing', () => {
    // An empty allowlist would reject every browser request, which reads as an
    // outage rather than as a configuration mistake.
    for (const raw of ['', '   ', ',,,', undefined]) {
        strict_1.default.deepEqual((0, cors_origins_js_1.allowedOrigins)({ CORS_ALLOWED_ORIGINS: raw }, false), [...cors_origins_js_1.DEFAULT_ALLOWED_ORIGINS], JSON.stringify(raw));
    }
});
(0, node_test_1.default)('emulator detection covers both signals the suite sets', () => {
    strict_1.default.equal((0, cors_origins_js_1.runningInEmulator)({}), false);
    strict_1.default.equal((0, cors_origins_js_1.runningInEmulator)({ FUNCTIONS_EMULATOR: 'true' }), true);
    strict_1.default.equal((0, cors_origins_js_1.runningInEmulator)({ FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' }), true);
    strict_1.default.equal((0, cors_origins_js_1.runningInEmulator)({ FUNCTIONS_EMULATOR: 'false' }), false);
});
