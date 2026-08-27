"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const node_test_1 = __importDefault(require("node:test"));
const recovery_task_creation_js_1 = require("./recovery_task_creation.js");
(0, node_test_1.default)('uses one atomic merchant/customer open slot and returns the existing task', async () => {
    const existing = {
        id: 'task-existing',
        merchant_id: 'merchant-1',
        customer_id: 'customer-1',
        status: 'open',
        creation_created: false,
    };
    const calls = [];
    const db = {
        async query(_sql, values) {
            calls.push(values);
            return { rows: [existing] };
        },
    };
    const result = await (0, recovery_task_creation_js_1.createOrGetOpenRecoveryTask)(db, {
        id: 'task-new',
        merchantId: 'merchant-1',
        customerId: 'customer-1',
        priority: 'high',
        dueAt: null,
        notes: null,
        actorAppUserId: 'user-1',
        now: 123,
    });
    strict_1.default.equal(result.outcome, 'already_open');
    strict_1.default.equal(result.task.id, 'task-existing');
    strict_1.default.equal('creation_created' in result.task, false);
    strict_1.default.deepEqual(calls[0]?.slice(1, 3), ['merchant-1', 'customer-1']);
    strict_1.default.match(recovery_task_creation_js_1.CREATE_OPEN_RECOVERY_TASK_SQL, /ON CONFLICT \(merchant_id, customer_id, open_slot\) DO UPDATE/);
});
(0, node_test_1.default)('reports a newly inserted open task as created', async () => {
    const db = {
        async query(_sql, values) {
            return {
                rows: [{
                        id: values[0],
                        status: 'open',
                        creation_created: true,
                    }],
            };
        },
    };
    const result = await (0, recovery_task_creation_js_1.createOrGetOpenRecoveryTask)(db, {
        id: 'task-new',
        merchantId: 'merchant-1',
        customerId: 'customer-1',
        priority: 'medium',
        dueAt: null,
        notes: null,
        actorAppUserId: null,
        now: 123,
    });
    strict_1.default.equal(result.outcome, 'created');
    strict_1.default.equal(result.task.id, 'task-new');
});
(0, node_test_1.default)('schema derives and uniquely indexes the open slot', () => {
    const schema = (0, node_fs_1.readFileSync)((0, node_path_1.resolve)(process.cwd(), 'sql/schema.sql'), 'utf8');
    strict_1.default.match(schema, /open_slot SMALLINT GENERATED ALWAYS AS \(\s*CASE WHEN LOWER\(status\) = 'open' THEN 1 ELSE NULL END\s*\) STORED/);
    strict_1.default.match(schema, /CREATE UNIQUE INDEX IF NOT EXISTS idx_recovery_tasks_one_open_customer\s+ON recovery_tasks\(merchant_id, customer_id, open_slot\)/);
});
(0, node_test_1.default)('queued task collision reconciles to the canonical remote task', async () => {
    const canonical = {
        id: 'task-canonical',
        merchant_id: 'merchant-1',
        customer_id: 'customer-1',
        status: 'open',
        created_at: 1000,
        updated_at: 2000,
        creation_created: false,
    };
    let values = [];
    const db = {
        async query(_sql, queryValues) {
            values = queryValues;
            return { rows: [canonical] };
        },
    };
    const result = await (0, recovery_task_creation_js_1.createOrGetOpenRecoveryTask)(db, {
        id: 'task-provisional',
        merchantId: 'merchant-1',
        customerId: 'customer-1',
        priority: 'low',
        dueAt: null,
        notes: 'queued offline',
        actorAppUserId: null,
        createdAt: 1500,
        now: 1600,
    });
    strict_1.default.equal(result.outcome, 'already_open');
    strict_1.default.equal(result.task.id, 'task-canonical');
    strict_1.default.equal(values[0], 'task-provisional');
    strict_1.default.equal(values[6], 1500);
});
