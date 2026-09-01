'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useState } from 'react';

/**
 * Search is a URL parameter, not component state, so a filtered view is
 * linkable and survives a reload. Submitting resets the offset: staying on
 * page 3 of a different result set would show an apparently empty list.
 */
export function MerchantSearch() {
  const router = useRouter();
  const params = useSearchParams();
  const [value, setValue] = useState(params.get('search') ?? '');

  function apply(next: string) {
    const query = new URLSearchParams();
    if (next.trim()) query.set('search', next.trim());
    const qs = query.toString();
    router.push(qs ? `/admin/merchants?${qs}` : '/admin/merchants');
  }

  const current = params.get('search') ?? '';

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply(value);
      }}
      style={{ display: 'flex', gap: 8, alignItems: 'center' }}
    >
      <input
        className="input"
        type="search"
        name="search"
        placeholder="Procurar por nome, telefone ou ID"
        aria-label="Procurar negócios"
        value={value}
        onChange={(event) => setValue(event.target.value)}
        style={{ minWidth: 260 }}
      />
      <button className="btn btn-navy" type="submit">
        Procurar
      </button>
      {current ? (
        <button
          type="button"
          className="btn btn-outline"
          onClick={() => {
            setValue('');
            apply('');
          }}
        >
          Limpar
        </button>
      ) : null}
    </form>
  );
}
