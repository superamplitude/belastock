# Bela Stock AI Commerce 2.2

Plataforma nativa em **Node.js + Fastify + MySQL**, independente de WordPress. WooCommerce é apenas um **conector de fornecedor** e fonte possível de migração/sincronização; o domínio interno da Bela Stock permanece desacoplado do schema WooCommerce.

## Estado atual

Produção canônica: `https://belastock.com.br`

A versão `2.2.0` está publicada e validada na VPS por GitHub Actions self-hosted runner, com banco, migrations, PM2, Nginx, páginas públicas e fronteiras de autenticação testadas end-to-end. Consulte `STATUS.md` para a evidência operacional atual.

## Princípios

- Node.js + Fastify + MySQL.
- IA como camada central de orquestração operacional.
- Supplier Gateway desacoplado do catálogo interno.
- WooCommerce tratado como adaptador, nunca como núcleo da plataforma.
- Multi-fornecedor e multi-loja/white-label.
- Estoque, preço, catálogo, pedidos, atendimento e operações auditáveis.
- Ações sensíveis protegidas por nível de autonomia: `automatic`, `supervised` ou `approval`.
- Credenciais de integrações armazenadas criptografadas em AES-256-GCM.
- Log de auditoria para ações administrativas e da IA.
- Dados separados por tenant para parceiros e lojas white-label.

## Supplier Gateway

O gateway de fornecedores permite que fontes externas sejam normalizadas para o modelo interno Bela Stock antes da publicação.

Fluxo:

```text
Fornecedor
  -> Adaptador (WooCommerce/API/JSON/XML/CSV/etc.)
  -> Normalização
  -> Simulador / pré-importação
  -> Regras de estoque, margem e catálogo
  -> Aprovação
  -> Catálogo Bela Stock
  -> Sincronização controlada
```

O adaptador WooCommerce lê a REST API do fornecedor, normaliza produtos e mantém IDs/SKUs externos vinculados aos itens internos sem acoplamento ao schema WordPress.

## Multi-store / White-label

A 2.2 adiciona a base para comercialização de lojas parceiras sobre o mesmo núcleo Bela Stock:

- tenant por parceiro;
- domínio próprio por tenant;
- marca e configurações por loja;
- usuários e permissões por parceiro;
- catálogo Bela Stock + produtos próprios do parceiro;
- preço/margem por listagem;
- gateways próprios por loja;
- transportadoras próprias por loja;
- plano, mensalidade e taxa da plataforma;
- sessões independentes de cliente e parceiro.

O host da requisição resolve o tenant correspondente. `belastock.com.br` é o tenant raiz da plataforma.

## Pagamentos

Catálogo estrutural disponível por tenant:

- Mercado Pago;
- PagBank;
- Pagar.me;
- Stripe;
- PIX manual.

Credenciais externas não ficam hard-coded no projeto. Cada tenant configura seus próprios dados de integração. Transações reais só devem ser ativadas após configuração e validação do respectivo provedor.

## Frete e transportadoras

Catálogo estrutural disponível por tenant:

- Correios;
- Melhor Envio;
- Frenet;
- Jadlog;
- transportadora própria/customizada;
- fulfillment pelo fornecedor;
- retirada.

Cada produto pode definir se exige envio físico e/ou transportadora, peso, dimensões, classe de frete e transportadoras permitidas.

## Painéis

Rotas públicas principais:

- `/` — loja pública;
- `/cliente` — Painel do Cliente;
- `/parceiro` — Painel do Parceiro;
- `/admin` — Super Admin.

APIs privadas retornam `401` sem sessão/token válido.

## IA central

A tabela `ai_actions` registra decisões, risco, justificativa, modo de autonomia, aprovação e resultado. O núcleo já suporta a evolução da IA sobre fornecedores, catálogo, preço, estoque, roteamento de pedidos, atendimento, marketing e qualidade.

A IA não recebe autorização irrestrita para credenciais, conta bancária, exclusões ou pagamentos. Operações sensíveis permanecem governadas por política e auditoria.

## Estrutura principal

```text
src/
  ai/
  commerce/
    payment/
    shipping/
  services/
  suppliers/
  security/
  server.mjs
migrations/
  001_init.sql
  002_supplier_gateway.sql
  003_multistore_payments_shipping.sql
  004_customer_sessions_partner_subscriptions.sql
  005_partner_user_sessions.sql
public/
deploy/
tests/
```

## Produção

Diretório:

```text
/home/lojabelastock/htdocs/belastock.com.br
```

Porta interna canônica:

```text
127.0.0.1:3210
```

O Nginx publica o domínio HTTPS e encaminha ao runtime Node nessa porta.

## Deploy e controle

O projeto utiliza GitHub Actions com runner self-hosted na VPS. A ponte de produção permite execução auditável sem depender de comandos SSH manuais para cada alteração.

Arquivos principais:

```text
.github/workflows/belastock-vps-bridge.yml
deploy/BELASTOCK_VPS_CONTROL.sh
.belastock/vps-task.sh
```

Mudanças de produção devem manter:

1. backup antes da alteração;
2. migrations idempotentes;
3. `npm run check` aprovado;
4. PM2 persistente;
5. `nginx -t` aprovado;
6. health local e público HTTP 200;
7. validação de autenticação e isolamento.

## Testes

```bash
npm test
npm run check
```

Na versão 2.2, a suíte de produção validada possui testes para Supplier Gateway, normalização WooCommerce, cálculo de margem e catálogos de pagamentos/frete.

## Endpoints principais

Públicos:

- `GET /health`
- `GET /api/public/store`
- `GET /api/public/home`
- `GET /api/public/products`

Cliente:

- `POST /api/customer/register`
- `POST /api/customer/login`
- `POST /api/customer/logout`
- `GET /api/customer/panel`
- `POST /api/customer/addresses`

Parceiro:

- `POST /api/partner/login`
- `POST /api/partner/logout`
- `GET /api/partner/panel`
- gestão de catálogo próprio e Bela Stock;
- configuração de gateways e transportadoras do tenant.

Super Admin:

- tenants e domínios;
- usuários de parceiros;
- catálogo e fornecedores;
- Supplier Gateway e simulador;
- regras de pagamento/frete;
- IA e auditoria.

Rotas administrativas exigem autenticação válida e ações sensíveis permanecem auditáveis.
