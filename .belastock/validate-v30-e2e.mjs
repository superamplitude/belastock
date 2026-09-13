import fs from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const site='/home/lojabelastock/htdocs/belastock.com.br';
const envText=await fs.readFile(`${site}/.env`,'utf8');
for(const raw of envText.split(/\r?\n/)){
  const line=raw.trim();if(!line||line.startsWith('#'))continue;
  const i=line.indexOf('=');if(i<=0)continue;
  const key=line.slice(0,i).trim();let value=line.slice(i+1).trim();
  if((value.startsWith('"')&&value.endsWith('"'))||(value.startsWith("'")&&value.endsWith("'")))value=value.slice(1,-1);
  if(process.env[key]===undefined)process.env[key]=value;
}

const load=rel=>import(pathToFileURL(`${site}/${rel}`).href+`?e2e=${Date.now()}-${Math.random()}`);
const {db}=await load('src/db.mjs');
const {createAdminProduct,listVariants}=await load('src/commerce/catalog-admin-service.mjs');
const {registerCustomer,loginCustomer,logoutCustomer}=await load('src/commerce/customer-service.mjs');
const {createCart,addCartItem,quoteCart,checkoutCart,confirmPayment,updateOrderStatus,getOrder}=await load('src/commerce/order-service.mjs');
const {createPrint,createPositioningCode,transitionPrint,addPrintAsset,startProcessing,createMockup,removeMockupImage,listMockups}=await load('src/commerce/print-workflow-service.mjs');

const stamp=`E2E${Date.now()}`;
let productId=null,variantId=null,customerId=null,cartId=null,orderId=null,printId=null,mockupId=null,positionCode=null,sessionToken=null;
let completed=false;

async function cleanup(){
  try{
    if(orderId){
      await db.execute(`DELETE FROM supplier_orders WHERE order_id=?`,[orderId]).catch(()=>{});
      await db.execute(`DELETE FROM shipments WHERE order_id=?`,[orderId]).catch(()=>{});
      await db.execute(`DELETE FROM payment_transactions WHERE order_id=?`,[orderId]).catch(()=>{});
      await db.execute(`DELETE FROM order_status_history WHERE order_id=?`,[orderId]).catch(()=>{});
      await db.execute(`DELETE FROM order_addresses WHERE order_id=?`,[orderId]).catch(()=>{});
      await db.execute(`DELETE FROM order_items WHERE order_id=?`,[orderId]).catch(()=>{});
      await db.execute(`DELETE FROM orders WHERE id=?`,[orderId]).catch(()=>{});
      await db.execute(`DELETE FROM audit_logs WHERE entity_type='order' AND entity_id=?`,[String(orderId)]).catch(()=>{});
    }
    if(cartId){await db.execute(`DELETE FROM cart_items WHERE cart_id=?`,[cartId]).catch(()=>{});await db.execute(`DELETE FROM carts WHERE id=?`,[cartId]).catch(()=>{});}
    if(customerId){await db.execute(`DELETE FROM customer_sessions WHERE customer_id=?`,[customerId]).catch(()=>{});await db.execute(`DELETE FROM customer_addresses WHERE customer_id=?`,[customerId]).catch(()=>{});await db.execute(`DELETE FROM customers WHERE id=?`,[customerId]).catch(()=>{});await db.execute(`DELETE FROM audit_logs WHERE entity_type='customer' AND entity_id=?`,[String(customerId)]).catch(()=>{});}
    if(productId){await db.execute(`DELETE FROM supplier_offers WHERE product_variant_id IN (SELECT id FROM product_variants WHERE product_id=?)`,[productId]).catch(()=>{});await db.execute(`DELETE FROM product_mockup_rules WHERE product_id=?`,[productId]).catch(()=>{});await db.execute(`DELETE FROM product_shipping_rules WHERE product_id=?`,[productId]).catch(()=>{});await db.execute(`DELETE FROM tenant_product_listings WHERE product_id=?`,[productId]).catch(()=>{});await db.execute(`DELETE FROM product_variants WHERE product_id=?`,[productId]).catch(()=>{});await db.execute(`DELETE FROM products WHERE id=?`,[productId]).catch(()=>{});await db.execute(`DELETE FROM audit_logs WHERE entity_type='product' AND entity_id=?`,[String(productId)]).catch(()=>{});}
    if(positionCode)await db.execute(`DELETE FROM positioning_codes WHERE code=?`,[positionCode]).catch(()=>{});
    if(printId){await db.execute(`DELETE FROM print_assets WHERE print_id=?`,[printId]).catch(()=>{});await db.execute(`DELETE FROM print_workflow_events WHERE print_id=?`,[printId]).catch(()=>{});await db.execute(`DELETE FROM print_workflow WHERE print_id=?`,[printId]).catch(()=>{});await db.execute(`DELETE FROM prints WHERE id=?`,[printId]).catch(()=>{});await db.execute(`DELETE FROM audit_logs WHERE entity_type='print' AND entity_id=?`,[String(printId)]).catch(()=>{});}
    if(mockupId){await db.execute(`DELETE FROM product_mockup_rules WHERE template_id=?`,[mockupId]).catch(()=>{});await db.execute(`DELETE FROM positioning_codes WHERE template_id=?`,[mockupId]).catch(()=>{});await db.execute(`DELETE FROM mockup_templates WHERE id=?`,[mockupId]).catch(()=>{});}
    await db.execute(`DELETE FROM audit_logs WHERE metadata_json LIKE ?`,[`%${stamp}%`]).catch(()=>{});
  }catch(error){console.error('E2E_CLEANUP_WARNING='+error.message);}
}

try{
  const product=await createAdminProduct({name:`Produto ${stamp}`,sku:`${stamp}-SKU`,price:79.9,stockQuantity:5,status:'published',customizable:false,metadata:{e2e:stamp}});
  productId=Number(product.id);
  const variants=await listVariants(productId);variantId=Number(variants[0]?.id);if(!variantId)throw new Error('E2E variant missing');
  console.log(`E2E_PRODUCT=OK id=${productId} variant=${variantId}`);

  const email=`${stamp.toLowerCase()}@example.invalid`;const password='BelaStock-E2E-123!';
  const customer=await registerCustomer(1,{name:`Cliente ${stamp}`,email,password});customerId=Number(customer.id);
  const login=await loginCustomer(1,{email,password},{ip:'127.0.0.1',userAgent:'BelaStock-E2E'});sessionToken=login.token;if(!sessionToken)throw new Error('E2E login token missing');
  console.log(`E2E_CUSTOMER_AUTH=OK id=${customerId}`);

  const cart=await createCart(1,customerId);cartId=Number(cart.id);
  await addCartItem(1,cart.token,{productId,variantId,quantity:2});
  const quote=await quoteCart(1,cart.token,{shippingMethod:'pickup'});if(Number(quote.totals.grandTotal)!==159.8)throw new Error(`Unexpected E2E total ${quote.totals.grandTotal}`);
  console.log(`E2E_CART_QUOTE=OK total=${quote.totals.grandTotal}`);

  const checkout=await checkoutCart(1,customerId,cart.token,{shippingMethod:'pickup',paymentProvider:'manual_pix'});orderId=Number(checkout.orderId);if(!orderId||checkout.status!=='pending')throw new Error('E2E checkout failed');
  console.log(`E2E_CHECKOUT=OK order=${checkout.orderNumber}`);
  await confirmPayment(1,orderId,{note:`${stamp} payment`});
  await updateOrderStatus(1,orderId,'processing',{note:`${stamp} processing`});
  await updateOrderStatus(1,orderId,'fulfilled',{note:`${stamp} fulfilled`});
  const finalOrder=await getOrder(1,orderId,customerId);if(finalOrder?.status!=='fulfilled')throw new Error('E2E order did not reach fulfilled');
  const [stockRows]=await db.execute(`SELECT stock_quantity FROM product_variants WHERE id=?`,[variantId]);if(Number(stockRows[0]?.stock_quantity)!==3)throw new Error('E2E stock reservation mismatch');
  console.log('E2E_ORDER_PAYMENT_FULFILLMENT=OK');

  const print=await createPrint({name:`Estampa ${stamp}`,code:`${stamp}-POS`,originalPath:`/tmp/${stamp}-original.png`,metadata:{e2e:stamp}});printId=Number(print.id);positionCode=print.code;
  await createPositioningCode({code:positionCode,printId,zoneKey:'frente',locked:true,config:{e2e:stamp}});
  await transitionPrint(printId,'queue',{note:`${stamp} queue`});
  let blocked=false;try{await transitionPrint(printId,'processed',{note:'must block'});}catch{blocked=true;}if(!blocked)throw new Error('Print left queue without composition');
  await addPrintAsset(printId,{role:'composition',path:`/tmp/${stamp}-composition.png`,metadata:{e2e:stamp}});
  await startProcessing(printId);
  await transitionPrint(printId,'processed',{note:`${stamp} processed`});
  await transitionPrint(printId,'published',{note:`${stamp} published`});
  const [printRows]=await db.execute(`SELECT p.status,w.stage FROM prints p JOIN print_workflow w ON w.print_id=p.id WHERE p.id=?`,[printId]);if(printRows[0]?.status!=='published'||printRows[0]?.stage!=='published')throw new Error('E2E print workflow failed');
  console.log('E2E_PRINT_LIBRARY_QUEUE_PROCESSED_PUBLISHED=OK');

  const mockup=await createMockup({name:`Mockup ${stamp}`,productType:'camiseta',colorImages:['img-a','img-b'],zones:[{key:'frente'}]});mockupId=Number(mockup.id);
  await removeMockupImage(mockupId,'img-a');
  const mockups=await listMockups();const m=mockups.find(x=>Number(x.id)===mockupId);if(!m||JSON.stringify(m.colorImages)!==JSON.stringify(['img-b']))throw new Error('Mockup image deletion did not persist');
  console.log('E2E_MOCKUP_IMAGE_DELETE_PERSISTENCE=OK');

  await logoutCustomer(sessionToken);sessionToken=null;
  completed=true;
  console.log('BELA_STOCK_V30_E2E=100%_OK');
} finally {
  await cleanup();
  console.log(`E2E_SYNTHETIC_DATA_CLEANUP=${completed?'OK':'ATTEMPTED'}`);
  await db.end();
}
