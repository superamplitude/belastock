# Bela Stock AI Commerce — Status de Produção

**Versão ativa:** `2.2.0`  
**Domínio canônico:** `https://belastock.com.br`  
**Runtime:** Node.js + Fastify + MySQL + PM2  
**Porta interna canônica:** `127.0.0.1:3210`  
**Deploy/controle:** GitHub Actions self-hosted runner na VPS

## Produção verificada

- Banco `belastock_node` autenticado pelo mesmo driver `mysql2` usado pela aplicação.
- Migrations `001` a `005` aplicadas.
- PM2 ativo sob o usuário `lojabelastock` e persistido via systemd.
- Nginx canônico corrigido para `127.0.0.1:3210`.
- `/`, `/health`, `/cliente`, `/parceiro`, `/admin` e `/api/public/store` respondendo HTTP 200.
- `www.belastock.com.br` redirecionando com HTTP 301 para o domínio canônico.
- Fronteiras privadas de cliente, parceiro e super admin respondendo HTTP 401 sem autenticação.
- Suite `npm run check`: 7/7 testes aprovados.

## Núcleos ativos

- Supplier Gateway desacoplado do catálogo interno.
- Adaptador WooCommerce para fornecedores, sem transformar Bela Stock em WordPress/WooCommerce.
- Simulador/pré-importação de fornecedor.
- Multi-store / white-label por tenant e domínio.
- Painel do Cliente.
- Painel do Parceiro.
- Super Admin.
- Catálogo de gateways: Mercado Pago, PagBank, Pagar.me, Stripe e PIX manual.
- Catálogo de frete: Correios, Melhor Envio, Frenet, Jadlog, transportadora própria, fulfillment do fornecedor e retirada.
- Regras de frete por produto, incluindo exigência de transportadora, peso e dimensões.

## Estrutura multi-tenant verificada

14 tabelas obrigatórias verificadas em produção, incluindo tenants, domínios, usuários de parceiro, listagens de produtos, gateways, transportadoras, clientes, endereços, transações, remessas, sessões e assinaturas.

Tenant raiz verificado:

- `id=1`
- `code=belastock`
- `status=active`
- `plan_code=platform`
- domínio primário `belastock.com.br`
- SSL ativo

## Gateways e transportadoras

Os provedores estão registrados na arquitetura e disponíveis para configuração por tenant. Operações financeiras e cotações reais de provedores externos só devem ser ativadas quando existirem credenciais válidas da conta correspondente e validação em sandbox/produção.

## Evidência de fechamento

Workflow de produção GitHub Actions **run 24** concluído com sucesso em 2026-09-13, com os marcadores:

```text
BELA_STOCK_22_MULTISTORE=100%_OK
BELA_STOCK_22_CUSTOMER_PANEL=100%_OK
BELA_STOCK_22_PARTNER_PANEL=100%_OK
BELA_STOCK_22_PAYMENTS_ARCHITECTURE=100%_OK
BELA_STOCK_22_SHIPPING_ARCHITECTURE=100%_OK
BELA_STOCK_22_SUPPLIER_GATEWAY=100%_OK
EXECUCAO_TOTAL_BELASTOCK_22=CONCLUIDA
```
