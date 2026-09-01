# Cartões NFC físicos: associação e identificação

Este documento descreve o mecanismo de identificação de clientes por cartão
NFC físico, que complementa o QR code rotativo já existente
(`functions/src/customer_qr.ts`), seguindo a mesma arquitetura de identidade
canónica por telefone usada em todo o Customer Core
(`functions/src/index.ts`).

## Modelo de dados

- **Coleção Firestore `customer_nfc_cards`**: um documento por UID de
  cartão normalizado (maiúsculas, sem separadores — ver
  `functions/src/customer_nfc.ts`). Cada documento contém
  `canonical_customer_id`, `status` (`ACTIVE`/`REVOKED`), `linked_by`
  (`customer`/`merchant`/`admin`), `source`
  (`self_service`/`merchant_assisted`/`legacy_import`), `created_at` e
  `updated_at`. Um UID só pode apontar para uma identidade canónica ativa
  de cada vez.
- Reaproveita `customer_identities`, `business_customers`,
  `business_customer_identity_links` e `canonical_identity_business_links`
  tal como já existiam para telefone/QR.
- Cache local (SQLite, migração v28): coluna `nfc_card_uid` em `customers`,
  única por `merchant_id`. É apenas um atalho de leitura para
  reconhecimento rápido de toques repetidos — a autoridade é sempre o
  backend.

## Identificação do cartão

Os cartões são identificados apenas pelo **UID de fábrica** (NTAG21x /
Mifare, 4, 7 ou 10 bytes), não por um segredo gravado no cartão. Isto é
mais barato e compatível, mas o UID é clonável. A mitigação é operacional,
não criptográfica:

- Toda a associação/leitura exige autorização válida (comerciante ou
  cliente autenticado) revalidada em cada chamada.
- Toda a mutação é auditada (`functions/src/customer_nfc.ts:logCustomerNfcEvent`).
- Um cartão pode ser revogado e reassociado a qualquer momento.

## Endpoints (Cloud Functions)

| Rota | Quem chama | Efeito |
| --- | --- | --- |
| `POST /customer/nfc-cards/link` | Cliente autenticado | Associa um UID à sua própria identidade canónica. |
| `POST /customer/nfc-cards/revoke` | Cliente autenticado | Revoga um cartão que associou. |
| `POST /merchant/customer-nfc/link` | Comerciante | Associação assistida: liga um UID a um cliente existente (por `customer_id` ou `phone`) ou cria um cliente novo. |
| `POST /merchant/customer-nfc/resolve` | Comerciante | Lê um UID e devolve o cliente do comerciante associado, criando o registo de cliente no primeiro toque se `create_customer_if_missing` (default `true`). |
| `POST /merchant/customer-nfc/revoke` | Comerciante | Revoga um cartão associado a um dos seus próprios clientes. |
| `POST /admin/customer-core/nfc-cards/backfill` | Admin (chave de serviço) | Importação idempotente de associações legadas — ver secção seguinte. |

Todas as rotas exigem a feature flag `CUSTOMER_NFC_ENABLED=true` (ver
`functions/src/customer_feature_flags.ts`), seguindo o mesmo padrão de
rollout do QR (`CUSTOMER_QR_ENABLED`).

## Importação de associações legadas

A origem exata dos dados do "app antigo" (cartão físico ↔ cliente) ainda
não foi confirmada com a equipa. O endpoint de backfill foi desenhado para
ser genérico e não depende desse esquema:

```
POST /admin/customer-core/nfc-cards/backfill
{
  "dry_run": false,
  "items": [
    { "card_uid": "04A22C9B", "phone": "841234567", "merchant_id": "biz_1", "customer_name": "Ana" },
    { "card_uid": "0B44FF10", "phone": "829876543" }
  ]
}
```

- `card_uid` e `phone` são obrigatórios por item; `merchant_id` e
  `customer_name` são opcionais.
- Se `merchant_id` for indicado, o cartão fica também ligado ao cliente
  desse comerciante (preservando ou criando o histórico existente).
  Sem `merchant_id`, só a identidade canónica é criada/atualizada — útil
  quando o cartão ainda não tem histórico num comerciante específico.
- Idempotente: repetir o mesmo item não duplica a ligação.
- Assim que a origem dos dados for confirmada, adapte apenas o script/CSV
  que produz esta lista — o contrato do endpoint não deve mudar.

## Fluxos na aplicação Flutter

- **App do cliente** (`lib/features/nfc_cards/presentation/customer_nfc_card_screen.dart`):
  associar/revogar o próprio cartão, acessível em Perfil → Definições →
  "Cartão físico".
- **App do dono do negócio**:
  - `lib/features/nfc_cards/presentation/merchant_nfc_card_screen.dart`:
    ler um cartão para identificar o cliente e avançar para "Registar
    venda" (`new_sale_screen.dart`, `preselectedCustomerId`) ou "Atribuir
    benefício" (`RedeemRewardSheet`). Acessível pelo atalho "Cartão NFC" no
    dashboard.
  - `lib/features/nfc_cards/presentation/merchant_nfc_card_link_screen.dart`:
    associação assistida (telefone + nome opcional) para clientes sem a
    app instalada.
  - O atalho "Código do cliente" no dashboard foi também ligado ao ecrã de
    QR já existente (`/merchant/customer-qr`), que antes não tinha nenhum
    botão a apontar para ele.
- Leitura de hardware: `lib/features/nfc_cards/domain/nfc_card_reader.dart`
  (pacote `nfc_manager`). Requer permissão `android.permission.NFC` no
  Android e a capability Core NFC (`com.apple.developer.nfc.readersession.formats`)
  no iOS — configuração feita em
  `android/app/src/main/AndroidManifest.xml` e
  `ios/Runner/Runner.entitlements`. **Nota:** a alteração ao
  `project.pbxproj` para referenciar o entitlements foi feita por edição de
  texto (sem Xcode disponível neste ambiente); confirme em Xcode que a
  capability "Near Field Communication Tag Reading" aparece corretamente
  em Signing & Capabilities antes de submeter à App Store.

## Limitações conhecidas / próximos passos

- A auditoria usa registo estruturado leve
  (`logCustomerNfcEvent`/`console.info`), não o pipeline completo de
  eventos de domínio/projeções de fidelização (esse pipeline destina-se a
  eventos que afetam saldo de pontos; associar/revogar um cartão não
  afeta pontos por si só).
- A app do cliente não mostra ainda qual o UID atualmente associado (só
  permite associar/revogar); mostrar esse estado exigiria uma nova rota
  de consulta inversa (canónico → cartão), fora do âmbito inicial.
- Testes automáticos de `NfcCardReader` cobrem disponibilidade, timeout e
  erros de sessão com um `NfcManager` falso; a extração do UID a partir de
  um `NfcTag` real só pode ser validada em dispositivo físico.
