'use client';

import { startSearchAction } from '@/lib/prospecting-actions';
import { ActionForm, Field, Select } from '../forms';

/**
 * The Find Leads form.
 *
 * A client component only because the industry checkboxes are a genuine
 * multi-select and the estimate has to move when the size of the search does.
 * It still submits to a server action — nothing here calls the API, and the
 * ID token stays in the cookie, like everywhere else in this portal.
 *
 * The estimate is rendered above the button rather than beside it. An operator
 * about to spend money should meet the number on the way to the control, not
 * next to it where it can be missed.
 */

export type EstimateSummary = {
  range: string;
  likely: string;
  verified: boolean;
  budget: string;
  remaining: string;
};

export function FindLeadsForm({
  industries,
  sizes,
  maxLeadsOptions,
  minScoreOptions,
  cities,
  estimate,
}: {
  industries: Array<{ business_type: string; label: string; tier: number }>;
  sizes: Array<{ key: string; label: string }>;
  maxLeadsOptions: number[];
  minScoreOptions: number[];
  cities: string[];
  estimate: EstimateSummary | null;
}) {
  return (
    <ActionForm
      action={startSearchAction}
      submitLabel="Procurar negócios"
      pendingLabel="A iniciar…"
      variant="btn-navy"
      hint="A procura corre em segundo plano. Os leads aparecem na lista abaixo à medida que são encontrados."
    >
      <fieldset className="field" style={{ gridColumn: '1 / -1', border: 0, padding: 0 }}>
        <legend className="section-label">Tipo de negócio</legend>
        <p className="field__hint" id="industries-hint">
          Não escolher nenhum procura todos os setores do perfil.
        </p>
        <div className="chip-row" role="group" aria-describedby="industries-hint">
          {industries.map((industry) => (
            <label className="check" key={industry.business_type}>
              <input
                name="industries"
                type="checkbox"
                value={industry.business_type}
              />
              <span>
                {industry.label}
                <em>Tier {industry.tier}</em>
              </span>
            </label>
          ))}
        </div>
      </fieldset>

      <div className="form-grid">
        <Field
          name="city"
          label="Localização"
          hint={
            cities.length > 0
              ? `Onde a MaisUm vende hoje: ${cities.join(', ')}. Outra cidade é permitida — os resultados ficam marcados como fora da geografia-alvo.`
              : 'Cidade ou província.'
          }
          list="prospecting-cities"
          placeholder="Maputo"
        />
        <datalist id="prospecting-cities">
          {cities.map((city) => (
            <option key={city} value={city} />
          ))}
        </datalist>

        <Select
          name="size"
          label="Dimensão"
          defaultValue=""
          options={[
            { value: '', label: 'Qualquer dimensão' },
            ...sizes.map((size) => ({ value: size.key, label: size.label })),
          ]}
          hint="Um negócio cuja dimensão é desconhecida não é excluído por este filtro."
        />

        <Select
          name="maxLeads"
          label="Quantos negócios"
          defaultValue="100"
          options={maxLeadsOptions.map((value) => ({
            value: String(value),
            label: `${value} negócios`,
          }))}
        />

        <Select
          name="minScore"
          label="Pontuação mínima para enriquecer"
          defaultValue="60"
          options={minScoreOptions.map((value) => ({
            value: String(value),
            label: `${value} pontos`,
          }))}
          hint="Abaixo disto, um lead é descoberto e pontuado mas nunca é pago."
        />
      </div>

      {estimate === null ? (
        <p className="field__hint" style={{ gridColumn: '1 / -1' }}>
          Não foi possível estimar o custo. O orçamento configurado continua a
          ser o que limita o gasto.
        </p>
      ) : (
        <div className="notice" role="status" style={{ gridColumn: '1 / -1' }}>
          <span className="notice__mark" aria-hidden>
            $
          </span>
          <span>
            Custo estimado para 100 negócios: <strong>{estimate.range}</strong>,
            provavelmente à volta de {estimate.likely}.{' '}
            {estimate.verified
              ? null
              : 'Os preços unitários ainda não foram confirmados contra uma fatura, por isso trate isto como ordem de grandeza — '}
            O que limita mesmo o gasto é o orçamento: {estimate.remaining} ainda
            disponíveis de {estimate.budget} este mês.
          </span>
        </div>
      )}
    </ActionForm>
  );
}
