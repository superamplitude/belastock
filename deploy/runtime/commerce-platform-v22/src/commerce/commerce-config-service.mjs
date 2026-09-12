import { db } from '../db.mjs';
import { encryptJson } from '../security/crypto.mjs';
import { audit } from '../audit.mjs';
import { getPaymentProvider, listPaymentProviders } from './payment/registry.mjs';
import { getShippingProvider, listShippingProviders } from './shipping/registry.mjs';

export function paymentProviderCatalog() { return listPaymentProviders(); }
export function shippingProviderCatalog() { return listShippingProviders(); }

export async function listPaymentGateways(tenantId) {
  const [rows] = await db.execute(`SELECT id,tenant_id,provider,display_name,enabled,sandbox,config_json,created_at,updated_at FROM payment_gateways WHERE tenant_id=? ORDER BY id ASC`, [tenantId]);
  return rows;
}

export async function savePaymentGateway(tenantId, input = {}) {
  const provider = String(input.provider || '').trim();
  const meta = getPaymentProvider(provider);
  const displayName = String(input.displayName || meta.label).trim();
  const encrypted = input.credentials && typeof input.credentials === 'object' ? encryptJson(input.credentials) : null;
  const config = input.config && typeof input.config === 'object' ? input.config : {};
  await db.execute(`INSERT INTO payment_gateways (tenant_id,provider,display_name,enabled,sandbox,credentials_encrypted,config_json)
    VALUES (?,?,?,?,?,?,?)
    ON DUPLICATE KEY UPDATE display_name=VALUES(display_name),enabled=VALUES(enabled),sandbox=VALUES(sandbox),credentials_encrypted=COALESCE(VALUES(credentials_encrypted),credentials_encrypted),config_json=VALUES(config_json),updated_at=NOW()`, [
    tenantId,provider,displayName,Boolean(input.enabled) ? 1 : 0,input.sandbox === false ? 0 : 1,encrypted,JSON.stringify(config)
  ]);
  await audit({ actorType:'admin', action:'payment.gateway.save', entityType:'tenant', entityId:tenantId, metadata:{ provider,enabled:Boolean(input.enabled),sandbox:input.sandbox !== false } });
  return listPaymentGateways(tenantId);
}

export async function listShippingCarriers(tenantId) {
  const [rows] = await db.execute(`SELECT id,tenant_id,provider,name,enabled,config_json,created_at,updated_at FROM shipping_carriers WHERE tenant_id=? ORDER BY id ASC`, [tenantId]);
  return rows;
}

export async function saveShippingCarrier(tenantId, input = {}) {
  const provider = String(input.provider || '').trim();
  const meta = getShippingProvider(provider);
  const name = String(input.name || meta.label).trim();
  const encrypted = input.credentials && typeof input.credentials === 'object' ? encryptJson(input.credentials) : null;
  const config = input.config && typeof input.config === 'object' ? input.config : {};
  await db.execute(`INSERT INTO shipping_carriers (tenant_id,provider,name,enabled,credentials_encrypted,config_json)
    VALUES (?,?,?,?,?,?)
    ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),credentials_encrypted=COALESCE(VALUES(credentials_encrypted),credentials_encrypted),config_json=VALUES(config_json),updated_at=NOW()`, [
    tenantId,provider,name,Boolean(input.enabled) ? 1 : 0,encrypted,JSON.stringify(config)
  ]);
  await audit({ actorType:'admin', action:'shipping.carrier.save', entityType:'tenant', entityId:tenantId, metadata:{ provider,name,enabled:Boolean(input.enabled) } });
  return listShippingCarriers(tenantId);
}

export async function getProductShippingRule(productId) {
  const [rows] = await db.execute(`SELECT * FROM product_shipping_rules WHERE product_id=? LIMIT 1`, [productId]);
  if (!rows[0]) return { productId,requiresShipping:true,requiresCarrier:false,supplierFulfilled:false,weightKg:null,lengthCm:null,widthCm:null,heightCm:null,allowedCarriers:[],shippingClass:null };
  const row = rows[0];
  return {
    productId,
    requiresShipping:Boolean(row.requires_shipping),
    requiresCarrier:Boolean(row.requires_carrier),
    supplierFulfilled:Boolean(row.supplier_fulfilled),
    weightKg:row.weight_kg,
    lengthCm:row.length_cm,
    widthCm:row.width_cm,
    heightCm:row.height_cm,
    allowedCarriers:typeof row.allowed_carriers_json === 'string' ? JSON.parse(row.allowed_carriers_json || '[]') : (row.allowed_carriers_json || []),
    shippingClass:row.shipping_class
  };
}

export async function saveProductShippingRule(productId, input = {}) {
  const allowed = Array.isArray(input.allowedCarriers) ? input.allowedCarriers.map(String).filter(Boolean) : [];
  await db.execute(`INSERT INTO product_shipping_rules (product_id,requires_shipping,requires_carrier,supplier_fulfilled,weight_kg,length_cm,width_cm,height_cm,allowed_carriers_json,shipping_class)
    VALUES (?,?,?,?,?,?,?,?,?,?)
    ON DUPLICATE KEY UPDATE requires_shipping=VALUES(requires_shipping),requires_carrier=VALUES(requires_carrier),supplier_fulfilled=VALUES(supplier_fulfilled),weight_kg=VALUES(weight_kg),length_cm=VALUES(length_cm),width_cm=VALUES(width_cm),height_cm=VALUES(height_cm),allowed_carriers_json=VALUES(allowed_carriers_json),shipping_class=VALUES(shipping_class),updated_at=NOW()`, [
    productId,input.requiresShipping === false ? 0 : 1,Boolean(input.requiresCarrier) ? 1 : 0,Boolean(input.supplierFulfilled) ? 1 : 0,input.weightKg ?? null,input.lengthCm ?? null,input.widthCm ?? null,input.heightCm ?? null,JSON.stringify(allowed),input.shippingClass || null
  ]);
  await audit({ actorType:'admin', action:'product.shipping_rule.save', entityType:'product', entityId:productId, metadata:{ requiresCarrier:Boolean(input.requiresCarrier),supplierFulfilled:Boolean(input.supplierFulfilled),allowedCarriers:allowed } });
  return getProductShippingRule(productId);
}
