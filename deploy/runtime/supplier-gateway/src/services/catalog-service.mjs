import { db } from '../db.mjs';
import { audit } from '../audit.mjs';

const slugify = value => String(value || '')
  .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

const internalSku = (supplierId, itemId) => `BS-S${String(supplierId).padStart(3, '0')}-${String(itemId).padStart(7, '0')}`;

export async function promoteSupplierItem(itemId) {
  const [rows] = await db.execute(`SELECT si.*, s.name supplier_name FROM supplier_items si JOIN suppliers s ON s.id=si.supplier_id WHERE si.id=? LIMIT 1`, [itemId]);
  const item = rows[0];
  if (!item) throw new Error('Supplier item not found');
  const normalized = typeof item.normalized_json === 'string' ? JSON.parse(item.normalized_json) : item.normalized_json;
  const externalSku = normalized.externalSku || item.external_sku;

  const [mapped] = await db.execute(`SELECT so.id,so.product_variant_id,pv.product_id FROM supplier_offers so LEFT JOIN product_variants pv ON pv.id=so.product_variant_id WHERE so.supplier_id=? AND so.supplier_item_id=? LIMIT 1`, [item.supplier_id, item.id]);
  if (mapped[0]?.product_variant_id) return { reused:true, productId:mapped[0].product_id || null, productVariantId:mapped[0].product_variant_id, matchedBy:'supplier_item' };

  if (externalSku) {
    const [variants] = await db.execute(`SELECT pv.id,pv.product_id FROM product_variants pv WHERE pv.sku=? LIMIT 1`, [externalSku]);
    if (variants[0]) {
      await upsertOffer({ item, normalized, productVariantId:variants[0].id });
      await audit({ actorType:'ai', action:'catalog.link_supplier_item', entityType:'supplier_item', entityId:item.id, metadata:{ productVariantId:variants[0].id, matchedBy:'sku' } });
      return { reused:true, productId:variants[0].product_id, productVariantId:variants[0].id, matchedBy:'sku' };
    }
  }

  const sku = internalSku(item.supplier_id, item.id);
  const baseSlug = slugify(normalized.slug || normalized.name || `produto-${item.id}`);
  const slug = `${baseSlug}-${item.supplier_id}-${item.id}`;
  const price = normalized.currentPrice ?? normalized.regularPrice ?? null;
  const [productResult] = await db.execute(
    `INSERT INTO products (sku,name,slug,description,short_description,status,customizable,price,metadata_json)
     VALUES (?,?,?,?,?,'draft',0,?,?)`,
    [sku, normalized.name || item.name, slug, normalized.description || '', normalized.shortDescription || '', price, JSON.stringify({ origin:'supplier', supplierId:item.supplier_id, supplierItemId:item.id, sourceType:normalized.sourceType || null, categories:normalized.categories || [], attributes:normalized.attributes || [], images:normalized.images || [] })]
  );
  const [variantResult] = await db.execute(
    `INSERT INTO product_variants (product_id,sku,attributes_json,price,stock_quantity,status) VALUES (?,?,?,?,?,'active')`,
    [productResult.insertId, sku, JSON.stringify({ sourceAttributes:normalized.attributes || [] }), price, normalized.stockQuantity]
  );
  await upsertOffer({ item, normalized, productVariantId:variantResult.insertId });
  await audit({ actorType:'ai', action:'catalog.promote_supplier_item', entityType:'product', entityId:productResult.insertId, metadata:{ supplierId:item.supplier_id, supplierItemId:item.id } });
  return { productId:productResult.insertId, productVariantId:variantResult.insertId, sku };
}

async function upsertOffer({ item, normalized, productVariantId }) {
  await db.execute(
    `INSERT INTO supplier_offers (supplier_id,supplier_item_id,product_variant_id,supplier_sku,cost,stock_quantity,active)
     VALUES (?,?,?,?,?,?,1)
     ON DUPLICATE KEY UPDATE supplier_sku=VALUES(supplier_sku),cost=VALUES(cost),stock_quantity=VALUES(stock_quantity),active=1,updated_at=NOW()`,
    [item.supplier_id, item.id, productVariantId, normalized.externalSku || item.external_sku, normalized.currentPrice ?? normalized.regularPrice ?? null, normalized.stockQuantity]
  );
}
