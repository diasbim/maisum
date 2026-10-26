import {
  assertCompanySane,
  assertNoFabrication,
  ProviderError,
  seniorityFromTitle,
  type BusinessDiscoveryProvider,
  type BusinessDiscoveryResult,
  type BusinessSearchCriteria,
  type CompanyEnrichmentInput,
  type CompanyEnrichmentProvider,
  type CompanyEnrichmentResult,
  type CompanyRecord,
  type CompanyResearchInput,
  type CompanyResearchResult,
  type DecisionMakerSearchInput,
  type PersonDiscoveryProvider,
  type PersonDiscoveryResult,
  type PersonEnrichmentInput,
  type PersonEnrichmentProvider,
  type PersonEnrichmentResult,
  type PersonRecord,
  type WebResearchProvider,
} from './prospecting_providers.js';
import type { ProviderOperation } from './prospecting_contracts.js';

/**
 * Two providers that never call anything.
 *
 * `NotConfiguredProvider` is what an unverified integration ships as. The
 * brief's rule is that an adapter is not written against an API that has not
 * been verified against documentation or a captured response, and AIsa has
 * neither — no documentation was supplied, no credentials exist, and nothing
 * in this repository has ever called it. So it implements all five interfaces
 * and refuses every call with `NOT_CONFIGURED`, which the chain treats as
 * "skip to the next provider". The alternative — an adapter written against a
 * guessed request shape — would look finished, pass its own mocked tests, and
 * fail the first time it met the real service.
 *
 * `FixtureProvider` is the development and test backend. Its data is
 * deliberately, visibly fictional: every domain is under `.test`, which
 * RFC 2606 reserves precisely so it can never resolve, and every phone number
 * is in a block that is not issued. Nothing here is the contact detail of a
 * real person or a real business in Maputo, and nothing here may become one.
 */

/* ------------------------------------------------------- not configured */

export class NotConfiguredProvider
  implements
    BusinessDiscoveryProvider,
    CompanyEnrichmentProvider,
    PersonDiscoveryProvider,
    PersonEnrichmentProvider,
    WebResearchProvider
{
  readonly key: string;

  constructor(key: string) {
    this.key = key;
  }

  isConfigured(): boolean {
    return false;
  }

  private refuse(operation: ProviderOperation): never {
    throw new ProviderError({
      code: 'NOT_CONFIGURED',
      provider: this.key,
      operation,
      detail: 'no verified API contract and no credentials',
    });
  }

  async searchBusinesses(): Promise<BusinessDiscoveryResult[]> {
    this.refuse('SEARCH_BUSINESSES');
  }

  async enrichCompany(): Promise<CompanyEnrichmentResult> {
    this.refuse('ENRICH_COMPANY');
  }

  async findDecisionMakers(): Promise<PersonDiscoveryResult[]> {
    this.refuse('FIND_DECISION_MAKERS');
  }

  async enrichPerson(): Promise<PersonEnrichmentResult> {
    this.refuse('ENRICH_PERSON');
  }

  async researchCompany(): Promise<CompanyResearchResult> {
    this.refuse('RESEARCH_COMPANY');
  }
}

/* ------------------------------------------------------------- fixtures */

/**
 * A company as a fixture states it.
 *
 * The shape is the internal model minus the fields the source fills in, so a
 * fixture cannot accidentally declare a `source` that disagrees with the
 * provider that served it.
 */
/**
 * The listing fields a fixture may state, and usually does not.
 *
 * Optional rather than required, and defaulted to null by `toCompany`. Twenty
 * fixtures spelling out five nulls each would be a hundred lines saying
 * nothing, and the point of the set is the fields that *differ* — a fixture
 * carries a rating when the case under test is about ratings, and stays silent
 * otherwise. Silence maps to null, which is "not known", which is what a
 * fixture that never looked at a listing should say.
 */
type ListingFields =
  | 'rating'
  | 'review_count'
  | 'has_opening_hours'
  | 'has_photos'
  | 'business_status'
  // Optional here, unlike on the record: a fixture exists to exercise the
  // pipeline, and most of these predate deduplication and have no coordinates
  // to give. The ones written for the dedup tests state theirs.
  | 'latitude'
  | 'longitude';

export type CompanyFixture = Omit<
  CompanyRecord,
  'source' | 'source_reference' | ListingFields
> &
  Partial<Pick<CompanyRecord, ListingFields>>;

export type PersonFixture = PersonRecord & {
  /** Which fixture company this person belongs to. */
  orgId: string;
};

/**
 * Twenty businesses, seven trades, two cities.
 *
 * The spread is deliberate rather than uniform: some have a website and no
 * social, some the reverse, several have neither, employee counts are missing
 * on a third of them, and two sit outside the target geography so the
 * qualifier has something to refuse. A fixture set where every record is
 * complete tests nothing — the module's entire difficulty is partial data.
 */
export const COMPANY_FIXTURES: readonly CompanyFixture[] = [
  {
    name: 'Barbearia Exemplo Central',
    legal_name: 'Barbearia Exemplo Central, Lda',
    domain: 'barbearia-exemplo.test',
    website: 'https://barbearia-exemplo.test',
    industry: 'barbershop',
    industry_raw: 'Barbearia',
    employee_count: 6,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: 'Av. Exemplo 100, Maputo',
    phone: '+258840000101',
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/barbearia_exemplo_test',
    facebook_url: 'https://facebook.com/barbeariaexemplotest',
    whatsapp: '+258840000101',
    // The complete lead: everything a listing can say, said. This is the
    // fixture that proves the table still reaches 100, so changing it changes
    // the ceiling test in `prospecting_scoring.test.ts`.
    rating: 4.6,
    review_count: 87,
    has_opening_hours: true,
    has_photos: true,
    business_status: 'OPERATIONAL',
    provider_org_id: 'fx-org-001',
  },
  {
    name: 'Salão Exemplo Beleza',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'salon',
    industry_raw: 'Salão de beleza',
    employee_count: 4,
    city: 'Matola',
    province: 'Maputo',
    address: 'Rua de Exemplo 12, Matola',
    country: 'Moçambique',
    phone: '+258840000102',
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/salao_exemplo_test',
    facebook_url: null,
    whatsapp: '+258840000102',
    provider_org_id: 'fx-org-002',
  },
  {
    name: 'Spa Exemplo Bem-Estar',
    legal_name: 'Spa Exemplo, SA',
    domain: 'spa-exemplo.test',
    website: 'https://spa-exemplo.test',
    industry: 'spa',
    industry_raw: 'Spa',
    employee_count: 12,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: 'Av. Exemplo 300, Maputo',
    phone: '+258210000103',
    email: null,
    linkedin_url: 'https://linkedin.com/company/spa-exemplo-test',
    instagram_url: 'https://instagram.com/spa_exemplo_test',
    facebook_url: null,
    whatsapp: null,
    // Well rated and barely reviewed: clears the rating criterion, misses both
    // review thresholds. The pair exists to prove the two are scored
    // separately — quality and traffic are different questions.
    rating: 4.8,
    review_count: 4,
    has_opening_hours: true,
    has_photos: false,
    business_status: 'OPERATIONAL',
    provider_org_id: 'fx-org-003',
  },
  {
    name: 'Ginásio Exemplo Forma',
    legal_name: null,
    domain: 'ginasio-exemplo.test',
    website: 'https://ginasio-exemplo.test',
    industry: 'gym',
    industry_raw: 'Ginásio',
    employee_count: 18,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: null,
    phone: '+258840000104',
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/ginasio_exemplo_test',
    facebook_url: 'https://facebook.com/ginasioexemplotest',
    whatsapp: '+258840000104',
    provider_org_id: 'fx-org-004',
  },
  {
    name: 'Lavagem Auto Exemplo',
    legal_name: 'Lavagem Auto Exemplo EI',
    domain: null,
    website: null,
    industry: 'car_wash',
    industry_raw: 'Lavagem automóvel',
    employee_count: null,
    city: 'Matola',
    province: 'Maputo',
    country: 'Moçambique',
    address: 'Estrada de Exemplo, Matola',
    phone: '+258840000105',
    email: null,
    linkedin_url: null,
    instagram_url: null,
    facebook_url: 'https://facebook.com/lavagemexemplotest',
    whatsapp: '+258840000105',
    provider_org_id: 'fx-org-005',
  },
  {
    name: 'Restaurante Exemplo Sabor',
    legal_name: null,
    domain: 'restaurante-exemplo.test',
    website: 'https://restaurante-exemplo.test',
    industry: 'restaurant',
    industry_raw: 'Restaurante',
    employee_count: 22,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: 'Av. Exemplo 55, Maputo',
    phone: '+258210000106',
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/restaurante_exemplo_test',
    facebook_url: 'https://facebook.com/restauranteexemplotest',
    whatsapp: null,
    provider_org_id: 'fx-org-006',
  },
  {
    name: 'Café Exemplo Aroma',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'cafe',
    industry_raw: 'Café',
    employee_count: 5,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: null,
    phone: null,
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/cafe_exemplo_test',
    facebook_url: null,
    whatsapp: null,
    provider_org_id: 'fx-org-007',
  },
  {
    name: 'Barbearia Exemplo Matola',
    legal_name: null,
    domain: 'barbearia-matola-exemplo.test',
    website: 'https://www.barbearia-matola-exemplo.test/',
    industry: 'barbershop',
    industry_raw: 'Barbearia',
    employee_count: 3,
    city: 'Matola',
    province: 'Maputo',
    country: 'Moçambique',
    address: null,
    phone: '+258840000108',
    email: null,
    linkedin_url: null,
    instagram_url: null,
    facebook_url: null,
    whatsapp: '+258840000108',
    // Busy and mediocre, and temporarily shut. Scored rather than discarded:
    // a shop that reopens is still a lead, and `operationalFrom` reads this
    // exact string as false rather than as unknown.
    rating: 3.4,
    review_count: 41,
    has_opening_hours: false,
    has_photos: true,
    business_status: 'CLOSED_TEMPORARILY',
    provider_org_id: 'fx-org-008',
  },
  {
    name: 'Salão Exemplo Estilo',
    legal_name: 'Salão Exemplo Estilo Lda',
    domain: null,
    website: null,
    industry: 'salon',
    industry_raw: 'Cabeleireiro',
    employee_count: 8,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: 'Rua Exemplo 7, Maputo',
    phone: '+258840000109',
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/salao_estilo_exemplo_test',
    facebook_url: 'https://facebook.com/salaoestiloexemplotest',
    whatsapp: '+258840000109',
    provider_org_id: 'fx-org-009',
  },
  {
    name: 'Clínica Exemplo Estética',
    legal_name: null,
    domain: 'clinica-exemplo.test',
    website: 'https://clinica-exemplo.test',
    industry: 'spa',
    industry_raw: 'Clínica de estética',
    employee_count: 15,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: null,
    phone: '+258210000110',
    email: null,
    linkedin_url: 'https://linkedin.com/company/clinica-exemplo-test',
    instagram_url: null,
    facebook_url: null,
    whatsapp: null,
    provider_org_id: 'fx-org-010',
  },
  {
    name: 'Ginásio Exemplo Matola',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'gym',
    industry_raw: 'Academia',
    employee_count: null,
    city: 'Matola',
    province: 'Maputo',
    country: 'Moçambique',
    address: null,
    phone: '+258840000111',
    email: null,
    linkedin_url: null,
    instagram_url: null,
    facebook_url: 'https://facebook.com/ginasiomatolaexemplotest',
    whatsapp: '+258840000111',
    provider_org_id: 'fx-org-011',
  },
  {
    name: 'Café Exemplo Matola',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'cafe',
    industry_raw: 'Pastelaria',
    employee_count: 7,
    city: 'Matola',
    province: 'Maputo',
    country: 'Moçambique',
    address: null,
    phone: '+258840000112',
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/cafe_matola_exemplo_test',
    facebook_url: null,
    whatsapp: '+258840000112',
    provider_org_id: 'fx-org-012',
  },
  {
    name: 'Lavagem Exemplo Rápida',
    legal_name: null,
    domain: 'lavagem-exemplo.test',
    website: 'https://lavagem-exemplo.test',
    industry: 'car_wash',
    industry_raw: 'Car wash',
    employee_count: 9,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: null,
    phone: '+258840000113',
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/lavagem_exemplo_test',
    facebook_url: 'https://facebook.com/lavagemrapidaexemplotest',
    whatsapp: '+258840000113',
    provider_org_id: 'fx-org-013',
  },
  {
    name: 'Restaurante Exemplo Matola',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'restaurant',
    industry_raw: 'Restaurante',
    employee_count: 30,
    city: 'Matola',
    province: 'Maputo',
    country: 'Moçambique',
    address: null,
    phone: '+258840000114',
    email: null,
    linkedin_url: null,
    instagram_url: null,
    facebook_url: 'https://facebook.com/restaurantematolaexemplotest',
    whatsapp: null,
    provider_org_id: 'fx-org-014',
  },
  {
    name: 'Barbearia Exemplo Bairro',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'barbershop',
    industry_raw: 'Barbearia',
    employee_count: 2,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: null,
    phone: null,
    email: null,
    linkedin_url: null,
    instagram_url: null,
    facebook_url: null,
    whatsapp: null,
    provider_org_id: 'fx-org-015',
  },
  {
    name: 'Spa Exemplo Matola',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'spa',
    industry_raw: 'Spa',
    employee_count: 6,
    city: 'Matola',
    province: 'Maputo',
    country: 'Moçambique',
    address: null,
    phone: '+258840000116',
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/spa_matola_exemplo_test',
    facebook_url: null,
    whatsapp: '+258840000116',
    provider_org_id: 'fx-org-016',
  },
  {
    name: 'Salão Exemplo Nova Imagem',
    legal_name: null,
    domain: 'nova-imagem-exemplo.test',
    website: 'https://nova-imagem-exemplo.test',
    industry: 'salon',
    industry_raw: 'Salão',
    employee_count: 11,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: null,
    phone: '+258840000117',
    email: null,
    linkedin_url: null,
    instagram_url: 'https://instagram.com/nova_imagem_exemplo_test',
    facebook_url: 'https://facebook.com/novaimagemexemplotest',
    whatsapp: '+258840000117',
    provider_org_id: 'fx-org-017',
  },
  {
    name: 'Oficina Exemplo Motor',
    legal_name: null,
    domain: null,
    website: null,
    // Outside the ICP: the qualifier must refuse this one on the trade.
    industry: 'workshop',
    industry_raw: 'Oficina',
    employee_count: 14,
    city: 'Maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: null,
    phone: '+258840000118',
    email: null,
    linkedin_url: null,
    instagram_url: null,
    facebook_url: null,
    whatsapp: null,
    provider_org_id: 'fx-org-018',
  },
  {
    name: 'Barbearia Exemplo Beira',
    legal_name: null,
    domain: null,
    website: null,
    industry: 'barbershop',
    industry_raw: 'Barbearia',
    employee_count: 5,
    // Outside the default target geography: the qualifier must refuse it on
    // the city, and must stop refusing it the day Beira is added to settings.
    city: 'Beira',
    province: 'Sofala',
    country: 'Moçambique',
    address: null,
    phone: '+258840000119',
    email: null,
    linkedin_url: null,
    instagram_url: null,
    facebook_url: null,
    whatsapp: '+258840000119',
    provider_org_id: 'fx-org-019',
  },
  {
    name: 'Barbearia Exemplo Central',
    legal_name: 'Barbearia Exemplo Central Lda',
    // The same business as fixture 001, written the way a second provider
    // would write it: a scheme and a www the first one did not have, the legal
    // suffix attached, the phone spaced out. Deduplication must fold these two
    // onto one company, and `prospecting_dedup.test.ts` asserts that it does.
    domain: null,
    website: 'http://www.Barbearia-Exemplo.test/contactos?utm_source=ig',
    industry: 'barbershop',
    industry_raw: 'Barbearia',
    employee_count: 6,
    city: 'maputo',
    province: 'Maputo Cidade',
    country: 'Moçambique',
    address: null,
    phone: '+258 84 000 0101',
    email: null,
    linkedin_url: null,
    instagram_url: null,
    facebook_url: null,
    whatsapp: null,
    provider_org_id: 'fx-org-020',
  },
];

/**
 * Ten decision makers, across nine of the twenty companies.
 *
 * Nine, not twenty, because the point of the fixture set is that most
 * businesses do not yield a decision maker on the first attempt — the
 * `NO_CONTACT` path and the "no decision maker found" empty state are the ones
 * an operator will meet most often, and a fixture set that always succeeds
 * would leave both untested.
 *
 * Every person here is invented. The names are common Mozambican given names
 * attached to fictional businesses, the emails are all under `.test`, and no
 * row corresponds to a real person.
 */
export const PERSON_FIXTURES: readonly PersonFixture[] = [
  {
    orgId: 'fx-org-001',
    first_name: 'Arlindo',
    last_name: 'Exemplo',
    job_title: 'Proprietário',
    seniority: 'OWNER',
    email: 'arlindo@barbearia-exemplo.test',
    email_status: 'VERIFIED',
    phone: '+258840000201',
    linkedin_url: null,
    provider_person_id: 'fx-per-001',
    confidence_score: 0.9,
  },
  {
    orgId: 'fx-org-003',
    first_name: 'Célia',
    last_name: 'Exemplo',
    job_title: 'Directora Geral',
    seniority: 'DIRECTOR',
    email: 'celia@spa-exemplo.test',
    email_status: 'VERIFIED',
    phone: null,
    linkedin_url: 'https://linkedin.com/in/celia-exemplo-test',
    provider_person_id: 'fx-per-002',
    confidence_score: 0.85,
  },
  {
    orgId: 'fx-org-004',
    first_name: 'Nelson',
    last_name: null,
    job_title: 'Gerente',
    seniority: 'MANAGER',
    // Pattern-built by the provider and never checked. It is stored, it is
    // labelled, and it does not earn the "reachable contact" point.
    email: 'nelson@ginasio-exemplo.test',
    email_status: 'GUESSED',
    phone: null,
    linkedin_url: null,
    provider_person_id: 'fx-per-003',
    confidence_score: 0.4,
  },
  {
    orgId: 'fx-org-006',
    first_name: 'Inês',
    last_name: 'Exemplo',
    job_title: 'Fundadora',
    seniority: 'FOUNDER',
    email: 'ines@restaurante-exemplo.test',
    email_status: 'VERIFIED',
    phone: '+258840000204',
    linkedin_url: null,
    provider_person_id: 'fx-per-004',
    confidence_score: 0.92,
  },
  {
    orgId: 'fx-org-009',
    first_name: 'Ramos',
    last_name: null,
    job_title: 'Proprietário',
    seniority: 'OWNER',
    email: null,
    email_status: 'UNKNOWN',
    phone: '+258840000205',
    linkedin_url: null,
    provider_person_id: 'fx-per-005',
    confidence_score: 0.7,
  },
  {
    orgId: 'fx-org-010',
    first_name: 'Dulce',
    last_name: 'Exemplo',
    job_title: 'CEO',
    seniority: 'C_LEVEL',
    email: 'dulce@clinica-exemplo.test',
    email_status: 'VERIFIED',
    phone: null,
    linkedin_url: 'https://linkedin.com/in/dulce-exemplo-test',
    provider_person_id: 'fx-per-006',
    confidence_score: 0.88,
  },
  {
    orgId: 'fx-org-013',
    first_name: 'Hélder',
    last_name: null,
    job_title: 'Gerente Geral',
    seniority: 'MANAGER',
    email: null,
    email_status: 'UNKNOWN',
    phone: '+258840000207',
    linkedin_url: null,
    provider_person_id: 'fx-per-007',
    confidence_score: 0.55,
  },
  {
    orgId: 'fx-org-017',
    first_name: 'Telma',
    last_name: 'Exemplo',
    job_title: 'Proprietária',
    seniority: 'OWNER',
    email: 'telma@nova-imagem-exemplo.test',
    email_status: 'VERIFIED',
    phone: '+258840000208',
    linkedin_url: null,
    provider_person_id: 'fx-per-008',
    confidence_score: 0.95,
  },
  {
    orgId: 'fx-org-002',
    first_name: 'Anabela',
    last_name: null,
    job_title: 'Atendimento',
    // Stored, but not a decision maker: the UI must not offer her as the
    // person to pitch, and the commercial-opportunity point is not earned.
    seniority: 'STAFF',
    email: null,
    email_status: 'UNKNOWN',
    phone: '+258840000209',
    linkedin_url: null,
    provider_person_id: 'fx-per-009',
    confidence_score: 0.3,
  },
  {
    orgId: 'fx-org-008',
    first_name: 'Jorge',
    last_name: 'Exemplo',
    job_title: 'Dono',
    seniority: 'OWNER',
    email: null,
    email_status: 'UNKNOWN',
    phone: '+258840000210',
    linkedin_url: null,
    provider_person_id: 'fx-per-010',
    confidence_score: 0.8,
  },
];

/**
 * What the research provider says about a fixture company.
 *
 * Keyed by org id, and deliberately absent for most of them: a company with no
 * entry gets `null` for every observation rather than `false`, which is what
 * drives the `UNKNOWN` criteria in the scorer and the unknowns list in the UI.
 */
const RESEARCH_FIXTURES: Record<
  string,
  Pick<CompanyResearchResult, 'runs_promotions' | 'growth_signal' | 'findings' | 'unknowns'>
> = {
  'fx-org-001': {
    runs_promotions: true,
    growth_signal: true,
    findings: [
      {
        claim: 'Publica promoções de corte + barba no Instagram',
        type: 'FACT',
        source: 'https://instagram.com/barbearia_exemplo_test',
      },
      {
        claim: 'Anunciou vaga para um segundo barbeiro',
        type: 'FACT',
        source: 'https://barbearia-exemplo.test/vagas',
      },
      {
        claim: 'Clientes parecem voltar mensalmente',
        type: 'INFERENCE',
        source: 'https://instagram.com/barbearia_exemplo_test',
      },
    ],
    unknowns: ['Número de clientes', 'Sistema de gestão usado'],
  },
  'fx-org-003': {
    runs_promotions: true,
    growth_signal: null,
    findings: [
      {
        claim: 'Oferece pacotes de várias sessões',
        type: 'FACT',
        source: 'https://spa-exemplo.test/pacotes',
      },
    ],
    unknowns: ['Crescimento', 'Número de clientes'],
  },
  'fx-org-006': {
    runs_promotions: false,
    growth_signal: true,
    findings: [
      {
        claim: 'Abriu uma segunda sala em 2026',
        type: 'FACT',
        source: 'https://restaurante-exemplo.test/sobre',
      },
    ],
    unknowns: ['Promoções', 'Programa de fidelização'],
  },
  'fx-org-017': {
    runs_promotions: true,
    growth_signal: null,
    findings: [
      {
        claim: 'Publica descontos semanais',
        type: 'FACT',
        source: 'https://instagram.com/nova_imagem_exemplo_test',
      },
    ],
    unknowns: ['Crescimento'],
  },
};

/* ---------------------------------------------------------- the provider */

export type FixtureProviderOptions = {
  /** Fails every call with this code. For exercising the fallback chain. */
  failWith?: import('./prospecting_contracts.js').ProviderErrorCode;
  /** Returns no results rather than data. For the empty-state paths. */
  empty?: boolean;
  /** Overrides the fixture set, so a test can supply its own two companies. */
  companies?: readonly CompanyFixture[];
  people?: readonly PersonFixture[];
  key?: string;
};

export class FixtureProvider
  implements
    BusinessDiscoveryProvider,
    CompanyEnrichmentProvider,
    PersonDiscoveryProvider,
    PersonEnrichmentProvider,
    WebResearchProvider
{
  readonly key: string;
  private readonly options: FixtureProviderOptions;
  private readonly companies: readonly CompanyFixture[];
  private readonly people: readonly PersonFixture[];

  constructor(options: FixtureProviderOptions = {}) {
    this.options = options;
    this.key = options.key ?? 'fixtures';
    this.companies = options.companies ?? COMPANY_FIXTURES;
    this.people = options.people ?? PERSON_FIXTURES;
  }

  isConfigured(): boolean {
    return true;
  }

  private guard(operation: ProviderOperation): void {
    if (this.options.failWith !== undefined) {
      throw new ProviderError({
        code: this.options.failWith,
        provider: this.key,
        operation,
        detail: 'fixture provider configured to fail',
      });
    }
  }

  private toCompany(fixture: CompanyFixture): CompanyRecord {
    return assertCompanySane(
      {
        ...fixture,
        // Unstated is unknown. `?? null` and not a default of `false` or `0`:
        // a fixture that says nothing about photos has not said there are
        // none, and the scoring engine reads the difference.
        rating: fixture.rating ?? null,
        review_count: fixture.review_count ?? null,
        has_opening_hours: fixture.has_opening_hours ?? null,
        has_photos: fixture.has_photos ?? null,
        business_status: fixture.business_status ?? null,
        latitude: fixture.latitude ?? null,
        longitude: fixture.longitude ?? null,
        source: this.key,
        source_reference: fixture.provider_org_id,
      },
      this.key,
      'SEARCH_BUSINESSES',
    );
  }

  async searchBusinesses(
    criteria: BusinessSearchCriteria,
  ): Promise<BusinessDiscoveryResult[]> {
    this.guard('SEARCH_BUSINESSES');
    if (this.options.empty === true) return [];

    const wanted = new Set(criteria.industries.map((value) => value.trim().toLowerCase()));
    const matches = this.companies.filter((fixture) => {
      if (wanted.size > 0 && (fixture.industry === null || !wanted.has(fixture.industry))) {
        return false;
      }
      if (
        criteria.employeeMin !== null &&
        fixture.employee_count !== null &&
        fixture.employee_count < criteria.employeeMin
      ) {
        return false;
      }
      if (
        criteria.employeeMax !== null &&
        fixture.employee_count !== null &&
        fixture.employee_count > criteria.employeeMax
      ) {
        return false;
      }
      return true;
    });

    // The cursor is the index of the next unread fixture, which is the
    // simplest thing that behaves like a real cursor: opaque to the caller,
    // and correct across a page boundary.
    const start = criteria.cursor === null ? 0 : Number.parseInt(criteria.cursor, 10) || 0;
    const page = matches.slice(start, start + Math.max(1, criteria.limit));
    const nextStart = start + page.length;

    return page.map((fixture, index) => ({
      company: this.toCompany(fixture),
      cursor:
        index === page.length - 1 && nextStart < matches.length
          ? String(nextStart)
          : null,
    }));
  }

  async enrichCompany(
    input: CompanyEnrichmentInput,
  ): Promise<CompanyEnrichmentResult> {
    this.guard('ENRICH_COMPANY');

    const fixture =
      this.companies.find((entry) => entry.provider_org_id === input.providerOrgId) ??
      this.companies.find(
        (entry) => entry.name.toLowerCase() === input.name.toLowerCase(),
      );

    if (fixture === undefined || this.options.empty === true) {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'ENRICH_COMPANY',
      });
    }

    return {
      company: {
        employee_count: fixture.employee_count,
        linkedin_url: fixture.linkedin_url,
        industry: fixture.industry,
        address: fixture.address,
      },
      fieldsDiscovered: ['employee_count', 'linkedin_url', 'industry', 'address'].filter(
        (field) => fixture[field as keyof CompanyFixture] !== null,
      ),
    };
  }

  async findDecisionMakers(
    input: DecisionMakerSearchInput,
  ): Promise<PersonDiscoveryResult[]> {
    this.guard('FIND_DECISION_MAKERS');

    const matches = this.people.filter(
      (person) => person.orgId === input.providerOrgId,
    );
    if (matches.length === 0 || this.options.empty === true) {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'FIND_DECISION_MAKERS',
      });
    }

    return matches.slice(0, Math.max(1, input.limit)).map((person) => ({
      person: assertNoFabrication(
        { ...stripFixtureFields(person) },
        this.key,
        'FIND_DECISION_MAKERS',
      ),
    }));
  }

  async enrichPerson(input: PersonEnrichmentInput): Promise<PersonEnrichmentResult> {
    this.guard('ENRICH_PERSON');

    const fixture = this.people.find(
      (person) => person.provider_person_id === input.providerPersonId,
    );
    if (fixture === undefined || this.options.empty === true) {
      throw new ProviderError({
        code: 'NO_RESULT',
        provider: this.key,
        operation: 'ENRICH_PERSON',
      });
    }

    return {
      person: {
        email: fixture.email,
        email_status: fixture.email_status,
        phone: fixture.phone,
        linkedin_url: fixture.linkedin_url,
        job_title: fixture.job_title,
      },
      fieldsDiscovered: (['email', 'phone', 'linkedin_url', 'job_title'] as const).filter(
        (field) => fixture[field] !== null,
      ),
    };
  }

  async researchCompany(
    input: CompanyResearchInput,
  ): Promise<CompanyResearchResult> {
    this.guard('RESEARCH_COMPANY');

    const fixture = this.companies.find(
      (entry) => entry.name.toLowerCase() === input.name.toLowerCase(),
    );
    const research =
      fixture !== undefined ? RESEARCH_FIXTURES[fixture.provider_org_id ?? ''] : undefined;

    const profiles =
      fixture === undefined
        ? []
        : [fixture.instagram_url, fixture.facebook_url, fixture.linkedin_url].filter(
            (value): value is string => value !== null,
          );

    return {
      findings: research?.findings ?? [],
      // A company nothing was found about gets an explicit list of what was
      // looked for and not found, rather than an empty panel.
      unknowns: research?.unknowns ?? ['Promoções', 'Crescimento', 'Número de clientes'],
      website_reachable: fixture?.website != null ? true : null,
      social_profiles: profiles,
      runs_promotions: research?.runs_promotions ?? null,
      growth_signal: research?.growth_signal ?? null,
    };
  }
}

function stripFixtureFields(fixture: PersonFixture): PersonRecord {
  const { orgId: _orgId, ...person } = fixture;
  return person;
}

/** Seniority mapping is exercised here too, so the table cannot rot unused. */
export function fixtureSeniority(title: string | null) {
  return seniorityFromTitle(title);
}
