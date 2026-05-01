# 📱 UX SCRIPT — LOYALTYOS (MVP)

## Contexto
Aplicação mobile de fidelização para pequenas empresas (barbearias) em Maputo.

## Core Loop
Registrar venda → Atribuir pontos → Trazer cliente de volta

---

## 🎯 Objectivo de UX
Permitir que o barbeiro:
- Registe uma venda em < 5 segundos
- Atribua pontos automaticamente
- Incentive o retorno do cliente

---

## 🧠 Princípios de Design
- Máximo 3 toques por acção
- Botões grandes (uso com uma mão)
- Texto mínimo
- Feedback instantâneo
- UX familiar (estilo WhatsApp)
- Funciona offline

---

## 👤 Utilizador Principal
Barbeiro / dono do negócio

- Usa Android
- Ambiente movimentado
- Pouco tempo
- Baixa tolerância a complexidade

---

## 🔁 Fluxo Principal
Dashboard → Nova Venda → Pontos → Notificação → Dashboard

---

## 🟢 Ecrã 1 — Login
- Input: Número de telefone
- Botão: Continuar
- OTP automático

Regras:
- Sem password
- Login = registo

---

## 🟡 Ecrã 2 — Dashboard

Elementos:
- Nome da loja
- Estado (Online/Offline)
- Vendas do dia
- Pontos atribuídos

Botões principais:
- Nova Venda
- Clientes
- Recompensas

---

## 🔵 Ecrã 3 — Nova Venda

Passo 1:
- Procurar cliente (nome/telefone)

Passo 2:
- Inserir valor
- Botões rápidos: 100 / 200 / 500

Passo 3:
- Confirmar

---

## 🟣 Resultado
Mensagem:
"Cliente ganhou X pontos ⭐"

Mostrar:
- Total de pontos
- Progresso da recompensa

---

## 🔔 Notificação Automática
Mensagem via WhatsApp:

"Obrigado pela sua visita 🙌\n\nGanhou X pontos.\n\nVolte para ganhar recompensa!"

---

## 👥 Ecrã 4 — Clientes
Lista:
- Nome
- Pontos
- Última visita

Detalhe:
- Histórico
- Adicionar pontos
- Enviar mensagem

---

## 🎁 Ecrã 5 — Recompensas
Lista de recompensas

Criar:
- Nome
- Pontos necessários

---

## 🔄 Retenção
Mensagem automática se cliente inactivo:

"Sentimos sua falta 😄\n\nTem pontos acumulados. Volte!"

---

## 📶 Offline
- Guardar vendas localmente
- Sincronizar quando online

---

## 🔐 Autenticação
- OTP SMS
- Sessão persistente

---

## 🎨 Design
- Verde: sucesso
- Amarelo: recompensa
- Vermelho: erro

---

## ⚡ Performance
- Venda < 5s
- Feedback < 1s

---

## 📊 Métricas
- Vendas/dia
- Retenção de clientes

---

## 💡 Regra Final
O produto deve ser usado todos os dias, várias vezes.
Se não for rápido, falha.
