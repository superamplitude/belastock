import crypto from 'node:crypto';
import { db } from '../db.mjs';
import { audit } from '../audit.mjs';
import { canTransitionOrder,computeOrderTotals,normalizeQuantity,parseJson } from './core-math.mjs';

const hash=value=>crypto.createHash('sha256').update(String(value)).digest('hex');
const newToken=()=>crypto.randomBytes(32).toString('base64url');
const orderNumber=tenantId=>`BS${tenantId}-${new Date().toISOString().slice(0,10).replaceAll('-','')}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;

async function currentProduct(tenantId,productId,variantId=null){
  const [pRows]=await db.execute(`SELECT p.id,p.sku,p.name,p.status,p.customizable,p.price,l.price_override,l.enabled,l.store_name,l.store_slug
    FROM tenant_product_listings l JOIN products p ON p.id=l.product_id
    WHERE l.tenant_id=? AND p.id=? AND l.enabled=1 AND p.status='published' LIMIT 1`,[tenantId,productId]);
  const product=pRows[0];if(!product)throw new Error('Product unavailable');
  let variant=null;
  if(variantId){const [v]=await db.execute(`SELECT * FROM product_variants WHERE id=? AND product_id=? AND status='active' LIMIT 1`,[variantId,productId]);variant=v[0];if(!variant)throw new Error('Variant unavailable');}
  else{const [v]=await db.execute(`SELECT * FROM product_variants WHERE product_id=? AND status='active' ORDER BY id LIMIT 1`,[productId]);variant=v[0]||null;}
  const price=Number(product.price_override??variant?.price??product.price??0);
  if(!Number.isFinite(price)||price<0)throw new Error('Product has no valid selling price');
  return {product,variant,price};
}

export async function createCart(tenantId,customerId=null){
  const token=newToken();const [r]=await db.execute(`INSERT INTO carts (tenant_id,customer_id,token_hash,status,currency,expires_at) VALUES (?,?,?,'active','BRL',DATE_ADD(NOW(),INTERVAL 30 DAY))`,[tenantId,customerId||null,hash(token)]);return{id:r.insertId,token};
}

async function cartRow(tenantId,token){
  if(!token)return null;const [rows]=await db.execute(`SELECT * FROM carts WHERE tenant_id=? AND token_hash=? AND status='active' AND expires_at>NOW() LIMIT 1`,[tenantId,hash(token)]);return rows[0]||null;
}

async function requireCart(tenantId,token){const cart=await cartRow(tenantId,token);if(!cart)throw new Error('Cart not found or expired');return cart;}

export async function cartDetails(tenantId,token){
  const cart=await requireCart(tenantId,token);
  const [items]=await db.execute(`SELECT ci.id,ci.product_id,ci.variant_id,ci.print_id,ci.quantity,ci.unit_price,ci.customization_json,
    COALESCE(l.store_name,p.name) product_name,p.sku product_sku,v.sku variant_sku,v.attributes_json,v.stock_quantity,pr.name print_name,pr.code print_code
    FROM cart_items ci JOIN products p ON p.id=ci.product_id JOIN tenant_product_listings l ON l.product_id=p.id AND l.tenant_id=?
    LEFT JOIN product_variants v ON v.id=ci.variant_id LEFT JOIN prints pr ON pr.id=ci.print_id
    WHERE ci.cart_id=? ORDER BY ci.id`,[tenantId,cart.id]);
  const normalized=items.map(i=>({...i,customization:parseJson(i.customization_json,{}),attributes:parseJson(i.attributes_json,{})}));
  return {cart:{id:cart.id,currency:cart.currency,expiresAt:cart.expires_at},items:normalized,totals:computeOrderTotals(normalized,0,0)};
}

export async function addCartItem(tenantId,token,input={}){
  const cart=await requireCart(tenantId,token);const quantity=normalizeQuantity(input.quantity||1);const productId=Number(input.productId);if(!productId)throw new Error('productId is required');
  const {product,variant,price}=await currentProduct(tenantId,productId,input.variantId?Number(input.variantId):null);
  if(variant?.stock_quantity!=null&&Number(variant.stock_quantity)<quantity)throw new Error('Insufficient stock');
  let printId=input.printId?Number(input.printId):null;
  if(printId){if(!product.customizable)throw new Error('Product is not customizable');const [pr]=await db.execute(`SELECT id FROM prints WHERE id=? AND status='published' LIMIT 1`,[printId]);if(!pr[0])throw new Error('Print unavailable');}
  const [r]=await db.execute(`INSERT INTO cart_items (cart_id,product_id,variant_id,print_id,quantity,unit_price,customization_json) VALUES (?,?,?,?,?,?,?)`,[cart.id,productId,variant?.id||null,printId,quantity,price,JSON.stringify(input.customization||{})]);
  return {id:r.insertId,...await cartDetails(tenantId,token)};
}

export async function updateCartItem(tenantId,token,itemId,input={}){const cart=await requireCart(tenantId,token);const quantity=normalizeQuantity(input.quantity);const [rows]=await db.execute(`SELECT ci.*,v.stock_quantity FROM cart_items ci LEFT JOIN product_variants v ON v.id=ci.variant_id WHERE ci.id=? AND ci.cart_id=? LIMIT 1`,[itemId,cart.id]);if(!rows[0])throw new Error('Cart item not found');if(rows[0].stock_quantity!=null&&Number(rows[0].stock_quantity)<quantity)throw new Error('Insufficient stock');await db.execute(`UPDATE cart_items SET quantity=?,customization_json=? WHERE id=?`,[quantity,JSON.stringify(input.customization??parseJson(rows[0].customization_json,{})),itemId]);return cartDetails(tenantId,token);}
export async function removeCartItem(tenantId,token,itemId){const cart=await requireCart(tenantId,token);await db.execute(`DELETE FROM cart_items WHERE id=? AND cart_id=?`,[itemId,cart.id]);return cartDetails(tenantId,token);}

async function supplierShippingForItems(items){let total=0;let has=false;for(const item of items){if(!item.variant_id)continue;const [rows]=await db.execute(`SELECT shipping_estimate FROM supplier_offers WHERE product_variant_id=? AND active=1 AND (stock_quantity IS NULL OR stock_quantity>=?) ORDER BY score DESC,cost ASC LIMIT 1`,[item.variant_id,item.quantity]);if(rows[0]&&rows[0].shipping_estimate!=null){total+=Number(rows[0].shipping_estimate);has=true;}}return has?Math.max(0,total):null;}

export async function shippingOptions(tenantId,items){
  const [rows]=await db.execute(`SELECT id,provider,name,config_json FROM shipping_carriers WHERE tenant_id=? AND enabled=1 ORDER BY id`,[tenantId]);
  const options=[];
  for(const row of rows){const cfg=parseJson(row.config_json,{});let price=null;let estimateDays=cfg.estimateDays??null;
    if(row.provider==='pickup')price=0;
    else if(row.provider==='supplier')price=await supplierShippingForItems(items);
    else if(cfg.flatRate!=null||cfg.price!=null)price=Number(cfg.flatRate??cfg.price);
    options.push({carrierId:row.id,provider:row.provider,name:row.name,price:price==null?null:Math.max(0,Number(price)),estimateDays,available:price!=null,requiresExternalQuote:price==null});
  }
  if(!options.some(o=>o.provider==='pickup'))options.push({carrierId:null,provider:'pickup',name:'Retirada no local',price:0,estimateDays:0,available:true,requiresExternalQuote:false});
  return options;
}

export async function quoteCart(tenantId,token,input={}){
  const details=await cartDetails(tenantId,token);if(!details.items.length)throw new Error('Cart is empty');const options=await shippingOptions(tenantId,details.items);
  const wanted=String(input.shippingMethod||'pickup');const selected=options.find(o=>String(o.carrierId)===wanted||o.provider===wanted) || options.find(o=>o.provider==='pickup');if(!selected?.available)throw new Error('Selected shipping method requires an external quote/configuration');
  return {...details,shippingOptions:options,selectedShipping:selected,totals:computeOrderTotals(details.items,selected.price,0)};
}

async function customerSnapshot(tenantId,customerId){const [rows]=await db.execute(`SELECT id,name,email,phone,document FROM customers WHERE id=? AND tenant_id=? AND status='active' LIMIT 1`,[customerId,tenantId]);if(!rows[0])throw new Error('Customer not found');return rows[0];}
async function resolveAddress(customerId,input={}){if(input.addressId){const [rows]=await db.execute(`SELECT * FROM customer_addresses WHERE id=? AND customer_id=? LIMIT 1`,[Number(input.addressId),customerId]);if(!rows[0])throw new Error('Address not found');return rows[0];}if(input.address){const a=input.address;if(!a.postalCode||!a.street||!a.city||!a.state)throw new Error('Complete shipping address is required');return{recipient:a.recipient||null,postal_code:a.postalCode,street:a.street,number:a.number||null,complement:a.complement||null,district:a.district||null,city:a.city,state:a.state,country:a.country||'BR'};}return null;}

export async function checkoutCart(tenantId,customerId,token,input={}){
  const cart=await requireCart(tenantId,token);if(cart.customer_id&&Number(cart.customer_id)!==Number(customerId))throw new Error('Cart belongs to another customer');
  const quote=await quoteCart(tenantId,token,input);const customer=await customerSnapshot(tenantId,customerId);const shipping=quote.selectedShipping;const address=shipping.provider==='pickup'?null:await resolveAddress(customerId,input);
  if(shipping.provider!=='pickup'&&!address)throw new Error('Shipping address is required');
  const paymentProvider=String(input.paymentProvider||'manual_pix');
  const [gateways]=await db.execute(`SELECT id,provider,display_name,config_json,sandbox FROM payment_gateways WHERE tenant_id=? AND provider=? AND enabled=1 LIMIT 1`,[tenantId,paymentProvider]);
  const gateway=gateways[0];if(!gateway&&paymentProvider!=='manual_pix')throw new Error('Payment provider is not enabled for this store');
  const conn=await db.getConnection();let orderId;
  try{
    await conn.beginTransaction();
    const number=orderNumber(tenantId);const totals=quote.totals;
    const [or]=await conn.execute(`INSERT INTO orders (tenant_id,customer_id,order_number,status,currency,customer_json,subtotal,shipping_total,discount_total,grand_total) VALUES (?,? ,?,'pending','BRL',?,?,?,?,?)`,[tenantId,customerId,number,JSON.stringify(customer),totals.subtotal,totals.shippingTotal,totals.discountTotal,totals.grandTotal]);orderId=or.insertId;
    for(const item of quote.items){
      const current=await currentProduct(tenantId,item.product_id,item.variant_id);if(Number(current.price)!==Number(item.unit_price))throw new Error(`Price changed for product ${item.product_id}; refresh cart`);
      if(item.variant_id){const [stock]=await conn.execute(`UPDATE product_variants SET stock_quantity=CASE WHEN stock_quantity IS NULL THEN NULL ELSE stock_quantity-? END WHERE id=? AND (stock_quantity IS NULL OR stock_quantity>=?)`,[item.quantity,item.variant_id,item.quantity]);if(!stock.affectedRows)throw new Error(`Insufficient stock for variant ${item.variant_id}`);}
      await conn.execute(`INSERT INTO order_items (order_id,product_id,variant_id,print_id,quantity,unit_price,customization_json,routing_json) VALUES (?,?,?,?,?,?,?,?)`,[orderId,item.product_id,item.variant_id,item.print_id,item.quantity,item.unit_price,JSON.stringify(item.customization||{}),JSON.stringify({status:'unrouted'})]);
    }
    if(address)await conn.execute(`INSERT INTO order_addresses (order_id,address_type,recipient,postal_code,street,number,complement,district,city,state,country) VALUES (?,'shipping',?,?,?,?,?,?,?,?,?,?)`,[orderId,address.recipient||customer.name,address.postal_code,address.street,address.number||null,address.complement||null,address.district||null,address.city,address.state,address.country||'BR']);
    await conn.execute(`INSERT INTO payment_transactions (tenant_id,order_id,payment_gateway_id,status,amount,currency,method,payload_json) VALUES (?,?,?,'pending',?,'BRL',?,?)`,[tenantId,orderId,gateway?.id||null,totals.grandTotal,paymentProvider,JSON.stringify({checkout:'v3',sandbox:Boolean(gateway?.sandbox)})]);
    await conn.execute(`INSERT INTO shipments (tenant_id,order_id,shipping_carrier_id,service_code,status,shipping_cost,estimate_days,payload_json) VALUES (?,?,?,?,?,?,?,?)`,[tenantId,orderId,shipping.carrierId||null,shipping.provider,'pending',shipping.price,shipping.estimateDays,JSON.stringify({provider:shipping.provider,name:shipping.name})]);
    await conn.execute(`INSERT INTO order_status_history (order_id,from_status,to_status,actor_type,actor_id,note) VALUES (?,NULL,'pending','customer',?,'Checkout criado')`,[orderId,String(customerId)]);
    await conn.execute(`UPDATE carts SET status='converted',customer_id=? WHERE id=?`,[customerId,cart.id]);
    await conn.commit();
    const config=parseJson(gateway?.config_json,{});
    await audit({actorType:'customer',actorId:String(customerId),action:'checkout.create',entityType:'order',entityId:orderId,metadata:{tenantId,paymentProvider,shipping:shipping.provider}});
    return {orderId,orderNumber:number,status:'pending',totals,payment:{provider:paymentProvider,status:'pending',displayName:gateway?.display_name||'PIX manual',instructions:config.instructions||'Pagamento aguardando confirmação.',pixKey:config.pixKey||null},shipping};
  }catch(error){await conn.rollback();throw error;}finally{conn.release();}
}

export async function getOrder(tenantId,orderId,customerId=null){
  const params=[tenantId,orderId];let scope='';if(customerId){scope=' AND o.customer_id=?';params.push(customerId);}
  const [orders]=await db.execute(`SELECT o.* FROM orders o WHERE o.tenant_id=? AND o.id=?${scope} LIMIT 1`,params);const order=orders[0];if(!order)return null;
  const [[items],[addresses],[payments],[shipments],[history],[supplierOrders]] = await Promise.all([
    db.execute(`SELECT oi.*,p.name product_name,p.sku product_sku,v.sku variant_sku,pr.name print_name FROM order_items oi JOIN products p ON p.id=oi.product_id LEFT JOIN product_variants v ON v.id=oi.variant_id LEFT JOIN prints pr ON pr.id=oi.print_id WHERE oi.order_id=? ORDER BY oi.id`,[orderId]),
    db.execute(`SELECT * FROM order_addresses WHERE order_id=?`,[orderId]),db.execute(`SELECT pt.id,pt.status,pt.amount,pt.currency,pt.method,pt.provider_transaction_id,pt.created_at,pt.updated_at,pg.display_name gateway_name FROM payment_transactions pt LEFT JOIN payment_gateways pg ON pg.id=pt.payment_gateway_id WHERE pt.order_id=? ORDER BY pt.id`,[orderId]),
    db.execute(`SELECT s.*,sc.name carrier_name,sc.provider carrier_provider FROM shipments s LEFT JOIN shipping_carriers sc ON sc.id=s.shipping_carrier_id WHERE s.order_id=? ORDER BY s.id`,[orderId]),
    db.execute(`SELECT * FROM order_status_history WHERE order_id=? ORDER BY id`,[orderId]),db.execute(`SELECT so.*,s.name supplier_name FROM supplier_orders so JOIN suppliers s ON s.id=so.supplier_id WHERE so.order_id=? ORDER BY so.id`,[orderId])
  ]);
  return {...order,customer:parseJson(order.customer_json,{}),items:items.map(i=>({...i,customization:parseJson(i.customization_json,{}),routing:parseJson(i.routing_json,{})})),addresses,payments,shipments:shipments.map(s=>({...s,payload:parseJson(s.payload_json,{})})),history,supplierOrders:supplierOrders.map(s=>({...s,payload:parseJson(s.payload_json,{})}))};
}

export async function listOrders(tenantId,query={}){const status=String(query.status||'').trim();const limit=Math.min(Math.max(Number(query.limit||100),1),500);const params=[tenantId];let where='';if(status){where=' AND status=?';params.push(status);}params.push(limit);const [rows]=await db.execute(`SELECT id,order_number,status,currency,subtotal,shipping_total,discount_total,grand_total,customer_id,created_at,updated_at FROM orders WHERE tenant_id=?${where} ORDER BY id DESC LIMIT ?`,params);return rows;}

async function routeSupplierOrders(orderId){
  const [items]=await db.execute(`SELECT * FROM order_items WHERE order_id=?`,[orderId]);const groups=new Map();
  for(const item of items){if(!item.variant_id){await db.execute(`UPDATE order_items SET routing_json=? WHERE id=?`,[JSON.stringify({status:'platform_stock'}),item.id]);continue;}
    const [offers]=await db.execute(`SELECT so.*,s.name supplier_name FROM supplier_offers so JOIN suppliers s ON s.id=so.supplier_id WHERE so.product_variant_id=? AND so.active=1 AND s.enabled=1 AND s.status='active' AND (so.stock_quantity IS NULL OR so.stock_quantity>=?) ORDER BY so.score DESC,so.cost ASC LIMIT 1`,[item.variant_id,item.quantity]);const offer=offers[0];
    if(!offer){await db.execute(`UPDATE order_items SET routing_json=? WHERE id=?`,[JSON.stringify({status:'manual_review',reason:'no_active_supplier_offer'}),item.id]);continue;}
    const line={orderItemId:item.id,variantId:item.variant_id,quantity:item.quantity,supplierSku:offer.supplier_sku,cost:offer.cost,offerId:offer.id};if(!groups.has(offer.supplier_id))groups.set(offer.supplier_id,[]);groups.get(offer.supplier_id).push(line);await db.execute(`UPDATE order_items SET routing_json=? WHERE id=?`,[JSON.stringify({status:'supplier',supplierId:offer.supplier_id,offerId:offer.id}),item.id]);
  }
  for(const [supplierId,lines] of groups){const [existing]=await db.execute(`SELECT id FROM supplier_orders WHERE order_id=? AND supplier_id=? LIMIT 1`,[orderId,supplierId]);if(!existing[0])await db.execute(`INSERT INTO supplier_orders (order_id,supplier_id,status,payload_json) VALUES (?,?,'pending',?)`,[orderId,supplierId,JSON.stringify({items:lines,source:'belastock-routing-v3'})]);}
}

export async function confirmPayment(tenantId,orderId,input={}){
  const order=await getOrder(tenantId,orderId);if(!order)throw new Error('Order not found');if(order.status==='cancelled'||order.status==='refunded')throw new Error('Order cannot be paid in current status');
  const conn=await db.getConnection();try{await conn.beginTransaction();if(input.transactionId)await conn.execute(`UPDATE payment_transactions SET status='paid',provider_transaction_id=COALESCE(?,provider_transaction_id),response_json=? WHERE id=? AND tenant_id=? AND order_id=?`,[input.providerTransactionId||null,JSON.stringify(input.response||{confirmedBy:'admin'}),Number(input.transactionId),tenantId,orderId]);else await conn.execute(`UPDATE payment_transactions SET status='paid',provider_transaction_id=COALESCE(?,provider_transaction_id),response_json=? WHERE tenant_id=? AND order_id=? AND status='pending'`,[input.providerTransactionId||null,JSON.stringify(input.response||{confirmedBy:'admin'}),tenantId,orderId]);if(order.status==='pending'){await conn.execute(`UPDATE orders SET status='paid' WHERE id=?`,[orderId]);await conn.execute(`INSERT INTO order_status_history (order_id,from_status,to_status,actor_type,actor_id,note) VALUES (?,'pending','paid','admin','admin',?)`,[orderId,input.note||'Pagamento confirmado']);}await conn.commit();}catch(error){await conn.rollback();throw error;}finally{conn.release();}
  await routeSupplierOrders(orderId);await audit({actorType:'admin',action:'payment.confirm',entityType:'order',entityId:orderId,metadata:{tenantId}});return getOrder(tenantId,orderId);
}

export async function updateOrderStatus(tenantId,orderId,toStatus,input={}){
  const [rows]=await db.execute(`SELECT status FROM orders WHERE id=? AND tenant_id=? LIMIT 1`,[orderId,tenantId]);const current=rows[0]?.status;if(!current)throw new Error('Order not found');if(!canTransitionOrder(current,toStatus))throw new Error(`Invalid order transition: ${current} -> ${toStatus}`);
  const conn=await db.getConnection();try{await conn.beginTransaction();if(toStatus==='cancelled'&&current!=='cancelled'){const [items]=await conn.execute(`SELECT variant_id,quantity FROM order_items WHERE order_id=? AND variant_id IS NOT NULL`,[orderId]);for(const item of items)await conn.execute(`UPDATE product_variants SET stock_quantity=CASE WHEN stock_quantity IS NULL THEN NULL ELSE stock_quantity+? END WHERE id=?`,[item.quantity,item.variant_id]);await conn.execute(`UPDATE payment_transactions SET status=CASE WHEN status='paid' THEN 'refund_required' ELSE 'cancelled' END WHERE order_id=?`,[orderId]);}
    await conn.execute(`UPDATE orders SET status=? WHERE id=?`,[toStatus,orderId]);await conn.execute(`INSERT INTO order_status_history (order_id,from_status,to_status,actor_type,actor_id,note) VALUES (?,?,?,?,?,?)`,[orderId,current,toStatus,input.actorType||'admin',input.actorId||'admin',input.note||null]);await conn.commit();
  }catch(error){await conn.rollback();throw error;}finally{conn.release();}
  await audit({actorType:input.actorType||'admin',actorId:input.actorId||'admin',action:'order.status',entityType:'order',entityId:orderId,before:{status:current},after:{status:toStatus}});return getOrder(tenantId,orderId);
}

export async function saveShipment(tenantId,orderId,input={}){const order=await getOrder(tenantId,orderId);if(!order)throw new Error('Order not found');let id=input.id?Number(input.id):null;if(id){await db.execute(`UPDATE shipments SET shipping_carrier_id=?,external_shipment_id=?,service_code=?,status=?,tracking_code=?,shipping_cost=?,label_url=?,estimate_days=?,payload_json=?,response_json=? WHERE id=? AND tenant_id=? AND order_id=?`,[input.shippingCarrierId??null,input.externalShipmentId??null,input.serviceCode??null,input.status||'pending',input.trackingCode??null,input.shippingCost??null,input.labelUrl??null,input.estimateDays??null,JSON.stringify(input.payload||{}),JSON.stringify(input.response||{}),id,tenantId,orderId]);}else{const [r]=await db.execute(`INSERT INTO shipments (tenant_id,order_id,shipping_carrier_id,external_shipment_id,service_code,status,tracking_code,shipping_cost,label_url,estimate_days,payload_json,response_json) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`,[tenantId,orderId,input.shippingCarrierId??null,input.externalShipmentId??null,input.serviceCode??null,input.status||'pending',input.trackingCode??null,input.shippingCost??null,input.labelUrl??null,input.estimateDays??null,JSON.stringify(input.payload||{}),JSON.stringify(input.response||{})]);id=r.insertId;}
  if(input.status==='delivered'||input.status==='fulfilled')await updateOrderStatus(tenantId,orderId,'fulfilled',{actorType:'admin',actorId:'admin',note:'Entrega concluída'}).catch(()=>{});return{id};}
