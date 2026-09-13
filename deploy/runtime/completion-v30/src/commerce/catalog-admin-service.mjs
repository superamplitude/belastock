import { db } from '../db.mjs';
import { audit } from '../audit.mjs';
import { parseJson } from './core-math.mjs';

const slugify=value=>String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/(^-|-$)/g,'');
const cleanSku=value=>String(value||'').trim().toUpperCase().replace(/[^A-Z0-9_-]+/g,'-').replace(/^-+|-+$/g,'');

export async function listAdminProducts(query={}) {
  const status=String(query.status||'').trim();
  const term=String(query.q||'').trim();
  const limit=Math.min(Math.max(Number(query.limit||100),1),500);
  const where=[]; const params=[];
  if(status){where.push('p.status=?');params.push(status);}
  if(term){where.push('(p.name LIKE ? OR p.sku LIKE ? OR p.slug LIKE ?)');const like=`%${term}%`;params.push(like,like,like);}
  params.push(limit);
  const [rows]=await db.execute(`SELECT p.*,COUNT(v.id) variant_count,COALESCE(SUM(v.stock_quantity),0) total_stock
    FROM products p LEFT JOIN product_variants v ON v.product_id=p.id
    ${where.length?'WHERE '+where.join(' AND '):''}
    GROUP BY p.id ORDER BY p.id DESC LIMIT ?`,params);
  return rows.map(r=>({...r,metadata:parseJson(r.metadata_json,{})}));
}

export async function getPublicProduct(tenantId,idOrSlug) {
  const numeric=/^\d+$/.test(String(idOrSlug));
  const [rows]=await db.execute(`SELECT p.id,p.sku,COALESCE(l.store_name,p.name) name,COALESCE(l.store_slug,p.slug) slug,p.description,p.short_description,p.customizable,
      COALESCE(l.price_override,p.price) price,COALESCE(l.compare_at_override,p.compare_at_price) compare_at_price,p.metadata_json,l.source_mode
    FROM tenant_product_listings l JOIN products p ON p.id=l.product_id
    WHERE l.tenant_id=? AND l.enabled=1 AND p.status='published' AND ${numeric?'p.id=?':'l.store_slug=?'} LIMIT 1`,[tenantId,numeric?Number(idOrSlug):String(idOrSlug)]);
  const product=rows[0]; if(!product) return null;
  const [[variants],[shipping],[rules]] = await Promise.all([
    db.execute(`SELECT id,sku,attributes_json,COALESCE(price,?) price,stock_quantity,status FROM product_variants WHERE product_id=? AND status='active' ORDER BY id`,[product.price,product.id]),
    db.execute(`SELECT * FROM product_shipping_rules WHERE product_id=? LIMIT 1`,[product.id]),
    db.execute(`SELECT r.template_id,r.allowed_positions_json,r.position_prices_json,m.name template_name,m.product_type,m.color_images_json,m.zones_json
      FROM product_mockup_rules r JOIN mockup_templates m ON m.id=r.template_id WHERE r.product_id=?`,[product.id])
  ]);
  return {...product,metadata:parseJson(product.metadata_json,{}),variants:variants.map(v=>({...v,attributes:parseJson(v.attributes_json,{})})),shipping:shipping[0]||null,mockups:rules.map(r=>({...r,allowedPositions:parseJson(r.allowed_positions_json,[]),positionPrices:parseJson(r.position_prices_json,{}),colorImages:parseJson(r.color_images_json,[]),zones:parseJson(r.zones_json,[])}))};
}

export async function createAdminProduct(input={}) {
  const name=String(input.name||'').trim(); if(!name) throw new Error('Product name is required');
  const sku=cleanSku(input.sku||`BS-${Date.now()}`); if(!sku) throw new Error('Invalid SKU');
  const slug=slugify(input.slug||name)||`produto-${Date.now()}`;
  const price=input.price==null?null:Number(input.price); if(price!=null&&(!Number.isFinite(price)||price<0)) throw new Error('Invalid price');
  const status=['draft','published','paused','archived'].includes(input.status)?input.status:'draft';
  const conn=await db.getConnection();
  try{
    await conn.beginTransaction();
    const [r]=await conn.execute(`INSERT INTO products (owner_tenant_id,sku,name,slug,description,short_description,status,customizable,price,compare_at_price,cost_floor,margin_floor_pct,metadata_json)
      VALUES (1,?,?,?,?,?,?,?,?,?,?,?,?)`,[sku,name,slug,input.description||'',input.shortDescription||'',status,input.customizable?1:0,price,input.compareAtPrice??null,input.costFloor??null,input.marginFloorPct??null,JSON.stringify(input.metadata||{})]);
    const productId=r.insertId;
    const variantSku=cleanSku(input.variantSku||`${sku}-01`);
    await conn.execute(`INSERT INTO product_variants (product_id,sku,attributes_json,price,stock_quantity,status) VALUES (?,?,?,?,?,'active')`,[productId,variantSku,JSON.stringify(input.attributes||{}),price,input.stockQuantity??null]);
    await conn.execute(`INSERT INTO tenant_product_listings (tenant_id,product_id,source_mode,enabled,store_name,store_slug,price_override,compare_at_override,metadata_json)
      VALUES (1,?,'platform',1,?,?,?,?,?)`,[productId,name,slug,price,input.compareAtPrice??null,JSON.stringify(input.listingMetadata||{})]);
    await conn.commit();
    await audit({actorType:'admin',action:'product.create',entityType:'product',entityId:productId,after:{sku,name,slug,status,price}});
    return {id:productId,sku,slug};
  }catch(error){await conn.rollback();throw error;}finally{conn.release();}
}

export async function updateAdminProduct(productId,input={}) {
  const [rows]=await db.execute(`SELECT * FROM products WHERE id=? LIMIT 1`,[productId]); const p=rows[0]; if(!p) throw new Error('Product not found');
  const name=input.name===undefined?p.name:String(input.name||'').trim(); if(!name) throw new Error('Product name is required');
  const status=input.status===undefined?p.status:String(input.status); if(!['draft','published','paused','archived'].includes(status)) throw new Error('Invalid product status');
  const price=input.price===undefined?p.price:(input.price==null?null:Number(input.price)); if(price!=null&&(!Number.isFinite(price)||price<0)) throw new Error('Invalid price');
  const slug=input.slug===undefined?p.slug:(slugify(input.slug)||p.slug);
  const metadata=input.metadata===undefined?parseJson(p.metadata_json,{}):input.metadata;
  await db.execute(`UPDATE products SET name=?,slug=?,description=?,short_description=?,status=?,customizable=?,price=?,compare_at_price=?,cost_floor=?,margin_floor_pct=?,metadata_json=? WHERE id=?`,[
    name,slug,input.description??p.description,input.shortDescription??p.short_description,status,input.customizable===undefined?p.customizable:(input.customizable?1:0),price,input.compareAtPrice===undefined?p.compare_at_price:input.compareAtPrice,input.costFloor===undefined?p.cost_floor:input.costFloor,input.marginFloorPct===undefined?p.margin_floor_pct:input.marginFloorPct,JSON.stringify(metadata||{}),productId
  ]);
  if(input.storeName!==undefined||input.storeSlug!==undefined||input.price!==undefined||input.compareAtPrice!==undefined){
    await db.execute(`UPDATE tenant_product_listings SET store_name=COALESCE(?,store_name),store_slug=COALESCE(?,store_slug),price_override=?,compare_at_override=? WHERE tenant_id=1 AND product_id=?`,[
      input.storeName??null,input.storeSlug?slugify(input.storeSlug):null,price,input.compareAtPrice===undefined?p.compare_at_price:input.compareAtPrice,productId
    ]);
  }
  await audit({actorType:'admin',action:'product.update',entityType:'product',entityId:productId,before:{status:p.status,price:p.price},after:{status,price}});
  return {ok:true};
}

export async function listVariants(productId){const [rows]=await db.execute(`SELECT * FROM product_variants WHERE product_id=? ORDER BY id`,[productId]);return rows.map(r=>({...r,attributes:parseJson(r.attributes_json,{})}));}

export async function saveVariant(productId,input={}){
  const [products]=await db.execute(`SELECT id,sku,price FROM products WHERE id=? LIMIT 1`,[productId]);if(!products[0])throw new Error('Product not found');
  if(input.id){
    const [rows]=await db.execute(`SELECT * FROM product_variants WHERE id=? AND product_id=? LIMIT 1`,[Number(input.id),productId]);const v=rows[0];if(!v)throw new Error('Variant not found');
    await db.execute(`UPDATE product_variants SET sku=?,attributes_json=?,price=?,stock_quantity=?,status=? WHERE id=?`,[
      cleanSku(input.sku||v.sku),JSON.stringify(input.attributes??parseJson(v.attributes_json,{})),input.price===undefined?v.price:input.price,input.stockQuantity===undefined?v.stock_quantity:input.stockQuantity,['active','paused','archived'].includes(input.status)?input.status:v.status,v.id
    ]);return {id:v.id};
  }
  const sku=cleanSku(input.sku||`${products[0].sku}-${Date.now().toString(36)}`);
  const [r]=await db.execute(`INSERT INTO product_variants (product_id,sku,attributes_json,price,stock_quantity,status) VALUES (?,?,?,?,?,?)`,[productId,sku,JSON.stringify(input.attributes||{}),input.price??products[0].price,input.stockQuantity??null,['active','paused','archived'].includes(input.status)?input.status:'active']);
  return {id:r.insertId};
}
