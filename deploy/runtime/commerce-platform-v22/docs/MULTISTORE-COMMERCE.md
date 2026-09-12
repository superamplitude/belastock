# Bela Stock 2.2 — Multi-store / White-label Commerce

A plataforma deixa de ser apenas uma loja única e passa a suportar a Bela Stock principal + lojas parceiras independentes, todas no mesmo núcleo Node/MySQL.

## Loja parceira

Cada parceiro pode ter:

- domínio próprio;
- marca/configuração visual própria;
- usuários e perfis de acesso próprios;
- catálogo da Bela Stock, catálogo de fornecedores e produtos próprios;
- preços e margens próprios por produto;
- gateways de pagamento próprios;
- transportadoras próprias;
- pedidos e clientes segregados por loja;
- mensalidade/plano e taxa de plataforma configuráveis;
- painel em `/parceiro`.

## Cliente final

Cada loja possui painel de cliente em `/cliente` com:

- cadastro e login;
- pedidos;
- pagamentos;
- entregas e rastreio;
- endereços;
- dados da conta.

## Pagamentos

Registro inicial de provedores:

- Mercado Pago;
- PagBank;
- Pagar.me;
- Stripe;
- PIX manual.

As credenciais são criptografadas com o mecanismo já usado no Bela Stock. Cada tenant mantém suas próprias credenciais/configurações.

## Transportadoras e frete

Registro inicial de provedores:

- Correios;
- Melhor Envio;
- Frenet;
- Jadlog;
- transportadora própria/contratada;
- frete do fornecedor;
- retirada no local.

Cada produto pode definir se precisa de frete, se exige transportadora, se é enviado pelo fornecedor, peso/dimensões e quais transportadoras são permitidas.

## Domínios

O domínio é resolvido pela aplicação através da tabela `tenant_domains`. DNS/Cloudflare continua sendo configurado externamente. SSL precisa estar válido no servidor antes de marcar o domínio como totalmente ativo.

## Segurança e isolamento

- dados segregados por `tenant_id`;
- credenciais de gateway/transportadora criptografadas;
- sessões separadas para clientes e usuários parceiros;
- ações administrativas auditadas;
- loja raiz Bela Stock é o tenant 1.
