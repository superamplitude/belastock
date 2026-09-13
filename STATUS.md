# Bela Stock AI Commerce — Status de Produção

**Versão ativa:** `3.0.0`  
**Domínio canônico:** `https://belastock.com.br`  
**Runtime:** Node.js + Fastify + MySQL + PM2  
**Porta interna canônica:** `127.0.0.1:3210`  
**Deploy/controle:** GitHub Actions self-hosted runner na VPS

## Fechamento interno

A Bela Stock 3.0 está publicada e validada em produção com o fluxo interno completo de comércio, operação e processamento.

- banco `belastock_node` autenticado pelo driver `mysql2` usado pela aplicação;
- migrations `001` a `006` aplicadas;
- PM2 `belastock` online como versão `3.0.0` e persistido;
- Nginx canônico em `127.0.0.1:3210`;
- `/`, `/health`, `/admin`, `/cliente`, `/parceiro`, `/storefront.js`, `/operations.js`, `/api/public/store` e `/api/public/products` respondendo HTTP 200;
- `www.belastock.com.br` redirecionando HTTP 301 para o domínio canônico;
- fronteiras privadas de cliente, parceiro e Super Admin respondendo HTTP 401 sem autenticação;
- suíte `npm run check`: **11/11 testes aprovados, 0 falhas**;
- teste sintético end-to-end concluído e removido integralmente após a prova.

## Fluxo comercial validado

O teste de produção criou dados descartáveis e comprovou:

`Produto publicado → Cliente → Carrinho → Cotação → Checkout → Pedido → Pagamento → Processamento → Conclusão`

Também foi comprovada a reserva de estoque e a limpeza dos dados sintéticos depois do teste.

## Estampas e mockups

Fluxo operacional ativo:

`Biblioteca → Fila de Processamento → Processadas → Publicadas`

Regras ativas e testadas:

- original preservado;
- item não sai da fila sem composição/mockup ativo;
- item não sai da fila sem código de posicionamento travado;
- código de posicionamento persistente e não renomeado automaticamente;
- histórico de transições;
- remoção de imagem de mockup persistindo no banco e permanecendo removida após nova leitura.

## Super Admin

O painel administra:

- produtos, preços, status, variações e estoque;
- Biblioteca/Fila/Processadas/Publicadas;
- arquivos de estampa e códigos de posicionamento;
- mockups;
- pedidos e confirmação de pagamentos;
- lojas white-label, domínios e usuários;
- fornecedores e Supplier Gateway;
- simulador/pré-importação;
- pagamentos e transportadoras;
- relatórios;
- rascunhos de marketing;
- Central de IA.

## Multi-store / white-label

A estrutura multi-tenant permanece ativa para tenants, domínios, usuários, listagens, clientes, pedidos, pagamentos, frete, sessões e assinaturas. O tenant raiz é `belastock`, domínio primário `belastock.com.br`, status `active`.

## Pagamento e frete

O caminho interno funcional usa:

- `manual_pix` — PIX manual;
- `pickup` — retirada no local.

A arquitetura também registra Mercado Pago, PagBank, Pagar.me, Stripe, Correios, Melhor Envio, Frenet, Jadlog, transportadora própria e fulfillment do fornecedor.

**Dependência externa:** provedores que movimentam dinheiro ou consultam transportadoras externas não são declarados como ativos sem credenciais reais da conta correspondente e validação sandbox/produção. O código está preparado para configuração por tenant; credenciais não são inventadas nem embutidas no repositório.

## Evidência final

Workflow de produção GitHub Actions **run 29**, concluído com `success` em 2026-09-13.

```text
PACKAGE_VERSION=3.0.0
DB_AUTH_MYSQL2=OK
BELA_STOCK_V30_E2E=100%_OK
E2E_SYNTHETIC_DATA_CLEANUP=OK
V30_REQUIRED_TABLES=10
V30_MISSING_TABLES=
MIGRATION_006_EFFECT=100%_OK
SCHEMA_MIGRATIONS_TOTAL=6
E2E_RESIDUE={"products":0,"customers":0,"prints":0}
VHOST_PROXY=proxy_pass http://127.0.0.1:3210/;
BELA_STOCK_V30_RUNTIME=100%_OK
BELA_STOCK_V30_DATABASE=100%_OK
BELA_STOCK_V30_STOREFRONT=100%_OK
BELA_STOCK_V30_CART_CHECKOUT=100%_OK
BELA_STOCK_V30_ORDERS=100%_OK
BELA_STOCK_V30_PRINT_WORKFLOW=100%_OK
BELA_STOCK_V30_MOCKUP_PERSISTENCE=100%_OK
BELA_STOCK_V30_MULTISTORE=100%_OK
BELA_STOCK_V30_SUPPLIER_GATEWAY=100%_OK
BELA_STOCK_V30_INTERNAL_PROCESS=100%_OK
EXTERNAL_PROVIDERS=READY_FOR_CREDENTIALS
EXECUCAO_TOTAL_BELASTOCK_V30=CONCLUIDA
```
