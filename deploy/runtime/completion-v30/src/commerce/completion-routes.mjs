import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { db } from '../db.mjs';
import { createAdminProduct,getPublicProduct,listAdminProducts,listVariants,saveVariant,updateAdminProduct } from './catalog-admin-service.mjs';
import { addCartItem,cartDetails,checkoutCart,confirmPayment,createCart,getOrder,listOrders,quoteCart,removeCartItem,saveShipment,updateCartItem,updateOrderStatus } from './order-service.mjs';
import { addPrintAsset,createMockup,createPositioningCode,createPrint,deactivatePrintAsset,getProductMockupRules,listMockups,listPositioningCodes,listPrintAssets,listPrints,lockPositioningCode,removeMockupImage,saveProductMockupRule,startProcessing,transitionPrint,updateMockup } from './print-workflow-service.mjs';
import { parseJson } from './core-math.mjs';

const __dirname=path.dirname(fileURLToPath(import.meta.url));
const publicDir=path.resolve(__dirname,'../../public');
const cartToken=request=>String(request.headers['x-cart-token']||'').trim();
const sendError=(reply,error,code=400)=>reply.code(code).send({error:error.message});

export function registerCompletionRoutes(app,{requireAdmin,requireTenant,requireCustomer,requirePartner}){
  app.get('/api/public/products/:idOrSlug',{preHandler:requireTenant},async(request,reply)=>{const item=await getPublicProduct(request.tenant.id,request.params.idOrSlug);return item||reply.code(404).send({error:'product_not_found'});});

  app.post('/api/cart',{preHandler:requireTenant},async request=>createCart(request.tenant.id,null));
  app.get('/api/cart',{preHandler:requireTenant},async(request,reply)=>{try{return await cartDetails(request.tenant.id,cartToken(request));}catch(error){return sendError(reply,error,404);}});
  app.post('/api/cart/items',{preHandler:requireTenant},async(request,reply)=>{try{return await addCartItem(request.tenant.id,cartToken(request),request.body||{});}catch(error){return sendError(reply,error);}});
  app.put('/api/cart/items/:id',{preHandler:requireTenant},async(request,reply)=>{try{return await updateCartItem(request.tenant.id,cartToken(request),Number(request.params.id),request.body||{});}catch(error){return sendError(reply,error);}});
  app.delete('/api/cart/items/:id',{preHandler:requireTenant},async(request,reply)=>{try{return await removeCartItem(request.tenant.id,cartToken(request),Number(request.params.id));}catch(error){return sendError(reply,error);}});
  app.post('/api/checkout/quote',{preHandler:requireTenant},async(request,reply)=>{try{return await quoteCart(request.tenant.id,cartToken(request),request.body||{});}catch(error){return sendError(reply,error);}});
  app.post('/api/checkout',{preHandler:requireCustomer},async(request,reply)=>{try{return await checkoutCart(request.tenant.id,request.customer.id,cartToken(request),request.body||{});}catch(error){return sendError(reply,error);}});
  app.get('/api/customer/orders/:id',{preHandler:requireCustomer},async(request,reply)=>{const order=await getOrder(request.tenant.id,Number(request.params.id),request.customer.id);return order||reply.code(404).send({error:'order_not_found'});});

  app.get('/api/partner/orders/:id',{preHandler:requirePartner},async(request,reply)=>{const order=await getOrder(request.tenant.id,Number(request.params.id));return order||reply.code(404).send({error:'order_not_found'});});
  app.put('/api/partner/orders/:id/status',{preHandler:requirePartner},async(request,reply)=>{if(!['owner','admin','orders'].includes(request.partnerUser.role))return reply.code(403).send({error:'partner_forbidden'});try{return await updateOrderStatus(request.tenant.id,Number(request.params.id),String(request.body?.status||''),{actorType:'partner',actorId:String(request.partnerUser.id),note:request.body?.note});}catch(error){return sendError(reply,error);}});

  app.get('/api/admin/products',{preHandler:requireAdmin},async request=>({items:await listAdminProducts(request.query||{})}));
  app.post('/api/admin/products',{preHandler:requireAdmin},async(request,reply)=>{try{return await createAdminProduct(request.body||{});}catch(error){return sendError(reply,error);}});
  app.put('/api/admin/products/:id',{preHandler:requireAdmin},async(request,reply)=>{try{return await updateAdminProduct(Number(request.params.id),request.body||{});}catch(error){return sendError(reply,error);}});
  app.get('/api/admin/products/:id/variants',{preHandler:requireAdmin},async request=>({items:await listVariants(Number(request.params.id))}));
  app.post('/api/admin/products/:id/variants',{preHandler:requireAdmin},async(request,reply)=>{try{return await saveVariant(Number(request.params.id),request.body||{});}catch(error){return sendError(reply,error);}});

  app.get('/api/admin/orders',{preHandler:requireAdmin},async request=>({items:await listOrders(Number(request.query?.tenantId||1),request.query||{})}));
  app.get('/api/admin/orders/:id',{preHandler:requireAdmin},async(request,reply)=>{const tenantId=Number(request.query?.tenantId||1);const order=await getOrder(tenantId,Number(request.params.id));return order||reply.code(404).send({error:'order_not_found'});});
  app.put('/api/admin/orders/:id/status',{preHandler:requireAdmin},async(request,reply)=>{try{return await updateOrderStatus(Number(request.body?.tenantId||1),Number(request.params.id),String(request.body?.status||''),{note:request.body?.note});}catch(error){return sendError(reply,error);}});
  app.post('/api/admin/orders/:id/confirm-payment',{preHandler:requireAdmin},async(request,reply)=>{try{return await confirmPayment(Number(request.body?.tenantId||1),Number(request.params.id),request.body||{});}catch(error){return sendError(reply,error);}});
  app.post('/api/admin/orders/:id/shipments',{preHandler:requireAdmin},async(request,reply)=>{try{return await saveShipment(Number(request.body?.tenantId||1),Number(request.params.id),request.body||{});}catch(error){return sendError(reply,error);}});

  app.get('/api/admin/prints',{preHandler:requireAdmin},async request=>({items:await listPrints(request.query||{})}));
  app.post('/api/admin/prints',{preHandler:requireAdmin},async(request,reply)=>{try{return await createPrint(request.body||{});}catch(error){return sendError(reply,error);}});
  app.post('/api/admin/prints/:id/start-processing',{preHandler:requireAdmin},async(request,reply)=>{try{return await startProcessing(Number(request.params.id));}catch(error){return sendError(reply,error);}});
  app.post('/api/admin/prints/:id/transition',{preHandler:requireAdmin},async(request,reply)=>{try{return await transitionPrint(Number(request.params.id),String(request.body?.stage||''),request.body||{});}catch(error){return sendError(reply,error);}});
  app.get('/api/admin/prints/:id/assets',{preHandler:requireAdmin},async request=>({items:await listPrintAssets(Number(request.params.id))}));
  app.post('/api/admin/prints/:id/assets',{preHandler:requireAdmin},async(request,reply)=>{try{return await addPrintAsset(Number(request.params.id),request.body||{});}catch(error){return sendError(reply,error);}});
  app.delete('/api/admin/prints/:id/assets/:assetId',{preHandler:requireAdmin},async(request,reply)=>{try{return await deactivatePrintAsset(Number(request.params.id),Number(request.params.assetId));}catch(error){return sendError(reply,error);}});

  app.get('/api/admin/positioning-codes',{preHandler:requireAdmin},async request=>({items:await listPositioningCodes(request.query||{})}));
  app.post('/api/admin/positioning-codes',{preHandler:requireAdmin},async(request,reply)=>{try{return await createPositioningCode(request.body||{});}catch(error){return sendError(reply,error);}});
  app.put('/api/admin/positioning-codes/:code/lock',{preHandler:requireAdmin},async(request,reply)=>{try{return await lockPositioningCode(request.params.code,request.body?.locked!==false);}catch(error){return sendError(reply,error);}});

  app.get('/api/admin/mockups',{preHandler:requireAdmin},async()=>({items:await listMockups()}));
  app.post('/api/admin/mockups',{preHandler:requireAdmin},async(request,reply)=>{try{return await createMockup(request.body||{});}catch(error){return sendError(reply,error);}});
  app.put('/api/admin/mockups/:id',{preHandler:requireAdmin},async(request,reply)=>{try{return await updateMockup(Number(request.params.id),request.body||{});}catch(error){return sendError(reply,error);}});
  app.delete('/api/admin/mockups/:id/images/:imageKey',{preHandler:requireAdmin},async(request,reply)=>{try{return await removeMockupImage(Number(request.params.id),decodeURIComponent(request.params.imageKey));}catch(error){return sendError(reply,error);}});
  app.get('/api/admin/products/:id/mockup-rules',{preHandler:requireAdmin},async request=>({items:await getProductMockupRules(Number(request.params.id))}));
  app.put('/api/admin/products/:id/mockup-rules',{preHandler:requireAdmin},async(request,reply)=>{try{return {items:await saveProductMockupRule(Number(request.params.id),request.body||{})};}catch(error){return sendError(reply,error);}});

  app.get('/api/admin/reports/summary',{preHandler:requireAdmin},async request=>{
    const tenantId=Number(request.query?.tenantId||1);
    const [[orders],[products],[customers],[suppliers],[prints],[payments]] = await Promise.all([
      db.execute(`SELECT COUNT(*) total,COALESCE(SUM(CASE WHEN status NOT IN ('cancelled','refunded') THEN grand_total ELSE 0 END),0) gross,COALESCE(SUM(CASE WHEN status IN ('paid','processing','partially_fulfilled','fulfilled') THEN grand_total ELSE 0 END),0) recognized FROM orders WHERE tenant_id=?`,[tenantId]),
      db.execute(`SELECT COUNT(*) total,SUM(status='published') published FROM products`),db.execute(`SELECT COUNT(*) total FROM customers WHERE tenant_id=?`,[tenantId]),db.execute(`SELECT COUNT(*) total,SUM(status='active') active FROM suppliers`),db.execute(`SELECT COUNT(*) total,SUM(status='published') published FROM prints`),db.execute(`SELECT COUNT(*) total,SUM(status='paid') paid,COALESCE(SUM(CASE WHEN status='paid' THEN amount ELSE 0 END),0) amount FROM payment_transactions WHERE tenant_id=?`,[tenantId])
    ]);
    return {tenantId,orders:orders[0],products:products[0],customers:customers[0],suppliers:suppliers[0],prints:prints[0],payments:payments[0]};
  });

  app.get('/api/admin/marketing/jobs',{preHandler:requireAdmin},async request=>{const tenantId=Number(request.query?.tenantId||1);const [rows]=await db.execute(`SELECT * FROM marketing_jobs WHERE tenant_id=? ORDER BY id DESC LIMIT 200`,[tenantId]);return{items:rows.map(r=>({...r,content:parseJson(r.content_json,{})}))};});
  app.post('/api/admin/marketing/jobs',{preHandler:requireAdmin},async(request,reply)=>{try{const tenantId=Number(request.body?.tenantId||1);const channel=String(request.body?.channel||'').trim();if(!channel)throw new Error('channel is required');const [r]=await db.execute(`INSERT INTO marketing_jobs (tenant_id,channel,job_type,status,content_json,scheduled_at) VALUES (?,?,?,'draft',?,?)`,[tenantId,channel,request.body?.jobType||'publish',JSON.stringify(request.body?.content||{}),request.body?.scheduledAt||null]);return{id:r.insertId,status:'draft'};}catch(error){return sendError(reply,error);}});

  app.get('/api/admin/completion',{preHandler:requireAdmin},async()=>{
    const required=['carts','cart_items','order_addresses','order_status_history','print_workflow','print_assets','positioning_codes','marketing_jobs'];
    const [tables]=await db.query(`SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE()`);const have=new Set(tables.map(r=>r.TABLE_NAME||r.table_name));
    const [[products],[gateways],[carriers]] = await Promise.all([db.query(`SELECT COUNT(*) total,SUM(status='published') published FROM products`),db.query(`SELECT provider,enabled,sandbox FROM payment_gateways WHERE tenant_id=1 ORDER BY provider`),db.query(`SELECT provider,enabled FROM shipping_carriers WHERE tenant_id=1 ORDER BY provider`)]);
    return {codeComplete:required.every(x=>have.has(x)),missingTables:required.filter(x=>!have.has(x)),catalog:products[0],paymentGateways:gateways,shippingCarriers:carriers,externalActivationNote:'External providers require valid account credentials and live/sandbox validation before real money or carrier operations.'};
  });

  app.get('/storefront.js',async(_request,reply)=>reply.type('application/javascript').send(await fs.readFile(path.join(publicDir,'storefront.js'),'utf8')));
  app.get('/operations.js',async(_request,reply)=>reply.type('application/javascript').send(await fs.readFile(path.join(publicDir,'operations.js'),'utf8')));
}
