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

export async function createTenantUser(tenantId, input = {}) {
  const name = String(input.name || '').trim();
  const email = String(input.email || '').trim().toLowerCase();
  if (!name || !email || !email.includes('@')) throw new Error('name and valid email are required');
  const passwordHash = input.password ? await hashPassword(input.password) : null;
  const role = ['owner','admin','catalog','orders','support','finance'].includes(input.role) ? input.role : 'admin';
  const status = passwordHash ? 'active' : 'invited';
  const [result] = await db.execute(`INSERT INTO tenant_users (tenant_id,name,email,password_hash,role,status) VALUES (?,?,?,?,?,?)`, [tenantId,name,email,passwordHash,role,status]);
  await audit({ actorType:'admin', action:'tenant.user.create', entityType:'tenant', entityId:tenantId, metadata:{ tenantUserId:result.insertId,email,role } });
  return { id:result.insertId,tenantId,name,email,role,status };
}

export async function loginTenantUser(tenantId, input = {}, context = {}) {
  const email = String(input.email || '').trim().toLowerCase();
  const [rows] = await db.execute(`SELECT id,tenant_id,name,email,password_hash,role,status FROM tenant_users WHERE tenant_id=? AND email=? LIMIT 1`, [tenantId,email]);
  const user = rows[0];
  if (!user || user.status !== 'active' || !(await verifyPassword(input.password, user.password_hash))) throw new Error('Invalid email or password');
  const token = crypto.randomBytes(32).toString('base64url');
  await db.execute(`INSERT INTO tenant_user_sessions (tenant_user_id,token_hash,user_agent,ip_hash,expires_at,last_seen_at) VALUES (?,?,?,?,DATE_ADD(NOW(),INTERVAL 30 DAY),NOW())`, [
    user.id,sha256(token),String(context.userAgent || '').slice(0,500) || null,context.ip ? sha256(context.ip) : null
  ]);
  await audit({ actorType:'partner', actorId:String(user.id), action:'tenant.user.login', entityType:'tenant', entityId:tenantId });
  return { token,user:{ id:user.id,tenantId:user.tenant_id,name:user.name,email:user.email,role:user.role } };
}

export async function tenantUserFromSession(tenantId, token) {
  if (!token) return null;
  const [rows] = await db.execute(`SELECT u.id,u.tenant_id,u.name,u.email,u.role,u.status,s.id session_id FROM tenant_user_sessions s JOIN tenant_users u ON u.id=s.tenant_user_id WHERE s.token_hash=? AND s.expires_at>NOW() AND u.tenant_id=? AND u.status='active' LIMIT 1`, [sha256(token),tenantId]);
  const user = rows[0];
  if (!user) return null;
  await db.execute(`UPDATE tenant_user_sessions SET last_seen_at=NOW() WHERE id=?`, [user.session_id]);
  delete user.session_id;
  return user;
}

export async function logoutTenantUser(token) {
  if (token) await db.execute(`DELETE FROM tenant_user_sessions WHERE token_hash=?`, [sha256(token)]);
  return { ok:true };
}
