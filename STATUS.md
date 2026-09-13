# Bela Stock AI Commerce — Status de Produção

**Versão ativa:** `3.0.0`  
**Domínio canônico:** `https://belastock.com.br`  
**Runtime:** Node.js + Fastify + MySQL + PM2 + Nginx  
**Porta interna canônica:** `127.0.0.1:3210`  
**Deploy/controle:** GitHub Actions self-hosted runner na VPS  
**Status técnico:** **APROVADO PARA PRODUÇÃO**

## Fechamento técnico

A Bela Stock 3.0 está publicada e validada em produção com fluxo interno de comércio, operação, catálogo, multi-store e processamento de estampas.

- banco `belastock_node` autenticado pelo mesmo driver `mysql2` usado pela aplicação;
- migrations `001` a `006` aplicadas;
- 43/43 tabelas obrigatórias verificadas;
- integridade relacional auditada sem órfãos ou duplicidades críticas;
- PM2 `belastock` online em `3.0.0`, controlado e persistido por `systemd`;
- reinício PM2 corrigido para exigir health estável antes de declarar sucesso;
- Nginx canônico apontando para `127.0.0.1:3210`;
- porta Node restrita ao loopback;
- `.env` pertencente a `lojabelastock:lojabelastock`, modo `640`, sem acesso para outros usuários;
- `ADMIN_TOKEN` com 80 caracteres;
- `CREDENTIALS_MASTER_KEY` validada como base64 de 32 bytes para AES-256-GCM;
- `NODE_ENV=production`, `HOST=127.0.0.1`, `PORT=3210` e `APP_URL` HTTPS canônica;
- suíte `npm run check`: **11/11 testes aprovados, 0 falhas**;
- `npm audit --omit=dev --audit-level=high`: **0 vulnerabilidades**;
- auditoria adversarial de banco/configuração: **0 falhas**.

## Segurança de autenticação

Foi instalado `@fastify/rate-limit@11.2.0` compatível com Fastify 5 e aplicado limite seletivo às rotas sensíveis:

- cadastro de cliente: 5 tentativas / 10 minutos;
- login de cliente: 8 tentativas / 1 minuto;
- login de parceiro: 8 tentativas / 1 minuto.

A validação real em produção obteve HTTP `401` nas oito primeiras tentativas inválidas e HTTP `429` na nona, com `Retry-After`. O Nginx também foi verificado usando `X-Real-IP $remote_addr`, evitando que o cliente escolha arbitrariamente a chave do rate limiter.

Headers mínimos de segurança verificados em produção:

- `X-Content-Type-Options: nosniff`;
- `X-Frame-Options: DENY`;
- `Referrer-Policy: strict-origin-when-cross-origin`;
- `Permissions-Policy`.

O certificado TLS foi verificado e permanece válido por mais de 14 dias na data da auditoria; validade observada até `Dec 11 18:54:36 2026 GMT`.

## Fluxo comercial validado end-to-end

O teste sintético de produção criou dados descartáveis e comprovou:

`Produto publicado → Cliente → Carrinho → Cotação → Checkout → Pedido → Pagamento → Processamento → Conclusão`

Também foram comprovados:

- reserva/baixa de estoque;
- criação e consulta do pedido;
- transições válidas de status;
- limpeza integral dos dados sintéticos ao fim da prova.

## Estampas e mockups

Fluxo operacional validado:

`Biblioteca → Fila de Processamento → Processadas → Publicadas`

Regras verificadas:

- original preservado;
- item não sai da fila sem composição ativa;
- item não sai da fila sem código de posicionamento travado;
- código de posicionamento persistente e não renomeado automaticamente;
- histórico de transições;
- remoção de imagem de mockup persiste no banco e permanece removida após nova leitura.

## Multi-store / White-label

A estrutura multi-tenant está ativa para:

- tenants e domínios próprios;
- usuários e sessões de parceiros;
- catálogo/listagens por tenant;
- clientes e sessões;
- pedidos;
- pagamentos;
- frete e remessas;
- assinaturas/planos;
- configurações próprias por loja.

Tenant raiz validado:

- `id=1`;
- `code=belastock`;
- `status=active`;
- domínio primário `belastock.com.br`;
- SSL ativo.

## Supplier Gateway

O núcleo permanece desacoplado de WordPress/WooCommerce. WooCommerce é apenas um conector possível de fornecedor.

O pipeline suporta normalização, simulador/pré-importação, regras de margem/estoque, aprovação e sincronização controlada. A suíte valida cálculo de margem, bloqueio por estoque mínimo e normalização de produto WooCommerce sem acoplamento ao schema WordPress.

## Pagamentos e transportadoras

Arquitetura preparada para:

- Mercado Pago;
- PagBank;
- Pagar.me;
- Stripe;
- PIX manual;
- Correios;
- Melhor Envio;
- Frenet;
- Jadlog;
- transportadora própria;
- fulfillment do fornecedor;
- retirada.

O caminho interno atualmente habilitado e validado é `manual_pix` + `pickup`.

**Dependência externa real:** gateways e transportadoras que movimentam dinheiro, consultam tarifas ou geram etiquetas não são declarados como ativos sem credenciais válidas de cada conta e teste sandbox/produção. As credenciais não são inventadas nem gravadas no repositório.

## Evidências finais

### Run 36 — auditoria adversarial pós-hardening

GitHub Actions run `34785822364`: concluído com `success`.

Principais marcadores:

```text
PACKAGE_VERSION=3.0.0
DB_AUTH_MYSQL2=OK
PM2_SYSTEMD_ACTIVE=YES
PM2_SYSTEMD_ENABLED=YES
PORT_3210_LOCAL_ONLY=YES
AUTH_RATE_LIMIT_ATTEMPT_9=429
AUTH_RATE_LIMIT_HTTP_429=OK
NGINX_REAL_IP_HEADER=TRUSTED_REMOTE_ADDR
BELA_STOCK_V30_E2E=100%_OK
E2E_SYNTHETIC_DATA_CLEANUP=OK
FINAL_DB_ADVERSARIAL_FAILURES=0
SECURITY_HEADERS_BASELINE=OK
TLS_CERT_VALID_GT_14_DAYS=YES
VHOST_PROXY=proxy_pass http://127.0.0.1:3210/;
RATE_LIMIT_DEP=11.2.0
AUTH_RATE_LIMIT_CODE=PRESENT
SECOND_PASS_RUNTIME=100%_OK
SECOND_PASS_DATABASE_INTEGRITY=100%_OK
SECOND_PASS_E2E=100%_OK
SECOND_PASS_PM2_PERSISTENCE=100%_OK
SECOND_PASS_NGINX=100%_OK
SECOND_PASS_SECURITY_BASELINE=100%_OK
SECOND_PASS_AUTH_RATE_LIMIT=100%_OK
SECOND_PASS_REGRESSION=100%_OK
SECOND_PASS_AUDIT=CONCLUIDA
BELA_STOCK_V30_PRODUCTION_APPROVAL=APPROVED
```

### Run 38 — correção de causa raiz do restart PM2

GitHub Actions run `34785965272`: concluído com `success`.

O controlador foi corrigido para aguardar três health checks consecutivos após reinício, eliminando a condição de corrida em que o PM2 já marcava o processo como `online` antes de a porta `3210` estar pronta.

```text
PM2_RESTART_RACE_ROOT_CAUSE=FIXED
PM2_RESTART_STABLE_HEALTH=100%_OK
```

### Run 39 — auditoria independente final do estado atual

GitHub Actions run `34786047995`: concluído com `success`, novamente com token do workflow reduzido para `contents: read`.

```text
DB_AUTH_MYSQL2=OK
LOCAL_HEALTH_HTTP=200
ORIGIN_HEALTH_HTTP=200
PM2=online 3.0.0
systemd=enabled/active
npm tests=11/11 pass
npm audit=0 vulnerabilities
required_tables=43/43
schema_migrations=6
FINAL_DB_ADVERSARIAL_FAILURES=0
PUBLIC /=200
PUBLIC /health=200
PUBLIC /admin=200
PUBLIC /cliente=200
PUBLIC /parceiro=200
PUBLIC /api/public/store=200
PUBLIC /api/public/products=200
PRIVATE admin=401 customer=401 partner=401
BELA_STOCK_REUSABLE_PRODUCTION_AUDIT=100%_OK
```

## Estado comercial real

A auditoria final encontrou o banco estruturalmente íntegro, porém ainda sem população comercial real:

```json
{"products":0,"published_products":0,"active_suppliers":0,"enabled_gateways":1,"enabled_carriers":1,"orders":0,"customers":0}
```

Isso não é falha de infraestrutura ou código. Significa que o próximo ciclo operacional é cadastrar/importar catálogo, ativar fornecedores reais e inserir credenciais dos provedores externos escolhidos.

## Pendências externas / operacionais

1. inserir e validar credenciais reais dos gateways de pagamento escolhidos;
2. inserir e validar credenciais reais das transportadoras escolhidas;
3. cadastrar/conectar fornecedores reais e importar catálogo;
4. popular produtos reais e iniciar operação comercial;
5. acompanhar o aviso não bloqueante do GitHub Actions sobre `actions/checkout@v4` e a descontinuação do runtime Node 20 da própria action; o runner atualmente força Node 24 e os jobs continuam aprovados.

Nenhuma dessas pendências invalida a aprovação técnica do núcleo da plataforma. Operações que dependem de terceiros só podem ser declaradas ativas depois da configuração real dessas contas.

## Status final

**APROVADO PARA PRODUÇÃO — núcleo técnico Bela Stock 3.0.0.**

A aprovação cobre runtime, banco, integridade, autenticação, proteção contra tentativas excessivas de login, Nginx, PM2/systemd, TLS, fluxo comercial interno, multi-store, Supplier Gateway, painéis, workflow de estampas/mockups e regressão. Ativação comercial de integrações externas permanece condicionada às credenciais reais dos respectivos provedores.
