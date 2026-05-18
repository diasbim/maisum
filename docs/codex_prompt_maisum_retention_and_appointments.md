# Codex Prompt — Implementação das Funcionalidades de Retenção + Agendamento

## Contexto do Produto

Estou a construir uma aplicação mobile chamada +1 (MaisUM), focada em fidelização de clientes para barbearias e salões em Maputo, Moçambique.

O objectivo principal da app é:

- registar vendas rapidamente;
- atribuir pontos automaticamente;
- aumentar retenção de clientes;
- aumentar recorrência;
- substituir cartões de papel.

A app é:

- mobile-first;
- offline-first;
- extremamente simples;
- inspirada em UX estilo WhatsApp/Nubank.

Stack actual:

- Flutter
- Riverpod
- Firebase Auth
- Cloud Firestore
- Firebase Cloud Functions
- Firebase Messaging
- SQLite/Hive/Drift para offline cache

Arquitectura desejada:

- Clean Architecture
- Feature-first
- Repository Pattern
- Riverpod State Management

---

# OBJECTIVO

Implementar DUAS funcionalidades:

1. Agendamento da próxima visita/corte.
2. Dashboard inteligente de retenção.

A implementação deve ser:

- production-ready;
- escalável;
- simples;
- optimizada para Firestore;
- optimizada para UX rápida;
- offline-first.

---

# FEATURE 1 — AGENDAMENTO DE PRÓXIMA VISITA

## OBJECTIVO

Após uma venda concluída:

1. mostrar um ecrã de sucesso;
2. sugerir agendar o próximo corte;
3. permitir seleccionar data rapidamente;
4. guardar agendamento;
5. enviar lembretes futuros.

---

# UX FLOW

Fluxo:

Venda registada
↓
Pontos atribuídos
↓
Success Screen
↓
CTA:
“Agendar próximo corte?”
↓
Quick options:
- 7 dias
- 14 dias
- 21 dias
- 30 dias
↓
OU calendário manual
↓
Guardar agendamento
↓
Notificação futura

---

# FIRESTORE COLLECTION

appointments

Exemplo:

```json
{
  "id": "appointment_id",
  "merchantId": "merchant_001",
  "customerId": "customer_001",
  "scheduledDate": "2026-05-20T10:00:00Z",
  "status": "scheduled",
  "source": "post_sale_flow",
  "reminderSent": false,
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

---

# STATUS TYPES

- scheduled
- completed
- cancelled
- missed

---

# IMPLEMENTAÇÃO NECESSÁRIA

Criar:

## Flutter

- screens
- widgets
- providers
- repositories
- models
- services
- local cache

---

# ESTRUTURA

/lib/features/appointments/

Subpastas:

- data/
- domain/
- presentation/
- providers/
- widgets/
- services/

---

# NECESSÁRIO IMPLEMENTAR

## 1. Appointment Model

Criar modelo completo:

- fromJson
- toJson
- copyWith
- equality

---

## 2. Firestore Repository

Métodos:

- createAppointment()
- updateAppointment()
- cancelAppointment()
- getUpcomingAppointments()
- markAppointmentAsMissed()

---

## 3. Riverpod Providers

Criar:

- appointmentsProvider
- upcomingAppointmentsProvider
- createAppointmentProvider

---

## 4. Success Screen Widget

Criar componente reutilizável:

SuccessSaleScreen()

Com:

- animação simples;
- CTA agendamento;
- quick date buttons;
- date picker.

---

## 5. Notifications

Usar Firebase Messaging.

Criar:

- local notification scheduling;
- reminder notifications.

---

## 6. Cloud Function

Criar:

dailyAppointmentReminder()

Responsabilidade:

- verificar agendamentos futuros;
- enviar reminders;
- actualizar reminderSent.

Usar TypeScript.

---

# FEATURE 2 — RETENÇÃO INTELIGENTE

## OBJECTIVO

Criar dashboard para mostrar:

- clientes recorrentes;
- clientes activos;
- clientes em risco;
- clientes perdidos;
- clientes recuperados.

---

# RISK RULES

0-14 dias → active
15-29 → attention
30-59 → risk
60+ → lost

---

# FIRESTORE COLLECTION

retention_metrics

```json
{
  "customerId": "customer_001",
  "merchantId": "merchant_001",
  "lastVisitAt": "timestamp",
  "daysInactive": 18,
  "riskLevel": "attention",
  "totalVisits": 12,
  "averageVisitInterval": 14,
  "totalSpent": 6500,
  "isRecurring": true,
  "recovered": false,
  "updatedAt": "timestamp"
}
```

---

# DASHBOARD UX

Criar duas tabs:

1. Recorrentes
2. Em risco

---

# RECORRENTES

Mostrar:

- nome;
- visitas totais;
- última visita;
- frequência;
- gasto total.

Badges:

- VIP
- Frequente
- Campeão

---

# EM RISCO

Mostrar:

- nome;
- dias sem voltar;
- última visita;
- ticket médio;
- risk level.

CTA:

“Enviar lembrete”

---

# IMPLEMENTAÇÃO NECESSÁRIA

Criar:

/lib/features/retention/

Subpastas:

- data/
- domain/
- presentation/
- providers/
- widgets/
- services/

---

# NECESSÁRIO IMPLEMENTAR

## 1. Retention Model

Criar:

- fromJson
- toJson
- copyWith
- equality

---

## 2. Repository

Métodos:

- getRecurringCustomers()
- getInactiveCustomers()
- calculateRetention()
- updateCustomerRisk()

---

## 3. Riverpod Providers

Criar:

- recurringCustomersProvider
- inactiveCustomersProvider
- retentionDashboardProvider

---

## 4. Dashboard UI

Criar:

RetentionDashboardScreen()

Com:

- tabs;
- cards;
- loading states;
- empty states;
- responsive layout.

---

## 5. Customer Cards

Criar widgets:

- RecurringCustomerCard
- InactiveCustomerCard

---

## 6. Cloud Function

Criar:

calculateRetentionMetrics()

Responsabilidade:

- calcular dias sem visita;
- actualizar riskLevel;
- actualizar métricas.

Usar TypeScript.

---

# OFFLINE-FIRST

IMPORTANTÍSSIMO:

Tudo deve funcionar offline.

Implementar:

- local cache;
- optimistic updates;
- sync queue.

---

# PERFORMANCE

Objectivos:

- venda completa < 5 segundos;
- dashboard < 2 segundos;
- agendamento < 1 segundo.

---

# FIRESTORE OPTIMIZATION

Criar indexes:

- merchantId + scheduledDate
- merchantId + riskLevel
- merchantId + lastVisitAt

---

# UI PRINCIPLES

A aplicação NÃO deve parecer:

- ERP;
- sistema pesado;
- agenda complexa.

Deve parecer:

- rápida;
- moderna;
- simples;
- extremamente intuitiva.

Inspirar UX em:

- WhatsApp
- Nubank
- Stripe

---

# OUTPUT ESPERADO

Gerar:

1. Estrutura completa de pastas
2. Models
3. Repositories
4. Riverpod Providers
5. Firestore Services
6. Cloud Functions
7. Flutter Screens
8. Widgets reutilizáveis
9. Offline cache layer
10. Notification services
11. Firestore indexes
12. Production-ready code
13. Comentários importantes
14. Best practices
15. Clean Architecture implementation

---

# IMPORTANTE

Prioridade máxima:

SIMPLICIDADE.

A app deve continuar:

- rápida;
- leve;
- fácil para barbeiros.

Não criar complexidade desnecessária.

Foco:

- retenção;
- recorrência;
- frequência;
- uso diário.

