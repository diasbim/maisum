import Link from 'next/link';

export default function AdminNotFound() {
  return (
    <div className="card" style={{ maxWidth: 620 }}>
      <p className="card__title">Não encontrado</p>
      <p className="card__hint">
        O registo que procura não existe, ou o endereço está incorreto. Se
        seguiu uma ligação de outro sítio, o registo pode ter sido removido
        entretanto.
      </p>
      <div className="form-actions">
        <Link className="btn btn-navy" href="/admin">
          Voltar à visão geral
        </Link>
        <Link className="btn btn-outline" href="/admin/merchants">
          Procurar um negócio
        </Link>
      </div>
    </div>
  );
}
