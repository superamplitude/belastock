import { priceFromCost } from './pricing-core.mjs';

const num = value => value === '' || value == null ? null : Number(value);
const clampInt = (value, fallback, min, max) => {
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : fallback;
};

export function normalizeImportProfile(row = {}) {
  return {
    mode: row.mode === 'production' ? 'production' : 'test',
    syncProducts: row.sync_products == null ? true : Boolean(row.sync_products),
    syncPrices: row.sync_prices == null ? true : Boolean(row.sync_prices),
    syncStock: row.sync_stock == null ? true : Boolean(row.sync_stock),
    syncImages: row.sync_images == null ? true : Boolean(row.sync_images),
    autoStage: row.auto_stage == null ? true : Boolean(row.auto_stage),
    autoPromote: Boolean(row.auto_promote),
    targetMarginPct: Number(row.target_margin_pct ?? 40),
    fixedOverhead: Number(row.fixed_overhead ?? 0),
    minimumStock: Number(row.minimum_stock ?? 0),
    extraLeadTimeDays: Number(row.extra_lead_time_days ?? 0),
    previewLimit: clampInt(row.preview_limit, 20, 1, 50),
    rules: typeof row.rules_json === 'string' ? JSON.parse(row.rules_json || '{}') : (row.rules_json || {})
  };
}

export function buildPreviewItem(normalized, profileInput = {}) {
  const profile = normalizeImportProfile(profileInput);
  const cost = num(normalized.currentPrice ?? normalized.regularPrice);
  const stock = normalized.stockQuantity == null ? null : Number(normalized.stockQuantity);
  const issues = [];

  if (!normalized.name) issues.push({ level: 'error', code: 'missing_name', message: 'Produto sem nome.' });
  if (!normalized.externalSku) issues.push({ level: 'warning', code: 'missing_sku', message: 'SKU externo ausente; o Bela Stock criará SKU interno.' });
  if (cost == null || !Number.isFinite(cost) || cost < 0) issues.push({ level: 'warning', code: 'missing_cost', message: 'Preço/custo de origem ausente ou inválido.' });
  if (normalized.stockStatus === 'outofstock' || (stock != null && stock <= 0)) issues.push({ level: 'warning', code: 'out_of_stock', message: 'Produto sem estoque no fornecedor.' });
  if (stock != null && stock < profile.minimumStock) issues.push({ level: 'warning', code: 'below_minimum_stock', message: `Estoque abaixo do mínimo configurado (${profile.minimumStock}).` });
  if (!Array.isArray(normalized.images) || normalized.images.length === 0) issues.push({ level: 'warning', code: 'missing_image', message: 'Produto sem imagem.' });

  let suggestedPrice = null;
  if (cost != null && Number.isFinite(cost) && cost >= 0) {
    try { suggestedPrice = priceFromCost(cost, profile.targetMarginPct, profile.fixedOverhead); }
    catch { suggestedPrice = null; }
  }

  const eligible = !issues.some(issue => issue.level === 'error') && !(stock != null && stock < profile.minimumStock);
  return {
    externalId: normalized.externalId,
    externalSku: normalized.externalSku || null,
    name: normalized.name || '',
    type: normalized.type || 'simple',
    sourceStatus: normalized.status || 'draft',
    stockStatus: normalized.stockStatus || null,
    stockQuantity: stock,
    sourceCost: cost,
    suggestedPrice,
    targetMarginPct: profile.targetMarginPct,
    fixedOverhead: profile.fixedOverhead,
    image: Array.isArray(normalized.images) && normalized.images[0] ? normalized.images[0].src : (normalized.image?.src || null),
    imageCount: Array.isArray(normalized.images) ? normalized.images.length : (normalized.image ? 1 : 0),
    categoryNames: Array.isArray(normalized.categories) ? normalized.categories.map(c => c.name).filter(Boolean) : [],
    attributes: Array.isArray(normalized.attributes) ? normalized.attributes : [],
    eligible,
    issues
  };
}
