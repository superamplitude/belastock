SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS supplier_import_profiles (
  supplier_id BIGINT UNSIGNED PRIMARY KEY,
  mode ENUM('test','production') NOT NULL DEFAULT 'test',
  sync_products TINYINT(1) NOT NULL DEFAULT 1,
  sync_prices TINYINT(1) NOT NULL DEFAULT 1,
  sync_stock TINYINT(1) NOT NULL DEFAULT 1,
  sync_images TINYINT(1) NOT NULL DEFAULT 1,
  auto_stage TINYINT(1) NOT NULL DEFAULT 1,
  auto_promote TINYINT(1) NOT NULL DEFAULT 0,
  target_margin_pct DECIMAL(8,3) NOT NULL DEFAULT 40.000,
  fixed_overhead DECIMAL(14,2) NOT NULL DEFAULT 0,
  minimum_stock INT NOT NULL DEFAULT 0,
  extra_lead_time_days INT NOT NULL DEFAULT 0,
  preview_limit INT UNSIGNED NOT NULL DEFAULT 20,
  rules_json JSON NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_supplier_import_profile_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS supplier_sync_runs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  supplier_id BIGINT UNSIGNED NOT NULL,
  run_type ENUM('test','preview','sync','import') NOT NULL,
  status ENUM('running','completed','failed') NOT NULL DEFAULT 'running',
  metrics_json JSON NULL,
  error_text TEXT NULL,
  started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at DATETIME NULL,
  KEY idx_supplier_sync_runs (supplier_id, started_at),
  CONSTRAINT fk_supplier_sync_runs_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
