SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS tenants (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(80) NOT NULL,
  name VARCHAR(190) NOT NULL,
  legal_name VARCHAR(255) NULL,
  status ENUM('trial','active','suspended','cancelled') NOT NULL DEFAULT 'trial',
  plan_code VARCHAR(80) NOT NULL DEFAULT 'partner',
  owner_name VARCHAR(190) NULL,
  owner_email VARCHAR(190) NULL,
  owner_phone VARCHAR(80) NULL,
  default_currency CHAR(3) NOT NULL DEFAULT 'BRL',
  platform_fee_pct DECIMAL(8,3) NOT NULL DEFAULT 0,
  monthly_fee DECIMAL(14,2) NOT NULL DEFAULT 0,
  brand_json JSON NULL,
  settings_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_code (code),
  KEY idx_tenant_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO tenants (id,code,name,status,plan_code,default_currency,settings_json)
VALUES (1,'belastock','Bela Stock','active','platform','BRL',JSON_OBJECT('root',true))
ON DUPLICATE KEY UPDATE name=VALUES(name),status='active';

CREATE TABLE IF NOT EXISTS tenant_domains (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  domain VARCHAR(255) NOT NULL,
  is_primary TINYINT(1) NOT NULL DEFAULT 0,
  status ENUM('pending_dns','pending_ssl','active','blocked') NOT NULL DEFAULT 'pending_dns',
  ssl_status ENUM('pending','active','error') NOT NULL DEFAULT 'pending',
  verified_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_domain (domain),
  KEY idx_domain_tenant (tenant_id,status),
  CONSTRAINT fk_domain_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO tenant_domains (tenant_id,domain,is_primary,status,ssl_status,verified_at)
VALUES (1,'belastock.com.br',1,'active','active',NOW())
ON DUPLICATE KEY UPDATE tenant_id=VALUES(tenant_id),is_primary=1,status='active';

CREATE TABLE IF NOT EXISTS tenant_users (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(190) NOT NULL,
  email VARCHAR(190) NOT NULL,
  password_hash VARCHAR(500) NULL,
  role ENUM('owner','admin','catalog','orders','support','finance') NOT NULL DEFAULT 'admin',
  status ENUM('invited','active','blocked') NOT NULL DEFAULT 'invited',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_user_email (tenant_id,email),
  CONSTRAINT fk_tenant_user_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tenant_product_listings (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  source_mode ENUM('platform','partner_own','supplier') NOT NULL DEFAULT 'platform',
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  store_name VARCHAR(500) NULL,
  store_slug VARCHAR(500) NULL,
  price_override DECIMAL(14,2) NULL,
  compare_at_override DECIMAL(14,2) NULL,
  margin_pct DECIMAL(8,3) NULL,
  metadata_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_product (tenant_id,product_id),
  UNIQUE KEY uq_tenant_store_slug (tenant_id,store_slug),
  KEY idx_listing_enabled (tenant_id,enabled),
  CONSTRAINT fk_listing_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_listing_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS payment_gateways (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  provider VARCHAR(80) NOT NULL,
  display_name VARCHAR(190) NOT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 0,
  sandbox TINYINT(1) NOT NULL DEFAULT 1,
  credentials_encrypted LONGTEXT NULL,
  config_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_payment_provider (tenant_id,provider),
  CONSTRAINT fk_payment_gateway_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS shipping_carriers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  provider VARCHAR(80) NOT NULL,
  name VARCHAR(190) NOT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 0,
  credentials_encrypted LONGTEXT NULL,
  config_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_shipping_provider_name (tenant_id,provider,name),
  CONSTRAINT fk_shipping_carrier_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS product_shipping_rules (
  product_id BIGINT UNSIGNED PRIMARY KEY,
  requires_shipping TINYINT(1) NOT NULL DEFAULT 1,
  requires_carrier TINYINT(1) NOT NULL DEFAULT 0,
  supplier_fulfilled TINYINT(1) NOT NULL DEFAULT 0,
  weight_kg DECIMAL(10,3) NULL,
  length_cm DECIMAL(10,2) NULL,
  width_cm DECIMAL(10,2) NULL,
  height_cm DECIMAL(10,2) NULL,
  allowed_carriers_json JSON NULL,
  shipping_class VARCHAR(80) NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_shipping_rule_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS customers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(190) NOT NULL,
  email VARCHAR(190) NOT NULL,
  phone VARCHAR(80) NULL,
  document VARCHAR(80) NULL,
  password_hash VARCHAR(500) NULL,
  status ENUM('active','blocked','deleted') NOT NULL DEFAULT 'active',
  preferences_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_customer_tenant_email (tenant_id,email),
  KEY idx_customer_tenant (tenant_id,status),
  CONSTRAINT fk_customer_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS customer_addresses (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id BIGINT UNSIGNED NOT NULL,
  label VARCHAR(80) NULL,
  recipient VARCHAR(190) NULL,
  postal_code VARCHAR(20) NOT NULL,
  street VARCHAR(255) NOT NULL,
  number VARCHAR(50) NULL,
  complement VARCHAR(190) NULL,
  district VARCHAR(190) NULL,
  city VARCHAR(190) NOT NULL,
  state VARCHAR(80) NOT NULL,
  country CHAR(2) NOT NULL DEFAULT 'BR',
  is_default TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_address_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS payment_transactions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NOT NULL,
  payment_gateway_id BIGINT UNSIGNED NULL,
  provider_transaction_id VARCHAR(190) NULL,
  status VARCHAR(80) NOT NULL DEFAULT 'pending',
  amount DECIMAL(14,2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'BRL',
  method VARCHAR(80) NULL,
  payload_json JSON NULL,
  response_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_payment_order (tenant_id,order_id,status),
  CONSTRAINT fk_payment_tx_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_payment_tx_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_payment_tx_gateway FOREIGN KEY (payment_gateway_id) REFERENCES payment_gateways(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS shipments (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  order_id BIGINT UNSIGNED NOT NULL,
  shipping_carrier_id BIGINT UNSIGNED NULL,
  external_shipment_id VARCHAR(190) NULL,
  service_code VARCHAR(120) NULL,
  status VARCHAR(80) NOT NULL DEFAULT 'pending',
  tracking_code VARCHAR(190) NULL,
  shipping_cost DECIMAL(14,2) NULL,
  label_url VARCHAR(1000) NULL,
  estimate_days INT NULL,
  payload_json JSON NULL,
  response_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_shipment_order (tenant_id,order_id,status),
  CONSTRAINT fk_shipment_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_shipment_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_shipment_carrier FOREIGN KEY (shipping_carrier_id) REFERENCES shipping_carriers(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE products ADD COLUMN owner_tenant_id BIGINT UNSIGNED NOT NULL DEFAULT 1 AFTER id;
ALTER TABLE orders ADD COLUMN tenant_id BIGINT UNSIGNED NOT NULL DEFAULT 1 AFTER id;
ALTER TABLE orders ADD COLUMN customer_id BIGINT UNSIGNED NULL AFTER tenant_id;
ALTER TABLE conversations ADD COLUMN tenant_id BIGINT UNSIGNED NOT NULL DEFAULT 1 AFTER id;

ALTER TABLE products ADD KEY idx_products_owner_tenant (owner_tenant_id,status);
ALTER TABLE orders ADD KEY idx_orders_tenant_status (tenant_id,status,created_at);
ALTER TABLE conversations ADD KEY idx_conversations_tenant (tenant_id,status,updated_at);
ALTER TABLE products ADD CONSTRAINT fk_products_owner_tenant FOREIGN KEY (owner_tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE orders ADD CONSTRAINT fk_orders_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE conversations ADD CONSTRAINT fk_conversations_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT;

INSERT INTO tenant_product_listings (tenant_id,product_id,source_mode,enabled,store_name,store_slug)
SELECT 1,id,'platform',1,name,slug FROM products
ON DUPLICATE KEY UPDATE store_name=VALUES(store_name),store_slug=VALUES(store_slug);
