"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerAffiliateRoutes = registerAffiliateRoutes;
const admin_audit_js_1 = require("./admin_audit.js");
const affiliate_api_contracts_js_1 = require("./affiliate_api_contracts.js");
const affiliate_contracts_js_1 = require("./affiliate_contracts.js");
const affiliate_rate_limit_js_1 = require("./affiliate_rate_limit.js");
const affiliate_sale_firestore_js_1 = require("./affiliate_sale_firestore.js");
const affiliate_store_js_1 = require("./affiliate_store.js");
const affiliate_notifications_js_1 = require("./affiliate_notifications.js");
const MAX_PAGE = 200;
const DEFAULT_PAGE = 50;
/* ------------------------------------------------------------------ helpers */
function clock(deps) {
    return deps.now ? deps.now() : Date.now();
}
function queryString(value) {
    if (typeof value !== 'string')
        return undefined;
    const trimmed = value.trim();
    return trimmed === '' ? undefined : trimmed;
}
function pageQuery(req) {
    const rawLimit = Number(req.query.limit);
    const rawOffset = Number(req.query.offset);
    return {
        search: queryString(req.query.search),
        status: queryString(req.query.status),
        limit: Number.isFinite(rawLimit) && rawLimit > 0
            ? Math.min(Math.floor(rawLimit), MAX_PAGE)
            : DEFAULT_PAGE,
        offset: Number.isFinite(rawOffset) && rawOffset > 0 ? Math.floor(rawOffset) : 0,
        affiliateId: queryString(req.query.affiliate_id),
    };
}
function pageResponse(res, query, page) {
    return res.json({
        success: true,
        data: page.items,
        paging: { limit: query.limit, offset: query.offset, has_more: page.hasMore },
        total: page.total,
        truncated: page.truncated,
    });
}
/**
 * Translates a refusal, or hands an unexpected failure to the existing logger.
 *
 * An `AffiliateApiError` is something the caller did and is told about in
 * Portuguese with a stable code. Anything else is a bug, and the response says
 * only "Server error" while the cause goes to Cloud Logging — the same split
 * `respondAdminServerError` already makes.
 */
function respond(deps, res, operation, error) {
    if (error instanceof affiliate_api_contracts_js_1.AffiliateApiError) {
        return res
            .status(error.status)
            .json({ success: false, code: error.code, message: error.message });
    }
    return deps.respondServerError(res, operation, error);
}
/** Raises the one 403 every mutation shares. Read routes never call it. */
function requireOwnerOrAdmin(deps, req) {
    if (!deps.isOwnerOrAdminRequest(req))
        throw (0, affiliate_api_contracts_js_1.ownerOnlyError)();
}
function actorIdOf(req) {
    const appUserId = req.appUserId?.trim();
    if (appUserId)
        return appUserId;
    const uid = req.auth?.uid?.trim();
    return uid && uid !== '' ? uid : 'anonymous';
}
function notFound(code) {
    return (0, affiliate_api_contracts_js_1.affiliateApiError)(404, code);
}
/**
 * Derives the global identity, or says plainly that it cannot.
 *
 * The derivation needs the customer-core HMAC secret, and without it there is
 * no safe identity to write — a fallback id would create a second affiliate
 * for a phone that already has one. A bare throw would surface as "Server
 * error" with no clue; this names the cause with a stable code.
 */
function affiliateIdFor(deps, phoneE164) {
    try {
        return deps.affiliateIdForPhone(phoneE164);
    }
    catch {
        throw (0, affiliate_api_contracts_js_1.affiliateApiError)(500, 'identity_unavailable');
    }
}
/**
 * The code settings a create or a link carries.
 *
 * `benefit_type` and `benefit_value` are required: the plan fixes a default
 * validity, a default usage limit and a default eligibility, but it does not
 * fix what a code is worth, and guessing one would create a discount nobody
 * chose.
 */
function parseCodeDefaults(payload, now) {
    return {
        benefit: (0, affiliate_api_contracts_js_1.parseBenefit)(payload.benefit_type, payload.benefit_value),
        validity: (0, affiliate_api_contracts_js_1.parseValidity)(payload.starts_at, payload.expires_at, now, affiliate_contracts_js_1.DEFAULT_CODE_VALIDITY_DAYS),
        usageLimit: (0, affiliate_api_contracts_js_1.parseUsageLimit)(payload.usage_limit),
        firstVisitOnly: (0, affiliate_api_contracts_js_1.parseFirstVisitOnly)(payload.first_visit_only, true),
    };
}
/* ======================================================================== */
function registerAffiliateRoutes(deps) {
    const { adminRouter, merchantRouter } = deps;
    /* ------------------------------------------------------------- admin */
    adminRouter.get('/affiliates', async (req, res) => {
        const request = req;
        try {
            const query = pageQuery(request);
            return pageResponse(res, query, await (0, affiliate_store_js_1.listAllAffiliates)(query));
        }
        catch (error) {
            return respond(deps, res, 'admin_affiliates', error);
        }
    });
    adminRouter.post('/affiliates', async (req, res) => {
        const request = req;
        try {
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const name = (0, affiliate_api_contracts_js_1.parseAffiliateName)(payload.name);
            const phoneE164 = (0, affiliate_api_contracts_js_1.parsePhone)(payload.phone, deps.normalizePhone);
            const now = clock(deps);
            const affiliate = await (0, affiliate_store_js_1.createGlobalAffiliate)({
                affiliateId: affiliateIdFor(deps, phoneE164),
                phoneE164,
                name,
                now,
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate.create',
                targetType: 'affiliate',
                targetId: affiliate.id,
                merchantId: null,
                details: { name: affiliate.name, phone_masked: (0, affiliate_notifications_js_1.maskPhone)(phoneE164) },
            });
            return res.json({ success: true, data: affiliate });
        }
        catch (error) {
            return respond(deps, res, 'admin_create_affiliate', error);
        }
    });
    adminRouter.get('/affiliates/:affiliateId', async (req, res) => {
        try {
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            const affiliate = await (0, affiliate_store_js_1.getAffiliate)(affiliateId);
            if (affiliate === null)
                throw notFound('affiliate_not_found');
            return res.json({ success: true, data: affiliate });
        }
        catch (error) {
            return respond(deps, res, 'admin_affiliate_detail', error);
        }
    });
    adminRouter.patch('/affiliates/:affiliateId', async (req, res) => {
        const request = req;
        try {
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const name = (0, affiliate_api_contracts_js_1.parseAffiliateName)(payload.name);
            const change = await (0, affiliate_store_js_1.updateAffiliateName)({
                affiliateId,
                name,
                now: clock(deps),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate.update',
                targetType: 'affiliate',
                targetId: affiliateId,
                merchantId: null,
                details: { before: change.before.name, after: change.after.name },
            });
            return res.json({ success: true, data: change.after });
        }
        catch (error) {
            return respond(deps, res, 'admin_update_affiliate', error);
        }
    });
    adminRouter.post('/affiliates/:affiliateId/status', async (req, res) => {
        const request = req;
        try {
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const status = (0, affiliate_api_contracts_js_1.parseAffiliateStatus)(payload.status);
            const change = await (0, affiliate_store_js_1.setAffiliateStatus)({
                affiliateId,
                status,
                now: clock(deps),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate.status',
                targetType: 'affiliate',
                targetId: affiliateId,
                merchantId: null,
                details: { before: change.before.status, after: change.after.status },
            });
            return res.json({ success: true, data: change.after });
        }
        catch (error) {
            return respond(deps, res, 'admin_affiliate_status', error);
        }
    });
    adminRouter.post('/affiliates/:affiliateId/merchants/:merchantId', async (req, res) => {
        const request = req;
        try {
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            const merchantId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.merchantId, 'merchant_not_found');
            if (!(await (0, affiliate_store_js_1.merchantExists)(merchantId)))
                throw notFound('merchant_not_found');
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const now = clock(deps);
            const linked = await (0, affiliate_store_js_1.linkAffiliateToMerchant)({
                merchantId,
                affiliateId,
                defaults: parseCodeDefaults(payload, now),
                now,
            });
            await (0, affiliate_store_js_1.appendAffiliateEvent)(merchantId, {
                eventType: 'AFFILIATE_CREATED',
                affiliateId,
                metadata: { source: 'admin_link', code_id: linked.code?.id ?? null },
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate.link',
                targetType: 'affiliate_merchant',
                targetId: affiliateId,
                merchantId,
                details: { code_id: linked.code?.id ?? null },
            });
            return res.json({ success: true, data: linked });
        }
        catch (error) {
            return respond(deps, res, 'admin_link_affiliate', error);
        }
    });
    adminRouter.delete('/affiliates/:affiliateId/merchants/:merchantId', async (req, res) => {
        const request = req;
        try {
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            const merchantId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.merchantId, 'merchant_not_found');
            if (!(await (0, affiliate_store_js_1.merchantExists)(merchantId)))
                throw notFound('merchant_not_found');
            await (0, affiliate_store_js_1.unlinkAffiliateFromMerchant)({
                merchantId,
                affiliateId,
                now: clock(deps),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate.unlink',
                targetType: 'affiliate_merchant',
                targetId: affiliateId,
                merchantId,
                details: {},
            });
            return res.json({ success: true });
        }
        catch (error) {
            return respond(deps, res, 'admin_unlink_affiliate', error);
        }
    });
    adminRouter.get('/merchants/:merchantId/affiliates', async (req, res) => {
        const request = req;
        try {
            const merchantId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.merchantId, 'merchant_not_found');
            if (!(await (0, affiliate_store_js_1.merchantExists)(merchantId)))
                throw notFound('merchant_not_found');
            const query = pageQuery(request);
            return pageResponse(res, query, await (0, affiliate_store_js_1.listMerchantAffiliates)(merchantId, query));
        }
        catch (error) {
            return respond(deps, res, 'admin_merchant_affiliates', error);
        }
    });
    adminRouter.get('/merchants/:merchantId/affiliate-rewards', async (req, res) => {
        const request = req;
        try {
            const merchantId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.merchantId, 'merchant_not_found');
            if (!(await (0, affiliate_store_js_1.merchantExists)(merchantId)))
                throw notFound('merchant_not_found');
            const query = pageQuery(request);
            return pageResponse(res, query, await (0, affiliate_store_js_1.listRewards)(merchantId, query));
        }
        catch (error) {
            return respond(deps, res, 'admin_merchant_affiliate_rewards', error);
        }
    });
    adminRouter.get('/merchants/:merchantId/affiliate-metrics', async (req, res) => {
        const request = req;
        try {
            const merchantId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.merchantId, 'merchant_not_found');
            if (!(await (0, affiliate_store_js_1.merchantExists)(merchantId)))
                throw notFound('merchant_not_found');
            const affiliateId = queryString(request.query.affiliate_id) ?? null;
            return res.json({
                success: true,
                data: await (0, affiliate_store_js_1.affiliateMetrics)({ merchantId, affiliateId }),
            });
        }
        catch (error) {
            return respond(deps, res, 'admin_merchant_affiliate_metrics', error);
        }
    });
    /* ---------------------------------------------------------- merchant */
    merchantRouter.post('/affiliates', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const name = (0, affiliate_api_contracts_js_1.parseAffiliateName)(payload.name);
            const phoneE164 = (0, affiliate_api_contracts_js_1.parsePhone)(payload.phone, deps.normalizePhone);
            const now = clock(deps);
            const created = await (0, affiliate_store_js_1.createAffiliateForMerchant)({
                merchantId: business.id,
                affiliateId: affiliateIdFor(deps, phoneE164),
                phoneE164,
                name,
                defaults: parseCodeDefaults(payload, now),
                now,
            });
            await (0, affiliate_store_js_1.appendAffiliateEvent)(business.id, {
                eventType: 'AFFILIATE_CREATED',
                affiliateId: created.affiliate.id,
                metadata: { identity_created: created.identityCreated },
            });
            await (0, affiliate_store_js_1.appendAffiliateEvent)(business.id, {
                eventType: 'AFFILIATE_CODE_CREATED',
                affiliateId: created.affiliate.id,
                metadata: { code_id: created.code.id, code: created.code.code },
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate.create',
                targetType: 'affiliate',
                targetId: created.affiliate.id,
                merchantId: business.id,
                details: {
                    // The phone is never written to the trail in full; the last four
                    // digits are enough to recognise the person in a support call.
                    phone_masked: (0, affiliate_notifications_js_1.maskPhone)(phoneE164),
                    identity_created: created.identityCreated,
                    code_id: created.code.id,
                    benefit_type: created.code.benefit_type,
                    benefit_value: created.code.benefit_value,
                },
            });
            return res.json({
                success: true,
                data: {
                    ...created.affiliate,
                    merchant_id: business.id,
                    link_status: created.link.status,
                    linked_at: created.link.linkedAt,
                    code: created.code,
                },
            });
        }
        catch (error) {
            return respond(deps, res, 'merchant_create_affiliate', error);
        }
    });
    merchantRouter.get('/affiliates', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const query = pageQuery(request);
            return pageResponse(res, query, await (0, affiliate_store_js_1.listMerchantAffiliates)(business.id, query));
        }
        catch (error) {
            return respond(deps, res, 'merchant_affiliates', error);
        }
    });
    // Declared before `/affiliates/:affiliateId`, because Express matches in
    // registration order and would otherwise read "metrics" as an id.
    merchantRouter.get('/affiliates/metrics', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            return res.json({
                success: true,
                data: await (0, affiliate_store_js_1.affiliateMetrics)({ merchantId: business.id, affiliateId: null }),
            });
        }
        catch (error) {
            return respond(deps, res, 'merchant_affiliate_metrics', error);
        }
    });
    merchantRouter.get('/affiliates/:affiliateId/metrics', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            // The link is the isolation boundary: without it there are no metrics to
            // read, and an id borrowed from another business answers "not found".
            const affiliate = await (0, affiliate_store_js_1.getMerchantAffiliate)(business.id, affiliateId);
            if (affiliate === null)
                throw notFound('affiliate_not_found');
            return res.json({
                success: true,
                data: await (0, affiliate_store_js_1.affiliateMetrics)({ merchantId: business.id, affiliateId }),
            });
        }
        catch (error) {
            return respond(deps, res, 'merchant_affiliate_metrics_one', error);
        }
    });
    merchantRouter.get('/affiliates/:affiliateId', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            const affiliate = await (0, affiliate_store_js_1.getMerchantAffiliate)(business.id, affiliateId);
            if (affiliate === null)
                throw notFound('affiliate_not_found');
            return res.json({ success: true, data: affiliate });
        }
        catch (error) {
            return respond(deps, res, 'merchant_affiliate_detail', error);
        }
    });
    merchantRouter.patch('/affiliates/:affiliateId', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            const existing = await (0, affiliate_store_js_1.getMerchantAffiliate)(business.id, affiliateId);
            if (existing === null)
                throw notFound('affiliate_not_found');
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const name = (0, affiliate_api_contracts_js_1.parseAffiliateName)(payload.name);
            const change = await (0, affiliate_store_js_1.updateMerchantAffiliateName)({
                merchantId: business.id,
                affiliateId,
                name,
                now: clock(deps),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate.update',
                targetType: 'affiliate',
                targetId: affiliateId,
                merchantId: business.id,
                details: {
                    before: change.before.displayName,
                    after: change.after.displayName,
                },
            });
            return res.json({
                success: true,
                // The code keeps the name it was minted with: it is printed, shared and
                // typed by customers, so renaming the person cannot rename it.
                data: {
                    ...existing,
                    name: change.after.displayName,
                    first_name: change.after.firstName,
                    last_name: change.after.lastName,
                },
            });
        }
        catch (error) {
            return respond(deps, res, 'merchant_update_affiliate', error);
        }
    });
    merchantRouter.post('/affiliates/:affiliateId/activate', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            const change = await (0, affiliate_store_js_1.setLinkStatus)({
                merchantId: business.id,
                affiliateId,
                status: 'ACTIVE',
                now: clock(deps),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate.link_status',
                targetType: 'affiliate_merchant',
                targetId: affiliateId,
                merchantId: business.id,
                details: { before: change.before, after: change.after },
            });
            return res.json({
                success: true,
                data: await (0, affiliate_store_js_1.getMerchantAffiliate)(business.id, affiliateId),
            });
        }
        catch (error) {
            return respond(deps, res, 'merchant_activate_affiliate', error);
        }
    });
    merchantRouter.post('/affiliates/:affiliateId/deactivate', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.affiliateId, 'affiliate_not_found');
            const change = await (0, affiliate_store_js_1.setLinkStatus)({
                merchantId: business.id,
                affiliateId,
                status: 'INACTIVE',
                now: clock(deps),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate.link_status',
                targetType: 'affiliate_merchant',
                targetId: affiliateId,
                merchantId: business.id,
                details: { before: change.before, after: change.after },
            });
            return res.json({
                success: true,
                data: await (0, affiliate_store_js_1.getMerchantAffiliate)(business.id, affiliateId),
            });
        }
        catch (error) {
            return respond(deps, res, 'merchant_deactivate_affiliate', error);
        }
    });
    merchantRouter.post('/affiliate-codes', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const affiliateId = (0, affiliate_api_contracts_js_1.parseIdParam)(payload.affiliate_id, 'affiliate_not_found');
            const now = clock(deps);
            const code = await (0, affiliate_store_js_1.createCodeForLinkedAffiliate)({
                merchantId: business.id,
                affiliateId,
                defaults: parseCodeDefaults(payload, now),
                now,
            });
            await (0, affiliate_store_js_1.appendAffiliateEvent)(business.id, {
                eventType: 'AFFILIATE_CODE_CREATED',
                affiliateId,
                metadata: { code_id: code.id, code: code.code },
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate_code.create',
                targetType: 'affiliate_code',
                targetId: code.id,
                merchantId: business.id,
                details: {
                    affiliate_id: affiliateId,
                    benefit_type: code.benefit_type,
                    benefit_value: code.benefit_value,
                },
            });
            return res.json({ success: true, data: code });
        }
        catch (error) {
            return respond(deps, res, 'merchant_create_affiliate_code', error);
        }
    });
    merchantRouter.get('/affiliate-codes', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const query = pageQuery(request);
            return pageResponse(res, query, await (0, affiliate_store_js_1.listMerchantCodes)(business.id, query));
        }
        catch (error) {
            return respond(deps, res, 'merchant_affiliate_codes', error);
        }
    });
    merchantRouter.get('/affiliate-codes/:codeId', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const codeId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.codeId, 'code_not_found');
            const code = await (0, affiliate_store_js_1.getMerchantCode)(business.id, codeId);
            if (code === null)
                throw notFound('code_not_found');
            return res.json({ success: true, data: code });
        }
        catch (error) {
            return respond(deps, res, 'merchant_affiliate_code_detail', error);
        }
    });
    merchantRouter.patch('/affiliate-codes/:codeId', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const codeId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.codeId, 'code_not_found');
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const now = clock(deps);
            // Each field is applied only when it was actually sent. A PATCH that
            // omitted the dates must not reset the code's validity to the default.
            const change = await (0, affiliate_store_js_1.updateCode)({
                merchantId: business.id,
                codeId,
                patch: {
                    benefit: payload.benefit_type === undefined && payload.benefit_value === undefined
                        ? undefined
                        : (0, affiliate_api_contracts_js_1.parseBenefit)(payload.benefit_type, payload.benefit_value),
                    validity: payload.starts_at === undefined && payload.expires_at === undefined
                        ? undefined
                        : (0, affiliate_api_contracts_js_1.parseValidityPair)(payload.starts_at, payload.expires_at, now),
                    usageLimit: payload.usage_limit === undefined
                        ? undefined
                        : (0, affiliate_api_contracts_js_1.parseUsageLimit)(payload.usage_limit),
                    firstVisitOnly: payload.first_visit_only === undefined
                        ? undefined
                        : (0, affiliate_api_contracts_js_1.parseFirstVisitOnly)(payload.first_visit_only, true),
                },
                now,
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate_code.update',
                targetType: 'affiliate_code',
                targetId: codeId,
                merchantId: business.id,
                details: { before: change.before, after: change.after },
            });
            return res.json({ success: true, data: change.after });
        }
        catch (error) {
            return respond(deps, res, 'merchant_update_affiliate_code', error);
        }
    });
    merchantRouter.post('/affiliate-codes/:codeId/enable', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const codeId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.codeId, 'code_not_found');
            const change = await (0, affiliate_store_js_1.setCodeStatus)({
                merchantId: business.id,
                codeId,
                status: 'ACTIVE',
                now: clock(deps),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate_code.status',
                targetType: 'affiliate_code',
                targetId: codeId,
                merchantId: business.id,
                details: { before: change.before.status, after: change.after.status },
            });
            return res.json({ success: true, data: change.after });
        }
        catch (error) {
            return respond(deps, res, 'merchant_enable_affiliate_code', error);
        }
    });
    merchantRouter.post('/affiliate-codes/:codeId/disable', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const codeId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.codeId, 'code_not_found');
            const change = await (0, affiliate_store_js_1.setCodeStatus)({
                merchantId: business.id,
                codeId,
                status: 'DISABLED',
                now: clock(deps),
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate_code.status',
                targetType: 'affiliate_code',
                targetId: codeId,
                merchantId: business.id,
                details: { before: change.before.status, after: change.after.status },
            });
            return res.json({ success: true, data: change.after });
        }
        catch (error) {
            return respond(deps, res, 'merchant_disable_affiliate_code', error);
        }
    });
    /**
     * The one referral endpoint a till calls, and the only one rate limited.
     *
     * Any authenticated member of the business may call it: validating a code is
     * part of serving a customer, not of managing affiliates. The budget is
     * spent before the body is read, so a caller cannot walk the code space by
     * sending malformed requests, and a refusal says nothing about whether the
     * code exists.
     */
    merchantRouter.post('/referrals/validate-code', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const now = clock(deps);
            const decision = await (0, affiliate_store_js_1.consumeRateLimit)({
                merchantId: business.id,
                actorId: actorIdOf(request),
                action: 'validate_code',
                policy: affiliate_rate_limit_js_1.VALIDATE_CODE_POLICY,
                now,
            });
            if (!decision.allowed) {
                const refusal = (0, affiliate_api_contracts_js_1.rateLimitedResponse)(decision.retryAfterMs);
                res.setHeader('Retry-After', refusal.headers['Retry-After']);
                return res.status(refusal.status).json(refusal.body);
            }
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const rawCode = (0, affiliate_api_contracts_js_1.parseCodeText)(payload.code);
            const customerPhoneE164 = payload.customer_phone === undefined || payload.customer_phone === null
                ? null
                : (0, affiliate_api_contracts_js_1.parsePhone)(payload.customer_phone, deps.normalizePhone);
            const saleAmount = (0, affiliate_api_contracts_js_1.parseOptionalSaleAmount)(payload.sale_amount);
            const outcome = await (0, affiliate_store_js_1.validateReferralCode)({
                merchantId: business.id,
                rawCode,
                customerPhoneE164,
                saleAmount,
                now,
            });
            // Append-only, both ways round: a rejection is as much a fact about this
            // till as an acceptance, and the metrics screen counts both.
            await (0, affiliate_store_js_1.appendAffiliateEvent)(business.id, {
                eventType: outcome.validation.ok
                    ? 'REFERRAL_CODE_VALIDATED'
                    : 'REFERRAL_REJECTED',
                affiliateId: outcome.affiliateId,
                customerId: outcome.customerId,
                dedupeKey: outcome.dedupeKey,
                metadata: {
                    code_id: outcome.codeId,
                    reason: outcome.validation.ok ? null : outcome.validation.reason,
                    had_customer_phone: customerPhoneE164 !== null,
                    had_sale_amount: saleAmount !== null,
                },
            });
            const body = (0, affiliate_api_contracts_js_1.referralValidationResponse)(outcome, now);
            return res.json({ success: true, data: body });
        }
        catch (error) {
            return respond(deps, res, 'merchant_validate_code', error);
        }
    });
    /**
     * The authoritative referred sale: one command, one transaction.
     *
     * Open to any authenticated member of the business, like validating a code
     * and for the same reason — this is the till confirming a sale with a
     * customer standing there, not an owner managing affiliates. What it may
     * change is fixed by `parseReferralSaleCommit`, which reads the sale's local
     * identity, the customer, the gross amount and the code, and nothing else.
     * The benefit, the loyalty points, the reward and the affiliate all come off
     * stored records inside the transaction.
     *
     * The preview the till was shown is advisory and is not trusted here: every
     * check runs again against what Firestore holds now and against the real
     * amount, so a code that expired between the preview and the confirmation is
     * refused with a reason the cashier can act on — and the sale is simply made
     * without a code instead.
     */
    merchantRouter.post('/referral-sales/commit', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const payload = (0, affiliate_api_contracts_js_1.parseBodyObject)(req.body);
            const parsed = (0, affiliate_api_contracts_js_1.parseReferralSaleCommit)(payload, deps.normalizePhone);
            const outcome = await (0, affiliate_sale_firestore_js_1.commitReferralSaleToFirestore)({
                merchantId: business.id,
                deviceId: parsed.deviceId,
                localSaleId: parsed.localSaleId,
                customerId: parsed.customerId,
                customerPhoneE164: parsed.customerPhoneE164,
                grossAmount: parsed.grossAmount,
                rawCode: parsed.rawCode,
                items: parsed.items,
                appUserId: actorIdOf(request),
                now: clock(deps),
            });
            switch (outcome.status) {
                case 'committed':
                case 'replayed':
                    // A replay answers exactly what the first call answered, apart from
                    // saying so: a till that retried after a dropped response must not
                    // be able to tell the difference and sell twice.
                    return res.json({
                        success: true,
                        data: { outcome: outcome.status, ...outcome.result },
                    });
                case 'rejected':
                    // Not an error: the request was well formed and the answer is that
                    // this code cannot be used for this sale. The till is told why, in
                    // the same shape `validate-code` uses, and sells without a code.
                    return res.json({
                        success: true,
                        data: {
                            outcome: 'rejected',
                            code: 'referral_rejected',
                            reason: outcome.reason,
                            message: outcome.message,
                        },
                    });
                case 'conflict':
                    throw (0, affiliate_api_contracts_js_1.affiliateApiError)(409, 'sale_conflict');
                default:
                    throw (0, affiliate_api_contracts_js_1.affiliateApiError)(404, 'customer_not_found');
            }
        }
        catch (error) {
            return respond(deps, res, 'merchant_commit_referral_sale', error);
        }
    });
    merchantRouter.get('/referrals', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const query = pageQuery(request);
            return pageResponse(res, query, await (0, affiliate_store_js_1.listAttributions)(business.id, query));
        }
        catch (error) {
            return respond(deps, res, 'merchant_referrals', error);
        }
    });
    merchantRouter.get('/referrals/:attributionId', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const attributionId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.attributionId, 'referral_not_found');
            const attribution = await (0, affiliate_store_js_1.getAttribution)(business.id, attributionId);
            if (attribution === null)
                throw notFound('referral_not_found');
            const rewards = await (0, affiliate_store_js_1.listRewards)(business.id, {
                limit: MAX_PAGE,
                offset: 0,
                affiliateId: attribution.affiliate_id,
            });
            return res.json({
                success: true,
                data: {
                    ...attribution,
                    rewards: rewards.items.filter((reward) => reward.attribution_id === attribution.id),
                },
            });
        }
        catch (error) {
            return respond(deps, res, 'merchant_referral_detail', error);
        }
    });
    merchantRouter.get('/affiliate-rewards', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            const query = pageQuery(request);
            return pageResponse(res, query, await (0, affiliate_store_js_1.listRewards)(business.id, query));
        }
        catch (error) {
            return respond(deps, res, 'merchant_affiliate_rewards', error);
        }
    });
    merchantRouter.post('/affiliate-rewards/:rewardId/approve', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const rewardId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.rewardId, 'reward_not_found');
            // No amount is read from the request. What the reward is worth was
            // decided when it was created, from the business's own settings.
            const change = await (0, affiliate_store_js_1.transitionReward)({
                merchantId: business.id,
                rewardId,
                to: 'APPROVED',
                actorId: actorIdOf(request),
                now: clock(deps),
            });
            await (0, affiliate_store_js_1.appendAffiliateEvent)(business.id, {
                eventType: 'AFFILIATE_REWARD_APPROVED',
                affiliateId: change.after.affiliate_id,
                metadata: { reward_id: rewardId, value: change.after.value },
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate_reward.approve',
                targetType: 'affiliate_reward',
                targetId: rewardId,
                merchantId: business.id,
                details: { before: change.before.status, after: change.after.status },
            });
            return res.json({ success: true, data: change.after });
        }
        catch (error) {
            return respond(deps, res, 'merchant_approve_affiliate_reward', error);
        }
    });
    merchantRouter.post('/affiliate-rewards/:rewardId/cancel', async (req, res) => {
        const request = req;
        try {
            const business = await deps.requireBusiness(request, res);
            if (!business)
                return undefined;
            requireOwnerOrAdmin(deps, request);
            const rewardId = (0, affiliate_api_contracts_js_1.parseIdParam)(req.params.rewardId, 'reward_not_found');
            const change = await (0, affiliate_store_js_1.transitionReward)({
                merchantId: business.id,
                rewardId,
                to: 'CANCELLED',
                actorId: actorIdOf(request),
                now: clock(deps),
            });
            await (0, affiliate_store_js_1.appendAffiliateEvent)(business.id, {
                eventType: 'AFFILIATE_REWARD_CANCELLED',
                affiliateId: change.after.affiliate_id,
                metadata: { reward_id: rewardId, value: change.after.value },
            });
            await (0, admin_audit_js_1.recordAuditEvent)(deps.auditActorFrom(request), {
                action: 'affiliate_reward.cancel',
                targetType: 'affiliate_reward',
                targetId: rewardId,
                merchantId: business.id,
                details: { before: change.before.status, after: change.after.status },
            });
            return res.json({ success: true, data: change.after });
        }
        catch (error) {
            return respond(deps, res, 'merchant_cancel_affiliate_reward', error);
        }
    });
}
