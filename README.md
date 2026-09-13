# Bela Stock AI Commerce 3.0

Plataforma nativa em **Node.js + Fastify + MySQL**, independente de WordPress. WooCommerce permanece somente como conector/adaptador possível de fornecedor e fonte de migração; o domínio interno da Bela Stock é próprio.

## Estado atual

Produção canônica: `https://belastock.com.br`

A versão `3.0.0` está publicada, endurecida e validada na VPS pelo runner self-hosted do GitHub Actions. A auditoria adversarial final e a auditoria reutilizável do estado corrente terminaram com sucesso; consulte `STATUS.md` para evidências, runs e pendências externas reais.

## Núcleo ativo

- catálogo público multi-tenant;
- produto, variação, preço e estoque;
- carrinho persistido no servidor;
- cliente, autenticação e endereços;
- cotação interna/configurável;
- checkout;
- pedidos, pagamentos, remessas e histórico;
- roteamento de itens para ofertas de fornecedores quando disponíveis;
- Supplier Gateway e simulador/pré-importação;
- painel do Cliente;
- painel do Parceiro;
- Super Admin;
- multi-store / white-label por tenant e domínio;
- relatórios;
- rascunhos de marketing;
- Central de IA e trilha de auditoria.

## Segurança de produção

- runtime Node exposto somente em `127.0.0.1:3210` atrás do Nginx;
- PM2 persistido e controlado por `systemd`;
- controlador de restart exige health estável antes de declarar sucesso;
- `.env` modo `640`, sem leitura para outros usuários;
- credenciais externas protegidas pelo contrato `CREDENTIALS_MASTER_KEY` / AES-256-GCM;
- headers de segurança no Nginx;
- TLS válido e monitorado;
- `@fastify/rate-limit@11.2.0` nas rotas de cadastro/login;
- login de cliente e parceiro limitado a 8 tentativas por minuto;
- cadastro de cliente limitado a 5 tentativas em 10 minutos;
- rate limit comprovado em produção por HTTP `429` na nona tentativa inválida de login;
- `npm audit --omit=dev --audit-level=high` sem vulnerabilidades na auditoria final.

## Estampas e mockups

Fluxo nativo:

```text
Biblioteca
  -> Fila de Processamento
  -> Processadas
  -> Publicadas
```

O original é preservado. Uma estampa não sai da fila sem composição/mockup ativo e código de posicionamento travado. O código de posicionamento é persistente e não é renomeado automaticamente. A remoção de imagem de mockup grava a alteração no banco, evitando o problema de a imagem reaparecer após refresh.

## Supplier Gateway

```text
Fornecedor
  -> Adaptador
  -> Normalização
  -> Simulador / pré-importação
  -> Regras de estoque e margem
  -> Aprovação
  -> Catálogo Bela Stock
  -> Sincronização controlada
```

O adaptador WooCommerce lê a API do fornecedor e normaliza dados para o domínio Bela Stock. A arquitetura mantém IDs/SKUs externos separados do catálogo interno.

## Multi-store / White-label

Cada tenant pode ter:

- domínio próprio;
- identidade e configurações;
- usuários e permissões;
- catálogo Bela Stock e produtos próprios;
- preço/margem por listagem;
- gateways e transportadoras;
- clientes e pedidos segregados;
- plano, mensalidade e taxa da plataforma.

`belastock.com.br` é o tenant raiz.

## Pagamentos e frete

Provedores registrados:

**Pagamentos:** Mercado Pago, PagBank, Pagar.me, Stripe e PIX manual.  
**Frete:** Correios, Melhor Envio, Frenet, Jadlog, transportadora própria, fulfillment do fornecedor e retirada.

O caminho interno validado em produção usa PIX manual e retirada. Provedores externos que movimentam dinheiro ou consultam serviços de transportadoras só podem ser marcados como ativos depois do cadastro de credenciais válidas e teste sandbox/produção. Nenhuma credencial é inventada ou hard-coded.

## Rotas principais

Públicas:

- `GET /health`
- `GET /api/public/store`
- `GET /api/public/home`
- `GET /api/public/products`
- `GET /api/public/products/:idOrSlug`
- `POST/GET /api/cart`
- `POST/PUT/DELETE /api/cart/items`
- `POST /api/checkout/quote`
- `POST /api/checkout`

Cliente:

- registro/login/logout;
- painel;
- endereços;
- detalhe de pedido.

Parceiro:

- login/logout;
- painel;
- produtos;
- pedidos;
- gateways e transportadoras por tenant.

Super Admin:

- produtos e variações;
- pedidos, pagamento e remessas;
- estampas, workflow, arquivos e posicionamento;
- mockups e regras por produto;
- tenants, domínios e usuários;
- fornecedores, Supplier Gateway e simulador;
- pagamentos/frete;
- relatórios;
- marketing;
- IA.

## Banco e migrations

Produção está em `001` a `006`. A auditoria final validou 43/43 tabelas obrigatórias, seis migrations registradas, ausência de órfãos nas relações críticas, ausência de duplicidades críticas e ausência de resíduos dos E2E sintéticos.

## Produção

Diretório:

```text
/home/lojabelastock/htdocs/belastock.com.br
```

Upstream canônico:

```text
127.0.0.1:3210
```

O Nginx publica HTTPS e o PM2 mantém o runtime Node ativo sob o usuário `lojabelastock`.

## Deploy e controle

A ponte de produção usa GitHub Actions com runner self-hosted na VPS. O token normal do workflow opera com `contents: read`; alterações de produção preservam backup, rollback, migrations idempotentes, testes, PM2/systemd, `nginx -t`, health e validações de autenticação.

Arquivos principais:

```text
.github/workflows/belastock-vps-bridge.yml
deploy/BELASTOCK_VPS_CONTROL.sh
deploy/APPLY_COMPLETION_V30.sh
deploy/APPLY_SECURITY_HARDENING_V30.sh
.belastock/vps-task.sh
.belastock/validate-v30-e2e.mjs
.belastock/final-adversarial-audit.mjs
```

## Testes

```bash
npm test
npm run check
```

A suíte validada da 3.0 possui **11 testes, 11 aprovados, 0 falhas**. Além da suíte unitária/estrutural, o deploy executou E2E descartável:

```text
produto -> cliente -> carrinho -> cotação -> checkout
-> pagamento -> processamento -> conclusão
```

O mesmo E2E validou o fluxo `Biblioteca -> Fila -> Processadas -> Publicadas`, a trava obrigatória e a persistência da exclusão de imagem de mockup. Os dados sintéticos foram removidos ao final.

## Estado comercial

A plataforma está tecnicamente aprovada, porém o catálogo real ainda precisa ser populado. Na última auditoria não havia produtos publicados, fornecedores ativos, pedidos ou clientes reais. Gateways/transportadoras externos permanecem condicionados às credenciais reais e validação de cada conta.
