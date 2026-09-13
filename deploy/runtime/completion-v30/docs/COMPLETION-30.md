# Bela Stock AI Commerce 3.0 — Fechamento Operacional

A versão 3.0 fecha o fluxo interno de ponta a ponta da Bela Stock em Node.js/Fastify/MySQL, sem transformar a plataforma em WordPress/WooCommerce.

## Fluxo comercial

- catálogo público por tenant;
- detalhe de produto, variações, estoque e regras de mockup;
- carrinho persistido no servidor;
- autenticação de cliente;
- cálculo de frete interno/configurável;
- checkout;
- criação de pedido, itens, endereço, pagamento e remessa;
- confirmação de pagamento;
- roteamento para ofertas de fornecedores quando existirem;
- histórico de status;
- acompanhamento no painel do cliente e do parceiro;
- operação de pedidos no Super Admin.

## Fluxo de estampas

Contrato operacional:

`Biblioteca → Fila de Processamento → Processadas → Publicadas`

Regras:

- o original é preservado e não pode ser removido pelo fluxo normal;
- uma estampa só sai da fila quando existe composição/mockup ativo e ao menos um código de posicionamento travado;
- o código de posicionamento é uma chave persistente: depois de criado, não é renomeado automaticamente;
- toda transição gera histórico;
- remoção de imagem de mockup grava o novo JSON no banco, portanto não reaparece após refresh.

## Multi-store / white-label

A arquitetura 2.2 permanece ativa: tenant, domínio, usuários, catálogo segregado, clientes, pedidos, pagamentos e transportadoras por loja.

## Pagamentos e frete

O núcleo oferece provedores registrados para Mercado Pago, PagBank, Pagar.me, Stripe, PIX manual, Correios, Melhor Envio, Frenet, Jadlog, transportadora própria, fulfillment do fornecedor e retirada.

A versão 3.0 ativa um caminho interno seguro e testável com **PIX manual** e **retirada no local**. Integrações financeiras/logísticas externas só podem ser consideradas ativas após cadastro de credenciais válidas da conta correspondente e teste sandbox/produção. O sistema não inventa nem armazena credenciais fictícias.

## Segurança e integridade

- tokens de carrinho são armazenados apenas como SHA-256;
- sessões de cliente/parceiro continuam separadas;
- áreas administrativas continuam protegidas por token;
- ações sensíveis continuam auditáveis;
- transições de pedido e estampa são determinísticas;
- estoque finito é reservado no checkout e restaurado em cancelamento;
- backups são produzidos antes do deploy pela ponte de produção.

## Critério de fechamento 100%

O fechamento interno é aceito apenas quando todos os seguintes testes passam na VPS de produção:

1. migrations até `006` aplicadas;
2. `npm run check` sem falhas;
3. health local/origin/público com banco `true` e versão `3.0.0`;
4. storefront, cliente, parceiro e admin HTTP 200;
5. fronteiras privadas retornando 401 sem autenticação;
6. teste sintético completo de produto → carrinho → checkout → pagamento → processamento → conclusão;
7. teste de Biblioteca → Fila → Processadas → Publicadas com travas obrigatórias;
8. teste de remoção persistente de imagem de mockup;
9. limpeza integral dos dados sintéticos após o teste;
10. Nginx canônico apontando para `127.0.0.1:3210`.
