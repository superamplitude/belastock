# Bela Stock AI Commerce 2.0

Reconstrução nativa em Node.js da Bela Stock. O núcleo não depende de WordPress ou WooCommerce. WooCommerce passa a existir somente como **adaptador de fornecedores e fonte de migração**.

## Princípios

- Node.js + Fastify + MySQL.
- IA como orquestrador operacional central.
- Supplier Gateway desacoplado do catálogo interno.
- WooCommerce Adapter bidirecional.
- Estoque, preço, catálogo, pedidos, atendimento e operações auditáveis.
- Ações sensíveis ficam protegidas por nível de autonomia: `automatic`, `supervised` ou `approval`.
- Credenciais de fornecedores criptografadas em AES-256-GCM.
- Log de auditoria para ações administrativas e da IA.
- Migração preserva produtos, estampas, templates e metadados específicos da Bela Stock.

## Estrutura

```text
src/
  ai/orchestrator.mjs
  suppliers/woocommerce.mjs
  services/supplier-service.mjs
  security/crypto.mjs
  server.mjs
migrations/001_init.sql
scripts/migrate.mjs
scripts/import-legacy-wordpress.mjs
public/
deploy/
tests/
```

## Supplier Gateway

O adaptador WooCommerce lê `/wp-json/wc/v3`, normaliza produtos para `supplier_items` e mantém a estrutura externa fora do domínio principal. A vinculação de ofertas a produtos/variantes internos ocorre pela camada de normalização e decisão da Bela Stock.

## IA central

A tabela `ai_actions` registra decisões, risco, justificativa, modo de autonomia, aprovação e resultado. O primeiro executor ativo é `supplier.sync`; a arquitetura foi preparada para catálogo, preço, estoque, roteamento de pedidos, atendimento, marketing e qualidade.

A IA nunca recebe carta branca para credenciais, conta bancária, exclusões ou pagamentos. A autonomia é governada por política e auditada.

## Instalação alvo

Diretório de produção:

```text
/home/lojabelastock/htdocs/belastock.com.br
```

Execute na VPS:

```bash
git clone https://github.com/superamplitude/belastock.git /home/lojabelastock/htdocs/belastock.com.br
cd /home/lojabelastock/htdocs/belastock.com.br
cp .env.example .env
# configure .env
npm install --omit=dev
npm run migrate
pm2 startOrReload ecosystem.config.cjs
pm2 save
```

O script `deploy/install.sh` faz backup do conteúdo anterior antes da instalação e não instala silenciosamente dependências de sistema.

## Migração do legado

1. Importe o dump antigo em um banco isolado, por exemplo `belastock_legacy`.
2. Configure `LEGACY_DB_*` no `.env`.
3. Execute:

```bash
npm run legacy:import
```

O importador inicial migra `product`, `bss_print` e `bss_template`. O SQL legado contém ainda WooCommerce e outras tabelas, que devem permanecer somente como fonte de reconciliação até a migração ser validada.

## Testes

```bash
npm test
npm run check
```

## Endpoints iniciais

- `GET /health`
- `GET /api/public/home`
- `GET /api/public/products`
- `GET /api/admin/dashboard`
- `GET/POST /api/admin/suppliers`
- `POST /api/admin/suppliers/:id/test`
- `POST /api/admin/suppliers/:id/sync`
- `POST /api/admin/ai/run`
- `GET /api/admin/ai/actions`
- `POST /api/admin/ai/actions/:id/approve`

Rotas administrativas exigem `Authorization: Bearer <ADMIN_TOKEN>`.
