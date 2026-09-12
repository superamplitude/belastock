import { db } from '../db.mjs';
import { audit } from '../audit.mjs';
import { getTenant } from './tenant-service.mjs';
import { saveProductShippingRule } from './commerce-config-service.mjs';

const slugify = value => String(value || '')
  .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
const cleanSku = value => String(value || '').trim().toUpperCase().replace(/[^A-Z0-9_-]+/g, '-').replace(/^-+|-+$/g, '');

export async function listTenantListings(tenantId) {
  await getTenant(tenantId);
  const [rows] = await db.execute(`SELECT l.id,l.tenant_id,l.product_id,l.source_mode,l.enabled,l.store_name,l.store_slug,l.price_override,l.compare_at_override,l.margin_pct,l.metadata_json,
      p.owner_tenant_id,p.sku,p.name,p.status,p.price,p.compare_at_price
    FROM tenant_product_listings l JOIN products p ON p.id=l.product_id
    WHERE l.tenant_id=? ORDER BY l.id DESC`, [tenantId]);
  return rows;
}

export async function addPlatformProductToTenant(tenantId, productId, input = {}) {
  await getTenant(tenantId);
  const [products] = await db.execute(`SELECT id,name,slug,owner_tenant_id FROM products WHERE id=? LIMIT 1`, [productId]);
  const product = products[0];
  if (!product) throw new Error('Product not found');
  const slug = slugify(input.storeSlug || product.slug || product.name) || `produto-${productId}`;
  await db.execute(`INSERT INTO tenant_product_listings (tenant_id,product_id,source_mode,enabled,store_name,store_slug,price_override,compare_at_override,margin_pct,metadata_json)
    VALUES (?,?,?,1,?,?,?,?,?,?)
    ON DUPLICATE KEY UPDATE enabled=1,store_name=VALUES(store_name),store_slug=VALUES(store_slug),price_override=VALUES(price_override),compare_at_override=VALUES(compare_at_override),margin_pct=VALUES(margin_pct),metadata_json=VALUES(metadata_json),updated_at=NOW()`, [
    tenantId,productId,product.owner_tenant_id === tenantId ? 'partner_own' : 'platform',input.storeName || product.name,slug,input.priceOverride ?? null,input.compareAtOverride ?? null,input.marginPct ?? null,JSON.stringify(input.metadata || {})
  ]);
  await audit({ actorType:'admin', action:'tenant.product.attach', entityType:'product', entityId:productId, metadata:{ tenantId,slug } });
  return listTenantListings(tenantId);
}

export async function createPartnerProduct(tenantId, input = {}) {
  const tenant = await getTenant(tenantId);
  const name = String(input.name || '').trim();
  if (!name) throw new Error('Product name is required');
  const rawSku = cleanSku(input.sku || `P${Date.now()}`);
  const sku = `T${tenantId}-${rawSku}`;
  const baseSlug = slugify(input.slug || name) || `produto-${Date.now()}`;
  const internalSlug = `${tenant.code}-${baseSlug}-${Date.now().toString(36)}`;
  const storeSlug = slugify(input.storeSlug || name) || baseSlug;
  const price = input.price == null ? null : Number(input.price);
  if (price != null && (!Number.isFinite(price) || price < 0)) throw new Error('Invalid price');

  const [productResult] = await db.execute(`INSERT INTO products (owner_tenant_id,sku,name,slug,description,short_description,status,customizable,price,compare_at_price,metadata_json)
    VALUES (?,?,?,?,?,?,?, ?,?,?,?)`, [
    tenantId,sku,name,internalSlug,input.description || '',input.shortDescription || '',input.status === 'published' ? 'published' : 'draft',Boolean(input.customizable) ? 1 : 0,price,input.compareAtPrice ?? null,JSON.stringify({ origin:'partner_own',tenantId })
  ]);
  const variantSku = `${sku}-01`;
  await db.execute(`INSERT INTO product_variants (product_id,sku,attributes_json,price,stock_quantity,status) VALUES (?,?,?,?,?,'active')`, [
    productResult.insertId,variantSku,JSON.stringify(input.attributes || {}),price,input.stockQuantity ?? null
  ]);
  await db.execute(`INSERT INTO tenant_product_listings (tenant_id,product_id,source_mode,enabled,store_name,store_slug,price_override,compare_at_override,metadata_json)
    VALUES (?,?,'partner_own',1,?,?,?,?,?)`, [tenantId,productResult.insertId,name,storeSlug,price,input.compareAtPrice ?? null,JSON.stringify(input.listingMetadata || {})]);

  if (input.shipping) await saveProductShippingRule(productResult.insertId, input.shipping);
  await audit({ actorType:'partner', actorId:String(tenantId), action:'partner.product.create', entityType:'product', entityId:productResult.insertId, after:{ name,sku,price } });
  return { productId:productResult.insertId, sku, storeSlug };
}

export async function updateTenantListing(tenantId, productId, input = {}) {
  const [rows] = await db.execute(`SELECT * FROM tenant_product_listings WHERE tenant_id=? AND product_id=? LIMIT 1`, [tenantId,productId]);
  if (!rows[0]) throw new Error('Tenant product listing not found');
  const current = rows[0];
  await db.execute(`UPDATE tenant_product_listings SET enabled=?,store_name=?,store_slug=?,price_override=?,compare_at_override=?,margin_pct=?,metadata_json=? WHERE tenant_id=? AND product_id=?`, [
    input.enabled == null ? current.enabled : (input.enabled ? 1 : 0),input.storeName ?? current.store_name,input.storeSlug ? slugify(input.storeSlug) : current.store_slug,input.priceOverride === undefined ? current.price_override : input.priceOverride,input.compareAtOverride === undefined ? current.compare_at_override : input.compareAtOverride,input.marginPct === undefined ? current.margin_pct : input.marginPct,JSON.stringify(input.metadata ?? (typeof current.metadata_json === 'string' ? JSON.parse(current.metadata_json || '{}') : current.metadata_json || {})),tenantId,productId
  ]);
  await audit({ actorType:'partner', actorId:String(tenantId), action:'tenant.product.update', entityType:'product', entityId:productId, metadata:{ tenantId } });
  return listTenantListings(tenantId);
}
