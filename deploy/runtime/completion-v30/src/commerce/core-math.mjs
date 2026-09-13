export const money = value => Math.round((Number(value || 0) + Number.EPSILON) * 100) / 100;

export function computeOrderTotals(items = [], shipping = 0, discount = 0) {
  const subtotal = money(items.reduce((sum,item) => sum + Number(item.unitPrice || item.unit_price || 0) * Number(item.quantity || 0), 0));
  const shippingTotal = money(Math.max(0,Number(shipping || 0)));
  const discountTotal = money(Math.max(0,Math.min(Number(discount || 0),subtotal + shippingTotal)));
  return { subtotal,shippingTotal,discountTotal,grandTotal:money(subtotal + shippingTotal - discountTotal) };
}

export const ORDER_TRANSITIONS = Object.freeze({
  pending:['paid','cancelled'],
  paid:['processing','refunded','cancelled'],
  processing:['partially_fulfilled','fulfilled','cancelled','refunded'],
  partially_fulfilled:['fulfilled','cancelled','refunded'],
  fulfilled:['refunded'],
  cancelled:[],
  refunded:[]
});

export function canTransitionOrder(from,to) {
  if (from === to) return true;
  return Boolean(ORDER_TRANSITIONS[from]?.includes(to));
}

export const PRINT_TRANSITIONS = Object.freeze({
  library:['queue','archived'],
  queue:['processed','archived'],
  processed:['published','queue','archived'],
  published:['processed','archived'],
  archived:['library']
});

export function canTransitionPrint(from,to) {
  if (from === to) return true;
  return Boolean(PRINT_TRANSITIONS[from]?.includes(to));
}

export function normalizeQuantity(value,max=99) {
  const n=Math.trunc(Number(value));
  if (!Number.isFinite(n) || n < 1 || n > max) throw new Error(`Quantity must be between 1 and ${max}`);
  return n;
}

export function parseJson(value,fallback={}) {
  if (value == null || value === '') return fallback;
  if (typeof value === 'object') return value;
  try { return JSON.parse(value); } catch { return fallback; }
}

export function sanitizeCode(value) {
  const code=String(value||'').trim().toUpperCase().replace(/[^A-Z0-9_-]+/g,'-').replace(/^-+|-+$/g,'');
  if (!code || code.length > 120) throw new Error('Invalid positioning/print code');
  return code;
}
