"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runDiscoveryBatch = runDiscoveryBatch;
exports.storeDiscovered = storeDiscovered;
exports.signalsFromCompany = signalsFromCompany;
exports.operationalFrom = operationalFrom;
exports.signalsFromResearch = signalsFromResearch;
exports.fetchListingDetails = fetchListingDetails;
exports.findDecisionMakers = findDecisionMakers;
exports.researchCompany = researchCompany;
exports.guardSpend = guardSpend;
exports.reportedCostFrom = reportedCostFrom;
const prospecting_budget_js_1 = require("./prospecting_budget.js");
const prospecting_config_js_1 = require("./prospecting_config.js");
const prospecting_contracts_js_1 = require("./prospecting_contracts.js");
const prospecting_providers_js_1 = require("./prospecting_providers.js");
const prospecting_scoring_js_1 = require("./prospecting_scoring.js");
/** Only used for its parameter type, above. */
function describeActivity(type) {
    return type;
}
/**
 * One batch of discovery.
 *
 * Returns counts rather than writing them, so the job record is advanced by
 * `applyBatch` in one place and this function stays free of the job's state
 * machine. A batch that discovers nothing new is not a failure — it is what
 * running the same search twice looks like, and the duplicate count is what
 * says so on the screen.
 */
async function runDiscoveryBatch(input) {
    const { deps } = input;
    const outcome = {
        discovered: 0,
        duplicates: 0,
        qualified: 0,
        disqualified: 0,
        enriched: 0,
        failed: 0,
        spentUsd: 0,
        cursor: null,
        fatalCode: null,
    };
    // Discovery is itself a paid call, so it is guarded like every other one.
    const searchSpend = await guardSpend({
        operation: 'SEARCH_BUSINESSES',
        prospectId: null,
        leadScore: null,
        deps,
    });
    if (!searchSpend.allowed) {
        outcome.fatalCode = searchSpend.refusal;
        return outcome;
    }
    const criteria = {
        industries: input.criteria.industries.length > 0
            ? input.criteria.industries
            : prospecting_config_js_1.ICP_INDUSTRIES.map((entry) => entry.businessType),
        city: input.criteria.city,
        province: input.criteria.province,
        country: deps.settings.geography.country,
        employeeMin: input.criteria.employeeMin,
        employeeMax: input.criteria.employeeMax,
        limit: input.batchSize,
        cursor: input.cursor,
    };
    const chain = await (0, prospecting_providers_js_1.runChain)(deps.providers.discovery, (provider) => provider.searchBusinesses(criteria));
    for (const attempt of chain.attempts) {
        await deps.store.recordUsage({
            provider: attempt.provider,
            operation: 'SEARCH_BUSINESSES',
            prospectId: null,
            estimatedCostUsd: prospecting_config_js_1.OPERATION_COST_USD.SEARCH_BUSINESSES,
            success: attempt.ok,
            errorCode: attempt.code,
        });
        outcome.spentUsd = (0, prospecting_budget_js_1.round)(outcome.spentUsd + prospecting_config_js_1.OPERATION_COST_USD.SEARCH_BUSINESSES);
    }
    if (!chain.ok) {
        // Running out of results is the ordinary end of a search, not a failure:
        // five hundred barbershops were asked for and Matola has forty.
        outcome.fatalCode = chain.code === 'NO_RESULT' ? null : chain.code;
        outcome.cursor = null;
        return outcome;
    }
    for (const result of chain.value) {
        if (result.cursor !== null)
            outcome.cursor = result.cursor;
        try {
            const stored = await storeDiscovered({
                company: result.company,
                criteria: input.criteria,
                deps,
            });
            outcome.discovered++;
            if (!stored.created)
                outcome.duplicates++;
            if (stored.qualified)
                outcome.qualified++;
            else
                outcome.disqualified++;
        }
        catch {
            // One business that could not be stored costs that business. The page it
            // came in on is still worth keeping.
            outcome.failed++;
        }
    }
    // A page that returned results but no cursor is the last one.
    if (chain.value.length === 0)
        outcome.cursor = null;
    return outcome;
}
/**
 * One discovered business, through deduplication, the customer check,
 * qualification and scoring.
 *
 * The customer check runs after deduplication and before qualification,
 * because a business that already pays for MaisUm should be recognised as one
 * whatever its trade or its city — and because the prospect it produces is the
 * record that stops it being discovered again next month.
 */
async function storeDiscovered(input) {
    const { deps } = input;
    const claim = await deps.store.claimCompany(input.company);
    const customer = await deps.store.matchExistingCustomer(input.company);
    if (customer.kind === 'PHONE') {
        const prospect = await deps.store.createProspect({
            companyId: claim.companyId,
            source: input.source ?? 'DISCOVERY',
            sourceReference: input.company.source_reference,
            status: 'EXISTING_CUSTOMER',
            suspectedMerchantId: customer.merchantId,
        });
        await deps.store.appendActivity({
            prospectId: prospect.prospectId,
            type: 'DISCOVERED',
            description: 'Já é cliente MaisUm (telefone coincide).',
            metadata: { merchant_id: customer.merchantId, match: 'PHONE' },
        });
        return {
            companyId: claim.companyId,
            prospectId: prospect.prospectId,
            created: claim.created,
            qualified: false,
            score: null,
            status: 'EXISTING_CUSTOMER',
        };
    }
    const qualification = (0, prospecting_scoring_js_1.qualify)({
        name: input.company.name,
        businessType: input.company.industry,
        city: input.company.city,
        province: input.company.province,
        country: input.company.country,
    }, deps.settings.geography);
    if (!qualification.qualified) {
        const prospect = await deps.store.createProspect({
            companyId: claim.companyId,
            source: input.source ?? 'DISCOVERY',
            sourceReference: input.company.source_reference,
            status: 'NOT_A_FIT',
            disqualifyReason: qualification.reason,
            suspectedMerchantId: customer.kind === 'NAME' ? customer.merchantId : null,
        });
        await deps.store.appendActivity({
            prospectId: prospect.prospectId,
            type: 'DISCOVERED',
            description: 'Descoberto e desqualificado.',
            metadata: { reason: qualification.reason },
        });
        return {
            companyId: claim.companyId,
            prospectId: prospect.prospectId,
            created: claim.created,
            qualified: false,
            score: null,
            status: 'NOT_A_FIT',
        };
    }
    const prospect = await deps.store.createProspect({
        companyId: claim.companyId,
        source: input.source ?? 'DISCOVERY',
        sourceReference: input.company.source_reference,
        status: 'RAW',
        suspectedMerchantId: customer.kind === 'NAME' ? customer.merchantId : null,
    });
    const score = (0, prospecting_scoring_js_1.scoreProspect)(signalsFromCompany(input.company), deps.settings.scoring, deps.settings.geography);
    await deps.store.saveScores({ prospectId: prospect.prospectId, score });
    if (prospect.created) {
        await deps.store.appendActivity({
            prospectId: prospect.prospectId,
            type: 'DISCOVERED',
            description: `Descoberto via ${input.company.source}.`,
            metadata: {
                matched_on: claim.matchedOn?.kind ?? null,
                suspected_merchant_id: customer.kind === 'NAME' ? customer.merchantId : null,
            },
        });
    }
    // QUALIFIED then SCORED, both recorded, because the pipeline order is the
    // thing the activity trail is there to evidence.
    await deps.store.setStatus({ prospectId: prospect.prospectId, to: 'QUALIFIED' });
    await deps.store.setStatus({ prospectId: prospect.prospectId, to: 'SCORED' });
    return {
        companyId: claim.companyId,
        prospectId: prospect.prospectId,
        created: claim.created,
        qualified: true,
        score,
        status: 'SCORED',
    };
}
/**
 * What a company record says, as scoring signals.
 *
 * Everything not present on the company is left at its unknown value, which is
 * why this spreads `UNKNOWN_SIGNALS` rather than building an object field by
 * field: a signal added to the type and forgotten here would otherwise arrive
 * as `undefined` and be read as false.
 */
function signalsFromCompany(company, extra = {}) {
    const socialProfiles = [
        company.instagram_url,
        company.facebook_url,
        company.linkedin_url,
    ].filter((value) => value !== null).length;
    const hasContactChannel = company.phone !== null || company.whatsapp !== null || company.email !== null;
    return {
        ...prospecting_scoring_js_1.UNKNOWN_SIGNALS,
        businessType: company.industry,
        employeeCount: company.employee_count,
        city: company.city,
        province: company.province,
        country: company.country,
        websiteUrl: company.website,
        socialProfileCount: socialProfiles,
        hasContactChannel,
        /**
         * A published phone is a reachable contact.
         *
         * This used to be true only once a people database had named somebody and
         * verified their email. For a barbershop in Maputo that standard describes
         * a lead that does not exist: there is no LinkedIn profile, and the person
         * who decides is the person who answers the number on the door. The number
         * is the contact, and pretending otherwise left the criterion permanently
         * unfired. `signalsFromResearch` still overrides this with the stronger
         * fact when contacts are actually found.
         */
        reachableContact: hasContactChannel,
        rating: company.rating,
        reviewCount: company.review_count,
        hasOpeningHours: company.has_opening_hours,
        hasPhotos: company.has_photos,
        isOperational: operationalFrom(company.business_status),
        ...extra,
    };
}
/**
 * The source's trading status, read conservatively.
 *
 * Unrecognised text is `null`, not `false`. A provider that grows a new status
 * string must not silently cost every lead five points, and "we have not been
 * told" is a different answer from "it is closed" everywhere else in this
 * module.
 */
function operationalFrom(status) {
    if (status === null)
        return null;
    const normalized = status.trim().toUpperCase();
    if (normalized === '')
        return null;
    if (normalized === 'OPERATIONAL')
        return true;
    if (normalized === 'CLOSED_PERMANENTLY' ||
        normalized === 'CLOSED_TEMPORARILY') {
        return false;
    }
    return null;
}
/** The research findings, folded into the signals they answer. */
function signalsFromResearch(base, research, contacts) {
    const decisionMakers = contacts.filter((contact) => (0, prospecting_contracts_js_1.isDecisionMakerSeniority)(contact.seniority));
    return {
        ...base,
        runsPromotions: research?.runs_promotions ?? base.runsPromotions,
        growthSignal: research?.growth_signal ?? base.growthSignal,
        socialProfileCount: research === null
            ? base.socialProfileCount
            : Math.max(base.socialProfileCount, research.social_profiles.length),
        decisionMakerIdentified: decisionMakers.length > 0,
        reachableContact: contacts.some((contact) => contact.phone !== null ||
            (contact.email !== null && (0, prospecting_contracts_js_1.isReachableEmail)(contact.email_status))),
    };
}
/**
 * Finds a decision maker and fills in what is known about them.
 *
 * Two paid calls, guarded separately. The second only happens if the first
 * found somebody — there is nothing to enrich otherwise, and a chain that
 * called person enrichment with no person would be paying to ask about
 * nobody.
 *
 * A lead that yields no decision maker becomes `NO_RESULT` rather than
 * `FAILED`, and that is stored: it stops the same lead being paid for again
 * next week to learn the same thing.
 */
/**
 * The dear half of a listing, behind the score gate.
 *
 * This is the only per-lead cost the module has left, and the whole of the
 * cost design is the two lines it sits between: `guardSpend` refuses
 * `BELOW_THRESHOLD` before it consults the budget at all, so a campaign that
 * turns up a thousand shops pays for the three hundred the rules liked and
 * nothing for the rest. Discovery already read everything that was free.
 *
 * On success the company is re-scored, because the fields that just arrived —
 * a website, a phone, a published timetable, photos — are worth twenty of the
 * hundred points. Not re-scoring would leave every enriched lead ranked on the
 * evidence available before the thing that was paid for arrived.
 */
async function fetchListingDetails(input) {
    const { deps } = input;
    const outcome = {
        score: null,
        status: 'NOT_STARTED',
        contactsFound: 0,
        decisionMakersFound: 0,
        spentUsd: 0,
        refusal: null,
        errorCode: null,
        fieldsDiscovered: [],
    };
    const reference = input.company.source_reference;
    if (reference === null || reference.trim() === '') {
        // A company discovered by a source that issues no stable id cannot be
        // asked about a second time. Not a failure and not a budget problem —
        // there is simply nothing to call, and calling anyway would spend money
        // to receive a 404.
        outcome.status = 'NO_RESULT';
        await deps.store.setEnrichment({
            prospectId: input.prospectId,
            status: outcome.status,
            lastEnrichedAt: deps.now(),
        });
        return outcome;
    }
    const decision = await guardSpend({
        operation: 'FETCH_LISTING_DETAILS',
        prospectId: input.prospectId,
        leadScore: input.leadScore,
        deps,
    });
    if (!decision.allowed) {
        outcome.refusal = decision.refusal;
        outcome.status =
            decision.refusal === 'BELOW_THRESHOLD' ? 'BELOW_THRESHOLD' : 'BUDGET_BLOCKED';
        await deps.store.setEnrichment({
            prospectId: input.prospectId,
            status: outcome.status,
        });
        return outcome;
    }
    await deps.store.setEnrichment({ prospectId: input.prospectId, status: 'IN_PROGRESS' });
    const chain = await (0, prospecting_providers_js_1.runChain)(deps.providers.listingDetail, (provider) => provider.fetchListingDetail({ reference }));
    outcome.spentUsd = (0, prospecting_budget_js_1.round)(outcome.spentUsd +
        (await chargeAttempts({
            attempts: chain.attempts,
            operation: 'FETCH_LISTING_DETAILS',
            prospectId: input.prospectId,
            deps,
        })));
    if (!chain.ok) {
        outcome.errorCode = chain.code;
        outcome.status = chain.code === 'NO_RESULT' ? 'NO_RESULT' : 'FAILED';
        await deps.store.setEnrichment({
            prospectId: input.prospectId,
            status: outcome.status,
            lastEnrichedAt: deps.now(),
        });
        return outcome;
    }
    const detail = chain.value;
    if (detail.phone !== null)
        outcome.fieldsDiscovered.push('phone');
    if (detail.website !== null)
        outcome.fieldsDiscovered.push('website');
    if (detail.hasOpeningHours === true)
        outcome.fieldsDiscovered.push('opening_hours');
    if (detail.hasPhotos === true)
        outcome.fieldsDiscovered.push('photos');
    await deps.store.updateCompanyListing({
        companyId: input.companyId,
        phone: detail.phone,
        website: detail.website,
        hasOpeningHours: detail.hasOpeningHours,
        hasPhotos: detail.hasPhotos,
    });
    const enriched = {
        ...input.company,
        phone: detail.phone ?? input.company.phone,
        website: detail.website ?? input.company.website,
        has_opening_hours: detail.hasOpeningHours,
        has_photos: detail.hasPhotos,
    };
    const rescored = (0, prospecting_scoring_js_1.scoreProspect)(signalsFromCompany(enriched), deps.settings.scoring, deps.settings.geography);
    await deps.store.saveScores({ prospectId: input.prospectId, score: rescored });
    outcome.score = rescored;
    const reachable = detail.phone !== null;
    // Complete when there is a way to reach the shop, partial when the listing
    // answered but named no number. A lead with a website and no phone is real
    // and worth showing; it is just not one an operator can open WhatsApp on.
    outcome.status = reachable ? 'COMPLETE' : 'PARTIAL';
    await deps.store.setEnrichment({
        prospectId: input.prospectId,
        status: outcome.status,
        lastEnrichedAt: deps.now(),
        hasReachableContact: reachable,
    });
    await deps.store.appendActivity({
        prospectId: input.prospectId,
        type: 'ENRICHED',
        description: outcome.fieldsDiscovered.length === 0
            ? 'A ficha do negócio não acrescentou dados.'
            : `Ficha do negócio: ${outcome.fieldsDiscovered.join(', ')}.`,
        metadata: { fields: outcome.fieldsDiscovered, score: rescored.total },
    });
    if (reachable) {
        await deps.store.setStatus({
            prospectId: input.prospectId,
            to: 'READY_TO_CONTACT',
            reason: 'Contacto público encontrado.',
        });
    }
    return outcome;
}
async function findDecisionMakers(input) {
    const { deps } = input;
    const outcome = {
        status: 'NOT_STARTED',
        contactsFound: 0,
        decisionMakersFound: 0,
        spentUsd: 0,
        refusal: null,
        errorCode: null,
        fieldsDiscovered: [],
    };
    const decision = await guardSpend({
        operation: 'FIND_DECISION_MAKERS',
        prospectId: input.prospectId,
        leadScore: input.leadScore,
        deps,
    });
    if (!decision.allowed) {
        outcome.refusal = decision.refusal;
        outcome.status =
            decision.refusal === 'BELOW_THRESHOLD' ? 'BELOW_THRESHOLD' : 'BUDGET_BLOCKED';
        await deps.store.setEnrichment({
            prospectId: input.prospectId,
            status: outcome.status,
        });
        return outcome;
    }
    await deps.store.setEnrichment({ prospectId: input.prospectId, status: 'IN_PROGRESS' });
    const chain = await (0, prospecting_providers_js_1.runChain)(deps.providers.personDiscovery, (provider) => provider.findDecisionMakers({
        companyName: input.company.name,
        domain: input.company.domain,
        providerOrgId: input.company.provider_org_id,
        titles: prospecting_providers_js_1.DECISION_MAKER_TITLES,
        limit: 5,
    }));
    outcome.spentUsd = (0, prospecting_budget_js_1.round)(outcome.spentUsd +
        await chargeAttempts({
            attempts: chain.attempts,
            operation: 'FIND_DECISION_MAKERS',
            prospectId: input.prospectId,
            deps,
        }));
    if (!chain.ok) {
        outcome.errorCode = chain.code;
        outcome.status = chain.code === 'NO_RESULT' ? 'NO_RESULT' : 'FAILED';
        await deps.store.setEnrichment({
            prospectId: input.prospectId,
            status: outcome.status,
            lastEnrichedAt: deps.now(),
        });
        return outcome;
    }
    const people = [];
    for (const found of chain.value) {
        const enriched = await enrichOnePerson({
            prospectId: input.prospectId,
            company: input.company,
            person: found.person,
            leadScore: input.leadScore,
            deps,
        });
        outcome.spentUsd = (0, prospecting_budget_js_1.round)(outcome.spentUsd + enriched.spentUsd);
        outcome.fieldsDiscovered.push(...enriched.fieldsDiscovered);
        people.push(enriched.person);
    }
    for (const person of people) {
        const isDecisionMaker = (0, prospecting_contracts_js_1.isDecisionMakerSeniority)(person.seniority);
        if (isDecisionMaker)
            outcome.decisionMakersFound++;
        outcome.contactsFound++;
        await deps.store.saveContact({
            prospectId: input.prospectId,
            person,
            isDecisionMaker,
        });
    }
    const reachable = people.some((person) => person.phone !== null ||
        (person.email !== null && (0, prospecting_contracts_js_1.isReachableEmail)(person.email_status)));
    // Partial when somebody was found but nothing could be learned about how to
    // reach them — which is a different thing from complete, and the screen says
    // so rather than presenting a name with no way to use it.
    outcome.status = outcome.decisionMakersFound === 0
        ? 'NO_RESULT'
        : reachable
            ? 'COMPLETE'
            : 'PARTIAL';
    await deps.store.setEnrichment({
        prospectId: input.prospectId,
        status: outcome.status,
        lastEnrichedAt: deps.now(),
        decisionMakerCount: outcome.decisionMakersFound,
        hasReachableContact: reachable,
    });
    if (outcome.decisionMakersFound > 0) {
        await deps.store.appendActivity({
            prospectId: input.prospectId,
            type: 'DECISION_MAKER_FOUND',
            description: `${outcome.decisionMakersFound} decisor(es) encontrado(s).`,
            metadata: { reachable, fields: outcome.fieldsDiscovered },
        });
    }
    return outcome;
}
async function enrichOnePerson(input) {
    const { deps } = input;
    const decision = await guardSpend({
        operation: 'ENRICH_PERSON',
        prospectId: input.prospectId,
        leadScore: input.leadScore,
        deps,
    });
    // The person is kept as discovery found them. Less is known about them, and
    // that is visible on the screen rather than being papered over.
    if (!decision.allowed) {
        return { person: input.person, spentUsd: 0, fieldsDiscovered: [] };
    }
    const chain = await (0, prospecting_providers_js_1.runChain)(deps.providers.personEnrichment, (provider) => provider.enrichPerson({
        providerPersonId: input.person.provider_person_id,
        firstName: input.person.first_name,
        lastName: input.person.last_name,
        companyName: input.company.name,
        domain: input.company.domain,
        linkedinUrl: input.person.linkedin_url,
    }));
    const spentUsd = await chargeAttempts({
        attempts: chain.attempts,
        operation: 'ENRICH_PERSON',
        prospectId: input.prospectId,
        deps,
    });
    if (!chain.ok)
        return { person: input.person, spentUsd, fieldsDiscovered: [] };
    // Merged field by field, and only where the enrichment actually said
    // something: a provider that returns no phone must not erase the one
    // discovery found.
    const merged = { ...input.person };
    for (const [field, value] of Object.entries(chain.value.person)) {
        if (value !== null && value !== undefined) {
            merged[field] = value;
        }
    }
    return {
        person: merged,
        spentUsd,
        fieldsDiscovered: [...chain.value.fieldsDiscovered],
    };
}
/**
 * Looks the company up on the open web, so the analysis has evidence.
 *
 * Separate from contact discovery because it answers a different question and
 * is worth doing for leads that will never yield a decision maker: what a
 * salon posts on Instagram is the personalised observation an outreach message
 * is built from, whether or not anybody's email was ever found.
 */
async function researchCompany(input) {
    const { deps } = input;
    const decision = await guardSpend({
        operation: 'RESEARCH_COMPANY',
        prospectId: input.prospectId,
        leadScore: input.leadScore,
        deps,
    });
    if (!decision.allowed) {
        return { research: null, spentUsd: 0, refusal: decision.refusal };
    }
    const chain = await (0, prospecting_providers_js_1.runChain)(deps.providers.webResearch, (provider) => provider.researchCompany({
        name: input.company.name,
        website: input.company.website,
        city: input.company.city,
        industry: input.company.industry,
    }));
    const spentUsd = await chargeAttempts({
        attempts: chain.attempts,
        operation: 'RESEARCH_COMPANY',
        prospectId: input.prospectId,
        deps,
        // Asked of the provider that answered rather than carried on the result,
        // so a provider that reports nothing needs no field on the shared type.
        reported: reportedCostFrom(deps.providers.webResearch, chain),
    });
    return {
        research: chain.ok ? chain.value : null,
        spentUsd,
        refusal: null,
    };
}
/* --------------------------------------------------------------- spending */
/**
 * The one place a paid call is admitted or refused.
 *
 * Every provider call in this file goes through it, and it reads the stored
 * spend rather than a number passed down from the caller — so a job that has
 * been running for ten minutes is measured against what it has actually spent
 * in those ten minutes, not against what was true when it started.
 */
async function guardSpend(input) {
    const spend = await input.deps.store.readSpend(input.prospectId);
    return (0, prospecting_budget_js_1.evaluateSpend)({
        operation: input.operation,
        leadScore: input.leadScore,
        spentThisMonthUsd: spend.monthUsd,
        spentTodayUsd: spend.dayUsd,
        spentOnLeadUsd: spend.leadUsd,
        settings: input.deps.settings,
        estimatedCostUsd: input.estimatedCostUsd,
    });
}
function reportedCostFrom(providers, chain) {
    if (!chain.ok || chain.provider === undefined)
        return null;
    const answered = providers.find((provider) => provider.key === chain.provider);
    if (answered === undefined)
        return null;
    // A provider with no opinion about its own price is billed at the table
    // rate, and its row says so.
    if (answered.lastCostUsd === undefined && answered.estimatedCostUsd === undefined) {
        return null;
    }
    return {
        provider: answered.key,
        actualCostUsd: answered.lastCostUsd ?? null,
        ...(answered.estimatedCostUsd !== undefined
            ? { estimatedCostUsd: answered.estimatedCostUsd() }
            : {}),
    };
}
async function chargeAttempts(input) {
    let spent = 0;
    const tableCost = prospecting_config_js_1.OPERATION_COST_USD[input.operation];
    for (const attempt of input.attempts) {
        // Nothing is charged for a provider that refused before calling out.
        if (attempt.code === 'NOT_CONFIGURED')
            continue;
        const reported = input.reported !== null &&
            input.reported !== undefined &&
            input.reported.provider === attempt.provider
            ? input.reported
            : null;
        const estimatedCostUsd = reported?.estimatedCostUsd ?? tableCost;
        const actualCostUsd = reported === null ? null : reported.actualCostUsd;
        await input.deps.store.recordUsage({
            provider: attempt.provider,
            operation: input.operation,
            prospectId: input.prospectId,
            estimatedCostUsd,
            actualCostUsd,
            success: attempt.ok,
            errorCode: attempt.code,
        });
        // The month advances by what was actually charged where that is known,
        // and by the estimate everywhere else.
        spent = (0, prospecting_budget_js_1.round)(spent + (actualCostUsd ?? estimatedCostUsd));
    }
    return spent;
}
