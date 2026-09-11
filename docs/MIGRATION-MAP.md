# Mapa de migração Bela Stock legado → Node

| Legado | Node |
|---|---|
| `wp_posts` product | `products` + `product_variants` |
| `_bss_customizable` | `products.customizable` |
| `_bss_template_id` | `product_mockup_rules.template_id` |
| `_bss_allowed_positions` | `product_mockup_rules.allowed_positions_json` |
| `_bss_position_prices` | `product_mockup_rules.position_prices_json` |
| `bss_print` | `prints` |
| `_bss_print_code` | `prints.code` |
| `_bss_print_status` | `prints.status` |
| `bss_template` | `mockup_templates` |
| `_bss_zones` | `mockup_templates.zones_json` |
| `_bss_color_images` | `mockup_templates.color_images_json` |
| `wp_bss_conversations` | `conversations` |
| `wp_bss_messages` | `messages` |
| `bss_home_content` | `settings` com prefixo `home.` |

## Regra arquitetural

WooCommerce não faz parte do núcleo da nova loja. Ele entra pelo `Supplier Gateway`, em staging, antes de qualquer dado virar catálogo Bela Stock. SKU interno, regras de preço, estampa, mockup, posicionamento e decisão de fornecedor permanecem sob controle da Bela Stock e da camada de IA auditável.
