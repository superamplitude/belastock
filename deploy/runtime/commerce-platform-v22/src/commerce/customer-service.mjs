import crypto from 'node:crypto';
import { promisify } from 'node:util';
import { db } from '../db.mjs';
import { audit } from '../audit.mjs';

const scrypt = promisify(crypto.scrypt);
const sha256 = value => crypto.createHash('sha256').update(String(value)).digest('hex');

async function hashPassword(password) {
  const value = String(password || '');
  if (value.length < 8) throw new Error('Password must have at least 8 characters');
  const salt = crypto.randomBytes(16).toString('hex');
  const derived = await scrypt(value, salt, 64);
  return `scrypt$${salt}$${Buffer.from(derived).toString('hex')}`;
}

async function verifyPassword(password, stored) {
  const [kind,salt,hex] = String(stored || '').split('$');
  if (kind !== 'scrypt' || !salt || !hex) return false;
  const derived = Buffer.from(await scrypt(String(password || ''), salt, 64));
  const expected = Buffer.from(hex, 'hex');
  return derived.length === expected.length && crypto.timingSafeEqual(derived, expected);
}

export async function registerCustomer(tenantId, input = {}) {
  const name = String(input.name || '').trim();
  const email = String(input.email || '').trim().toLowerCase();
  if (!name || !email || !email.includes('@')) throw new Error('name and valid email are required');
  const passwordHash = await hashPassword(input.password);
  const [result] = await db.execute(`INSERT INTO customers (tenant_id,name,email,phone,document,password_hash,status,preferences_json)
    VALUES (?,?,?,?,?,?,'active',?)`, [tenantId,name,email,input.phone || null,input.document || null,passwordHash,JSON.stringify(input.preferences || {})]);
  await audit({ actorType:'customer', actorId:String(result.insertId), action:'customer.register', entityType:'customer', entityId:result.insertId, metadata:{ tenantId,email } });
  return { id:result.insertId,tenantId,name,email };
}

export async function loginCustomer(tenantId, input = {}, context = {}) {
  const email = String(input.email || '').trim().toLowerCase();
  const [rows] = await db.execute(`SELECT id,tenant_id,name,email,phone,password_hash,status FROM customers WHERE tenant_id=? AND email=? LIMIT 1`, [tenantId,email]);
  const customer = rows[0];
  if (!customer || customer.status !== 'active' || !(await verifyPassword(input.password, customer.password_hash))) throw new Error('Invalid email or password');
  const token = crypto.randomBytes(32).toString('base64url');
  const tokenHash = sha256(token);
  const ipHash = context.ip ? sha256(context.ip) : null;
  await db.execute(`INSERT INTO customer_sessions (customer_id,token_hash,user_agent,ip_hash,expires_at,last_seen_at) VALUES (?,?,?,?,DATE_ADD(NOW(),INTERVAL 30 DAY),NOW())`, [
    customer.id,tokenHash,String(context.userAgent || '').slice(0,500) || null,ipHash
  ]);
  await audit({ actorType:'customer', actorId:String(customer.id), action:'customer.login', entityType:'customer', entityId:customer.id, metadata:{ tenantId } });
  return { token,customer:{ id:customer.id,tenantId:customer.tenant_id,name:customer.name,email:customer.email,phone:customer.phone } };
}

export async function logoutCustomer(token) {
  if (!token) return { ok:true };
  await db.execute(`DELETE FROM customer_sessions WHERE token_hash=?`, [sha256(token)]);
  return { ok:true };
}

export async function customerFromSession(tenantId, token) {
  if (!token) return null;
  const [rows] = await db.execute(`SELECT c.id,c.tenant_id,c.name,c.email,c.phone,c.document,c.preferences_json,s.id session_id
    FROM customer_sessions s JOIN customers c ON c.id=s.customer_id
    WHERE s.token_hash=? AND s.expires_at>NOW() AND c.tenant_id=? AND c.status='active' LIMIT 1`, [sha256(token),tenantId]);
  const customer = rows[0];
  if (!customer) return null;
  await db.execute(`UPDATE customer_sessions SET last_seen_at=NOW() WHERE id=?`, [customer.session_id]);
  delete customer.session_id;
  return customer;
}

export async function customerPanel(tenantId, customerId) {
  const [customers] = await db.execute(`SELECT id,name,email,phone,document,preferences_json,created_at FROM customers WHERE id=? AND tenant_id=? LIMIT 1`, [customerId,tenantId]);
  if (!customers[0]) throw new Error('Customer not found');
  const [[orders],[addresses],[shipments],[payments]] = await Promise.all([
    db.execute(`SELECT id,order_number,status,currency,subtotal,shipping_total,discount_total,grand_total,created_at,updated_at FROM orders WHERE tenant_id=? AND customer_id=? ORDER BY id DESC LIMIT 100`, [tenantId,customerId]),
    db.execute(`SELECT id,label,recipient,postal_code,street,number,complement,district,city,state,country,is_default FROM customer_addresses WHERE customer_id=? ORDER BY is_default DESC,id DESC`, [customerId]),
    db.execute(`SELECT s.id,s.order_id,s.status,s.tracking_code,s.shipping_cost,s.label_url,s.estimate_days,s.updated_at,sc.name carrier_name FROM shipments s LEFT JOIN shipping_carriers sc ON sc.id=s.shipping_carrier_id WHERE s.tenant_id=? AND s.order_id IN (SELECT id FROM orders WHERE tenant_id=? AND customer_id=?) ORDER BY s.id DESC`, [tenantId,tenantId,customerId]),
    db.execute(`SELECT pt.id,pt.order_id,pt.status,pt.amount,pt.currency,pt.method,pt.updated_at,pg.display_name gateway_name FROM payment_transactions pt LEFT JOIN payment_gateways pg ON pg.id=pt.payment_gateway_id WHERE pt.tenant_id=? AND pt.order_id IN (SELECT id FROM orders WHERE tenant_id=? AND customer_id=?) ORDER BY pt.id DESC`, [tenantId,tenantId,customerId])
  ]);
  return { customer:customers[0],orders,addresses,shipments,payments };
}

export async function saveCustomerAddress(tenantId, customerId, input = {}) {
  const [customer] = await db.execute(`SELECT id FROM customers WHERE id=? AND tenant_id=? LIMIT 1`, [customerId,tenantId]);
  if (!customer[0]) throw new Error('Customer not found');
  if (!input.postalCode || !input.street || !input.city || !input.state) throw new Error('postalCode, street, city and state are required');
  if (input.isDefault) await db.execute(`UPDATE customer_addresses SET is_default=0 WHERE customer_id=?`, [customerId]);
  const [result] = await db.execute(`INSERT INTO customer_addresses (customer_id,label,recipient,postal_code,street,number,complement,district,city,state,country,is_default)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`, [customerId,input.label || null,input.recipient || null,input.postalCode,input.street,input.number || null,input.complement || null,input.district || null,input.city,input.state,input.country || 'BR',input.isDefault ? 1 : 0]);
  return { id:result.insertId };
}
