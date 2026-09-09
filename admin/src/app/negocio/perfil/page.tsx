import { Suspense } from 'react';

import { fetchMyProfile } from '@/lib/merchant-api';
import {
  Card,
  DefinitionList,
  EmptyState,
  ErrorState,
  PageHeader,
  Panel,
  Skeleton,
  formatDateTime,
  load,
} from '../../admin/ui';

export const metadata = { title: 'Perfil do negócio | MaisUm' };
export const dynamic = 'force-dynamic';

async function ProfilePanel() {
  const result = await load(fetchMyProfile);
  if (result.error !== null) return <ErrorState message={result.error} />;

  const business = result.data;
  if (!business) {
    return (
      <EmptyState message="Ainda não há dados deste negócio. Assim que registar a primeira venda na aplicação, aparecem aqui." />
    );
  }

  return (
    <div className="split">
      <Card title="Identificação">
        <DefinitionList
          entries={[
            ['Nome', business.name ?? '—'],
            ['Telefone', business.phone ?? '—'],
            ['Identificador', <code key="id">{business.id}</code>],
            ['Registado em', formatDateTime(business.created_at)],
          ]}
        />
      </Card>

      <Card
        hint="Atualizado a partir da aplicação. Editar aqui chega numa fase seguinte."
        title="Atividade"
      >
        <DefinitionList
          entries={[
            [
              'Equipa',
              `${business.active_staff_count} ativos de ${business.staff_count}`,
            ],
            ['Última operação', formatDateTime(business.last_operational_update_at)],
            ['Última atualização', formatDateTime(business.updated_at)],
          ]}
        />
      </Card>
    </div>
  );
}

export default function MerchantProfilePage() {
  return (
    <>
      <PageHeader
        title="Perfil do negócio"
        subtitle="O que a MaisUm sabe sobre o seu negócio."
      />

      <Panel>
        <Suspense fallback={<Skeleton lines={5} />}>
          <ProfilePanel />
        </Suspense>
      </Panel>
    </>
  );
}
