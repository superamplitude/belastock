import { db } from '../db.mjs';
import { audit } from '../audit.mjs';

const cleanDomain = value => String(value || '').trim().toLowerCase().replace(/^https?:\/\//, '').replace(/\/$/, '').split(':')[0];
const cleanCode = value => String(value || '').trim().toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '');

export async function resolveTenantByHost(host) {
  const domain = cleanDomain(host);
  if (!domain) return null;
  const [rows] = await db.execute(`SELECT t.*,td.domain,td.is_primary FROM tenant_domains td JOIN tenants t ON t.id=td.tenant_id WHERE td.domain=? AND td.status='active' AND t.status IN ('trial','active') LIMIT 1`, [domain]);
  return rows[0] || null;
}

export async function listTenants() {
  const [rows] = await db.query(`SELECT t.id,t.code,t.name,t.status,t.plan_code,t.owner_name,t.owner_email,t.owner_phone,t.platform_fee_pct,t.monthly_fee,t.created_at,t.updated_at,
    (SELECT td.domain FROM tenant_domains td WHERE td.tenant_id=t.id ORDER BY td.is_primary DESC,td.id ASC LIMIT 1) primary_domain
    FROM tenants t ORDER BY t.id DESC`);
  return rows;
}

export async function getTenant(id) {
  const [rows] = await db.execute(`SELECT * FROM tenants WHERE id=? LIMIT 1`, [id]);
  if (!rows[0]) throw new Error('Tenant not found');
  const [domains] = await db.execute(`SELECT id,domain,is_primary,status,ssl_status,verified_at FROM tenant_domains WHERE tenant_id=? ORDER BY is_primary DESC,id ASC`, [id]);
  return { ...rows[0], domains };
}

export async function createTenant(input = {}) {
  const code = cleanCode(input.code || input.name);
  const name = String(input.name || '').trim();
  if (!code || !name) throw new Error('name and code are required');
  const [result] = await db.execute(`INSERT INTO tenants (code,name,legal_name,status,plan_code,owner_name,owner_email,owner_phone,default_currency,platform_fee_pct,monthly_fee,brand_json,settings_json)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`, [
    code,name,input.legalName || null,'trial',input.planCode || 'partner',input.ownerName || null,input.ownerEmail || null,input.ownerPhone || null,input.defaultCurrency || 'BRL',Number(input.platformFeePct || 0),Number(input.monthlyFee || 0),JSON.stringify(input.brand || {}),JSON.stringify(input.settings || {})
  ]);
  if (input.domain) await addTenantDomain(result.insertId, input.domain, true);
  await audit({ actorType:'admin', action:'tenant.create', entityType:'tenant', entityId:result.insertId, after:{ code,name,domain:input.domain || null } });
  return getTenant(result.insertId);
}

export async function updateTenant(id, input = {}) {
  const tenant = await getTenant(id);
  const next = {
    name: input.name ?? tenant.name,
    legalName: input.legalName ?? tenant.legal_name,
    status: input.status ?? tenant.status,
    planCode: input.planCode ?? tenant.plan_code,
    ownerName: input.ownerName ?? tenant.owner_name,
    ownerEmail: input.ownerEmail ?? tenant.owner_email,
    ownerPhone: input.ownerPhone ?? tenant.owner_phone,
    defaultCurrency: input.defaultCurrency ?? tenant.default_currency,
    platformFeePct: input.platformFeePct ?? tenant.platform_fee_pct,
    monthlyFee: input.monthlyFee ?? tenant.monthly_fee,
    brand: input.brand ?? (typeof tenant.brand_json === 'string' ? JSON.parse(tenant.brand_json || '{}') : tenant.brand_json || {}),
    settings: input.settings ?? (typeof tenant.settings_json === 'string' ? JSON.parse(tenant.settings_json || '{}') : tenant.settings_json || {})
  };
  await db.execute(`UPDATE tenants SET name=?,legal_name=?,status=?,plan_code=?,owner_name=?,owner_email=?,owner_phone=?,default_currency=?,platform_fee_pct=?,monthly_fee=?,brand_json=?,settings_json=? WHERE id=?`, [
    next.name,next.legalName,next.status,next.planCode,next.ownerName,next.ownerEmail,next.ownerPhone,next.defaultCurrency,Number(next.platformFeePct || 0),Number(next.monthlyFee || 0),JSON.stringify(next.brand),JSON.stringify(next.settings),id
  ]);
  await audit({ actorType:'admin', action:'tenant.update', entityType:'tenant', entityId:id, before:{ status:tenant.status,planCode:tenant.plan_code }, after:{ status:next.status,planCode:next.planCode } });
  return getTenant(id);
}

export async function addTenantDomain(tenantId, domainInput, primary = false) {
  await getTenant(tenantId);
  const domain = cleanDomain(domainInput);
  if (!domain || !domain.includes('.')) throw new Error('Invalid domain');
  if (primary) await db.execute(`UPDATE tenant_domains SET is_primary=0 WHERE tenant_id=?`, [tenantId]);
  await db.execute(`INSERT INTO tenant_domains (tenant_id,domain,is_primary,status,ssl_status) VALUES (?,?,?,'pending_dns','pending')
    ON DUPLICATE KEY UPDATE tenant_id=VALUES(tenant_id),is_primary=VALUES(is_primary)`, [tenantId,domain,primary ? 1 : 0]);
  await audit({ actorType:'admin', action:'tenant.domain.add', entityType:'tenant', entityId:tenantId, metadata:{ domain, primary:Boolean(primary) } });
  return getTenant(tenantId);
}

export async function activateTenantDomain(tenantId, domainInput, sslActive = false) {
  const domain = cleanDomain(domainInput);
  const [result] = await db.execute(`UPDATE tenant_domains SET status='active',ssl_status=?,verified_at=NOW() WHERE tenant_id=? AND domain=?`, [sslActive ? 'active' : 'pending',tenantId,domain]);
  if (!result.affectedRows) throw new Error('Tenant domain not found');
  return getTenant(tenantId);
}
