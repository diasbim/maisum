'use client';

import { useState } from 'react';

import { startSearchAction } from '@/lib/prospecting-actions';
import {
  estimateSearch,
  formatUsd,
  formatUsdRange,
  type EstimateUnits,
} from '@/lib/prospecting-form';
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
  verified: boolean;
  budget: string;
  remaining: string;
  /** The inputs the estimate is computed from. Never a precomputed answer. */
  units: EstimateUnits;
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
  // The two fields the cost depends on are held here so the figure below the
  // form moves with them. Everything else stays uncontrolled — the form posts
  // to a server action, and React state for fields nothing reads would be
  // machinery for its own sake.
  const [maxLeads, setMaxLeads] = useState(
    String(maxLeadsOptions.includes(100) ? 100 : (maxLeadsOptions[0] ?? 100)),
  );
  const [minScore, setMinScore] = useState(
    String(minScoreOptions.includes(60) ? 60 : (minScoreOptions[0] ?? 60)),
  );

  const computed =
    estimate === null
      ? null
      : estimateSearch(Number(maxLeads), Number(minScore), estimate.units);

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
          defaultValue={maxLeads}
          onChange={(event) => setMaxLeads(event.target.value)}
          options={maxLeadsOptions.map((value) => ({
            value: String(value),
            label: `${value} negócios`,
          }))}
        />

        <Select
          name="minScore"
          label="Pontuação mínima para enriquecer"
          defaultValue={minScore}
          onChange={(event) => setMinScore(event.target.value)}
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
        // `aria-live` because the figure changes without the region appearing
        // or disappearing: a sighted operator sees it move when they change
        // the size of the search, and everyone else is told.
        <div
          aria-live="polite"
          className="notice"
          role="status"
          style={{ gridColumn: '1 / -1' }}
        >
          <span className="notice__mark" aria-hidden>
            $
          </span>
          <span>
            Custo estimado para {maxLeads} negócios:{' '}
            <strong>{formatUsdRange(computed!.minUsd, computed!.maxUsd)}</strong>,
            provavelmente à volta de {formatUsd(computed!.likelyUsd)} — assumindo
            que {Math.round(computed!.assumedQualifyRate * 100)}% passam os{' '}
            {minScore} pontos.{' '}
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
