# Bela Stock Supplier Gateway 2.1

A Bela Stock continua sendo uma aplicação Node independente de WordPress/WooCommerce. WooCommerce é tratado somente como uma origem de catálogo.

Fluxo operacional:

1. Cadastrar fornecedor e credenciais do conector.
2. Testar a conexão.
3. Simular uma amostra sem gravar/publicar produtos.
4. Definir margem, custo fixo e estoque mínimo por fornecedor.
5. Sincronizar o catálogo para `supplier_items` (fila/staging).
6. Revisar e selecionar itens da fila.
7. Importar selecionados como produtos `draft`.
8. Publicação continua sendo decisão separada.

O vínculo entre origem e catálogo é persistente por `supplier_id + external_id`, evitando duplicação nas sincronizações futuras.

Conectores previstos no registro: WooCommerce (ativo), JSON, XML, CSV e manual (arquitetura preparada, ainda não ativos).
