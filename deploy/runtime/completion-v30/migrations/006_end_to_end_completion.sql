SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS carts (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  customer_id BIGINT UNSIGNED NULL,
  token_hash CHAR(64) NOT NULL,
  status ENUM('active','converted','abandoned') NOT NULL DEFAULT 'active',
  currency CHAR(3) NOT NULL DEFAULT 'BRL',
  expires_at DATETIME NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_cart_token (token_hash),
  KEY idx_cart_tenant_status (tenant_id,status,expires_at),
  KEY idx_cart_customer (customer_id,status),
  CONSTRAINT fk_cart_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_cart_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cart_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  cart_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  variant_id BIGINT UNSIGNED NULL,
  print_id BIGINT UNSIGNED NULL,
  quantity INT UNSIGNED NOT NULL DEFAULT 1,
  unit_price DECIMAL(14,2) NOT NULL,
  customization_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_cart_item_cart (cart_id),
  KEY idx_cart_item_product (product_id,variant_id),
  CONSTRAINT fk_cart_item_cart FOREIGN KEY (cart_id) REFERENCES carts(id) ON DELETE CASCADE,
  CONSTRAINT fk_cart_item_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT,
  CONSTRAINT fk_cart_item_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE SET NULL,
  CONSTRAINT fk_cart_item_print FOREIGN KEY (print_id) REFERENCES prints(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS order_addresses (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT UNSIGNED NOT NULL,
  address_type ENUM('shipping','billing') NOT NULL DEFAULT 'shipping',
  recipient VARCHAR(190) NULL,
  postal_code VARCHAR(20) NOT NULL,
  street VARCHAR(255) NOT NULL,
  number VARCHAR(50) NULL,
  complement VARCHAR(190) NULL,
  district VARCHAR(190) NULL,
  city VARCHAR(190) NOT NULL,
  state VARCHAR(80) NOT NULL,
  country CHAR(2) NOT NULL DEFAULT 'BR',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_order_address_type (order_id,address_type),
  CONSTRAINT fk_order_address_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS order_status_history (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT UNSIGNED NOT NULL,
  from_status VARCHAR(80) NULL,
  to_status VARCHAR(80) NOT NULL,
  actor_type VARCHAR(40) NOT NULL,
  actor_id VARCHAR(190) NULL,
  note VARCHAR(1000) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_order_history (order_id,created_at),
  CONSTRAINT fk_order_history_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS webhook_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  provider VARCHAR(80) NOT NULL,
  external_id VARCHAR(190) NOT NULL,
  event_type VARCHAR(120) NOT NULL,
  payload_json JSON NULL,
  status ENUM('received','processed','ignored','error') NOT NULL DEFAULT 'received',
  error_text TEXT NULL,
  received_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processed_at DATETIME NULL,
  UNIQUE KEY uq_webhook_provider_external (tenant_id,provider,external_id),
  KEY idx_webhook_status (status,received_at),
  CONSTRAINT fk_webhook_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS print_workflow (
  print_id BIGINT UNSIGNED PRIMARY KEY,
  stage ENUM('library','queue','processed','published','archived') NOT NULL DEFAULT 'library',
  processing_locked TINYINT(1) NOT NULL DEFAULT 0,
  last_actor VARCHAR(190) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_print_workflow_print FOREIGN KEY (print_id) REFERENCES prints(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS print_workflow_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  print_id BIGINT UNSIGNED NOT NULL,
  from_stage VARCHAR(40) NULL,
  to_stage VARCHAR(40) NOT NULL,
  actor_type VARCHAR(40) NOT NULL DEFAULT 'admin',
  actor_id VARCHAR(190) NULL,
  note VARCHAR(1000) NULL,
  metadata_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_print_event (print_id,created_at),
  CONSTRAINT fk_print_event_print FOREIGN KEY (print_id) REFERENCES prints(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS print_assets (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  print_id BIGINT UNSIGNED NOT NULL,
  role ENUM('original','composition','mockup','export') NOT NULL,
  path VARCHAR(1000) NOT NULL,
  checksum_sha256 CHAR(64) NULL,
  metadata_json JSON NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_print_asset (print_id,role,active),
  CONSTRAINT fk_print_asset_print FOREIGN KEY (print_id) REFERENCES prints(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS positioning_codes (
  code VARCHAR(120) PRIMARY KEY,
  print_id BIGINT UNSIGNED NULL,
  product_id BIGINT UNSIGNED NULL,
  template_id BIGINT UNSIGNED NULL,
  zone_key VARCHAR(120) NULL,
  config_json JSON NULL,
  locked TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_position_print (print_id,locked),
  KEY idx_position_product (product_id,template_id),
  CONSTRAINT fk_position_print FOREIGN KEY (print_id) REFERENCES prints(id) ON DELETE SET NULL,
  CONSTRAINT fk_position_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL,
  CONSTRAINT fk_position_template FOREIGN KEY (template_id) REFERENCES mockup_templates(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS marketing_jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  channel VARCHAR(80) NOT NULL,
  job_type VARCHAR(80) NOT NULL DEFAULT 'publish',
  status ENUM('draft','queued','approved','published','failed','cancelled') NOT NULL DEFAULT 'draft',
  content_json JSON NOT NULL,
  scheduled_at DATETIME NULL,
  published_at DATETIME NULL,
  external_id VARCHAR(190) NULL,
  last_error TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_marketing_tenant_status (tenant_id,status,scheduled_at),
  CONSTRAINT fk_marketing_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO payment_gateways (tenant_id,provider,display_name,enabled,sandbox,config_json)
VALUES (1,'manual_pix','PIX manual',1,0,JSON_OBJECT('mode','manual','instructions','Configure a chave PIX no Super Admin antes de receber pagamentos reais.'))
ON DUPLICATE KEY UPDATE display_name=VALUES(display_name);

INSERT INTO shipping_carriers (tenant_id,provider,name,enabled,config_json)
VALUES (1,'pickup','Retirada no local',1,JSON_OBJECT('price',0,'estimateDays',0))
ON DUPLICATE KEY UPDATE name=VALUES(name);
