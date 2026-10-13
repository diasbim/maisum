import Link from 'next/link';

/**
 * Inside the business shell, not Next's default page.
 *
 * A missing customer is a dead end reached from a real list, so the way back
 * to that list is the point of the screen.
 */
export default function MerchantNotFound() {
  return (
    <div className="card" style={{ maxWidth: 620 }}>
      <p className="card__title">Não encontrado</p>
      <p className="card__hint">
        Este registo não existe, ou o endereço está incorreto. Se veio de uma
        ligação antiga, pode ter sido removido entretanto.
      </p>
      <div className="form-actions">
        <Link className="btn btn-navy" href="/negocio">
          Voltar ao início
        </Link>
        <Link className="btn btn-outline" href="/negocio/clientes">
          Ver clientes
        </Link>
      </div>
    </div>
  );
}
