SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS tenant_user_sessions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_user_id BIGINT UNSIGNED NOT NULL,
  token_hash CHAR(64) NOT NULL,
  user_agent VARCHAR(500) NULL,
  ip_hash CHAR(64) NULL,
  expires_at DATETIME NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at DATETIME NULL,
  UNIQUE KEY uq_tenant_user_session_token (token_hash),
  KEY idx_tenant_user_sessions_user (tenant_user_id,expires_at),
  CONSTRAINT fk_tenant_user_session_user FOREIGN KEY (tenant_user_id) REFERENCES tenant_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
