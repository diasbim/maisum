/**
 * The API failure type and the sentences an operator reads when it happens.
 *
 * Kept apart from `admin-api.ts` because that module is `server-only` and
 * reaches for firebase-admin on import. Neither of the things here needs any of
 * that, and separating them is what lets the wording be tested directly rather
 * than only through a running server.
 */

export class AdminApiError extends Error {
  constructor(
    readonly status: number,
    readonly path: string,
    message: string,
  ) {
    super(message);
    this.name = 'AdminApiError';
  }

  /** The caller is signed in but the API rejected the claim. */
  get isForbidden(): boolean {
    return this.status === 401 || this.status === 403;
  }
}

/**
 * A Portuguese sentence for a status the API did not explain itself.
 *
 * The status code and path are logged, not shown: "A API respondeu 409" tells
 * an operator nothing they can act on, and the number is only useful next to
 * the server log it came from.
 */
export function statusMessage(status: number): string {
  if (status === 404) return 'Não foi encontrado. Confirme os dados indicados.';
  if (status === 409) {
    return 'Este registo entra em conflito com outro já existente.';
  }
  if (status === 422 || status === 400) {
    return 'Os dados enviados não foram aceites. Reveja os campos.';
  }
  if (status === 429) {
    return 'Demasiados pedidos seguidos. Aguarde e tente de novo.';
  }
  if (status >= 500) {
    return 'A API de administração falhou. Tente de novo dentro de momentos.';
  }
  return 'O pedido não foi concluído. Tente de novo.';
}
