import { db } from '../db.mjs';
import { audit } from '../audit.mjs';
import { canTransitionPrint,parseJson,sanitizeCode } from './core-math.mjs';

const stageToStatus=stage=>({library:'queue',queue:'queue',processed:'approved',published:'published',archived:'archived'}[stage]||'queue');

export async function listPrints(query={}){
  const stage=String(query.stage||'').trim();const params=[];let where='';
  if(stage){where='WHERE COALESCE(w.stage,\'library\')=?';params.push(stage);}
  const [rows]=await db.execute(`SELECT p.id,p.code,p.name,p.status,p.original_path,p.production_notes,p.metadata_json,p.created_at,p.updated_at,
    COALESCE(w.stage,'library') workflow_stage,w.processing_locked,
    (SELECT COUNT(*) FROM print_assets a WHERE a.print_id=p.id AND a.active=1) asset_count,
    (SELECT COUNT(*) FROM positioning_codes pc WHERE pc.print_id=p.id AND pc.locked=1) locked_position_count
    FROM prints p LEFT JOIN print_workflow w ON w.print_id=p.id ${where} ORDER BY p.id DESC LIMIT 500`,params);
  return rows.map(r=>({...r,metadata:parseJson(r.metadata_json,{})}));
}

export async function createPrint(input={}){
  const name=String(input.name||'').trim();if(!name)throw new Error('Print name is required');
  const code=sanitizeCode(input.code||`PRINT-${Date.now()}`);
  const conn=await db.getConnection();
  try{
    await conn.beginTransaction();
    const [r]=await conn.execute(`INSERT INTO prints (code,name,status,original_path,production_notes,metadata_json) VALUES (?,?,'queue',?,?,?)`,[code,name,input.originalPath||null,input.productionNotes||null,JSON.stringify(input.metadata||{})]);
    await conn.execute(`INSERT INTO print_workflow (print_id,stage,processing_locked,last_actor) VALUES (?,'library',0,'admin')`,[r.insertId]);
    await conn.execute(`INSERT INTO print_workflow_events (print_id,from_stage,to_stage,actor_type,actor_id,note) VALUES (?,NULL,'library','admin','admin','Criada na Biblioteca')`,[r.insertId]);
    if(input.originalPath) await conn.execute(`INSERT INTO print_assets (print_id,role,path,checksum_sha256,metadata_json) VALUES (?,'original',?,?,?)`,[r.insertId,input.originalPath,input.checksumSha256||null,JSON.stringify(input.assetMetadata||{})]);
    await conn.commit();
    await audit({actorType:'admin',action:'print.create',entityType:'print',entityId:r.insertId,after:{code,name,stage:'library'}});
    return {id:r.insertId,code,stage:'library'};
  }catch(error){await conn.rollback();throw error;}finally{conn.release();}
}

async function ensureWorkflow(printId){
  const [p]=await db.execute(`SELECT id,status FROM prints WHERE id=? LIMIT 1`,[printId]);if(!p[0])throw new Error('Print not found');
  await db.execute(`INSERT INTO print_workflow (print_id,stage,last_actor) VALUES (?,'library','migration') ON DUPLICATE KEY UPDATE print_id=VALUES(print_id)`,[printId]);
  const [w]=await db.execute(`SELECT * FROM print_workflow WHERE print_id=? LIMIT 1`,[printId]);return {print:p[0],workflow:w[0]};
}

async function assertReadyToLeaveQueue(printId){
  const [[assets],[locks]] = await Promise.all([
    db.execute(`SELECT COUNT(*) c FROM print_assets WHERE print_id=? AND active=1 AND role IN ('composition','mockup')`,[printId]),
    db.execute(`SELECT COUNT(*) c FROM positioning_codes WHERE print_id=? AND locked=1`,[printId])
  ]);
  if(Number(assets[0].c)<1)throw new Error('A composição/mockup é obrigatória antes de sair da fila');
  if(Number(locks[0].c)<1)throw new Error('Ao menos um código de posicionamento deve estar travado antes de sair da fila');
}

export async function transitionPrint(printId,toStage,input={}){
  const allowed=['library','queue','processed','published','archived'];if(!allowed.includes(toStage))throw new Error('Invalid print stage');
  const {workflow}=await ensureWorkflow(printId);const from=workflow.stage;
  if(!canTransitionPrint(from,toStage))throw new Error(`Invalid print transition: ${from} -> ${toStage}`);
  if(from==='queue'&&toStage==='processed')await assertReadyToLeaveQueue(printId);
  if(toStage==='published')await assertReadyToLeaveQueue(printId);
  const conn=await db.getConnection();
  try{
    await conn.beginTransaction();
    await conn.execute(`UPDATE print_workflow SET stage=?,processing_locked=?,last_actor='admin' WHERE print_id=?`,[toStage,toStage==='processed'||toStage==='published'?1:0,printId]);
    await conn.execute(`UPDATE prints SET status=? WHERE id=?`,[stageToStatus(toStage),printId]);
    await conn.execute(`INSERT INTO print_workflow_events (print_id,from_stage,to_stage,actor_type,actor_id,note,metadata_json) VALUES (?,?,?,'admin','admin',?,?)`,[printId,from,toStage,input.note||null,JSON.stringify(input.metadata||{})]);
    await conn.commit();
    await audit({actorType:'admin',action:'print.transition',entityType:'print',entityId:printId,before:{stage:from},after:{stage:toStage}});
    return {id:printId,from,to:toStage,status:stageToStatus(toStage)};
  }catch(error){await conn.rollback();throw error;}finally{conn.release();}
}

export async function startProcessing(printId){
  const {workflow}=await ensureWorkflow(printId);if(workflow.stage!=='queue')throw new Error('Only queued prints can enter processing');
  await db.execute(`UPDATE prints SET status='processing' WHERE id=?`,[printId]);
  await db.execute(`INSERT INTO print_workflow_events (print_id,from_stage,to_stage,actor_type,actor_id,note) VALUES (?,? ,?,'admin','admin','Processamento iniciado')`,[printId,'queue','queue']);
  return {ok:true};
}

export async function listPrintAssets(printId){const [rows]=await db.execute(`SELECT * FROM print_assets WHERE print_id=? ORDER BY id`,[printId]);return rows.map(r=>({...r,metadata:parseJson(r.metadata_json,{})}));}
export async function addPrintAsset(printId,input={}){
  await ensureWorkflow(printId);const role=String(input.role||'');if(!['original','composition','mockup','export'].includes(role))throw new Error('Invalid asset role');
  const assetPath=String(input.path||'').trim();if(!assetPath)throw new Error('Asset path is required');
  if(role==='original'){const [existing]=await db.execute(`SELECT id FROM print_assets WHERE print_id=? AND role='original' AND active=1 LIMIT 1`,[printId]);if(existing[0])throw new Error('Original asset is immutable and already exists');}
  const [r]=await db.execute(`INSERT INTO print_assets (print_id,role,path,checksum_sha256,metadata_json,active) VALUES (?,?,?,?,?,1)`,[printId,role,assetPath,input.checksumSha256||null,JSON.stringify(input.metadata||{})]);
  if(role==='original')await db.execute(`UPDATE prints SET original_path=? WHERE id=?`,[assetPath,printId]);
  return {id:r.insertId};
}
export async function deactivatePrintAsset(printId,assetId){const [rows]=await db.execute(`SELECT id,role FROM print_assets WHERE id=? AND print_id=? LIMIT 1`,[assetId,printId]);if(!rows[0])throw new Error('Asset not found');if(rows[0].role==='original')throw new Error('Original asset cannot be removed');await db.execute(`UPDATE print_assets SET active=0 WHERE id=?`,[assetId]);return{ok:true};}

export async function createPositioningCode(input={}){
  const code=sanitizeCode(input.code);if(!input.printId&&!input.productId&&!input.templateId)throw new Error('Positioning code needs a print, product or template reference');
  const [exists]=await db.execute(`SELECT code FROM positioning_codes WHERE code=? LIMIT 1`,[code]);if(exists[0])throw new Error('Positioning code already exists and is immutable');
  await db.execute(`INSERT INTO positioning_codes (code,print_id,product_id,template_id,zone_key,config_json,locked) VALUES (?,?,?,?,?,?,?)`,[code,input.printId??null,input.productId??null,input.templateId??null,input.zoneKey||null,JSON.stringify(input.config||{}),input.locked?1:0]);
  return {code,locked:Boolean(input.locked)};
}
export async function listPositioningCodes(query={}){const params=[];const where=[];if(query.printId){where.push('print_id=?');params.push(Number(query.printId));}if(query.productId){where.push('product_id=?');params.push(Number(query.productId));}const [rows]=await db.execute(`SELECT * FROM positioning_codes ${where.length?'WHERE '+where.join(' AND '):''} ORDER BY created_at DESC LIMIT 500`,params);return rows.map(r=>({...r,config:parseJson(r.config_json,{})}));}
export async function lockPositioningCode(code,locked=true){const safe=sanitizeCode(code);const [r]=await db.execute(`UPDATE positioning_codes SET locked=? WHERE code=?`,[locked?1:0,safe]);if(!r.affectedRows)throw new Error('Positioning code not found');return{code:safe,locked:Boolean(locked)};}

export async function listMockups(){const [rows]=await db.query(`SELECT * FROM mockup_templates ORDER BY id DESC`);return rows.map(r=>({...r,colorImages:parseJson(r.color_images_json,[]),zones:parseJson(r.zones_json,[])}));}
export async function createMockup(input={}){const name=String(input.name||'').trim();const productType=String(input.productType||'').trim();if(!name||!productType)throw new Error('name and productType are required');const [r]=await db.execute(`INSERT INTO mockup_templates (name,product_type,color_images_json,zones_json,locked) VALUES (?,?,?,?,?)`,[name,productType,JSON.stringify(input.colorImages||[]),JSON.stringify(input.zones||[]),input.locked?1:0]);return{id:r.insertId};}
export async function updateMockup(id,input={}){const [rows]=await db.execute(`SELECT * FROM mockup_templates WHERE id=? LIMIT 1`,[id]);const m=rows[0];if(!m)throw new Error('Mockup not found');await db.execute(`UPDATE mockup_templates SET name=?,product_type=?,color_images_json=?,zones_json=?,locked=? WHERE id=?`,[input.name??m.name,input.productType??m.product_type,JSON.stringify(input.colorImages??parseJson(m.color_images_json,[])),JSON.stringify(input.zones??parseJson(m.zones_json,[])),input.locked===undefined?m.locked:(input.locked?1:0),id]);return{ok:true};}
export async function removeMockupImage(id,imageKey){const [rows]=await db.execute(`SELECT color_images_json FROM mockup_templates WHERE id=? LIMIT 1`,[id]);if(!rows[0])throw new Error('Mockup not found');const current=parseJson(rows[0].color_images_json,[]);let next=current;
  if(Array.isArray(current)) next=current.filter(item=>{if(typeof item==='string')return item!==imageKey;return ![item?.id,item?.key,item?.name,item?.url,item?.path].map(v=>String(v??'')).includes(String(imageKey));});
  else if(current&&typeof current==='object'){next={...current};delete next[imageKey];for(const [k,v] of Object.entries(next)){if(String(v)===String(imageKey)||String(v?.url??'')===String(imageKey)||String(v?.id??'')===String(imageKey))delete next[k];}}
  await db.execute(`UPDATE mockup_templates SET color_images_json=? WHERE id=?`,[JSON.stringify(next),id]);return{ok:true,images:next};}

export async function getProductMockupRules(productId){const [rows]=await db.execute(`SELECT r.*,m.name template_name,m.product_type FROM product_mockup_rules r JOIN mockup_templates m ON m.id=r.template_id WHERE r.product_id=? ORDER BY r.template_id`,[productId]);return rows.map(r=>({...r,allowedPositions:parseJson(r.allowed_positions_json,[]),positionPrices:parseJson(r.position_prices_json,{})}));}
export async function saveProductMockupRule(productId,input={}){if(!input.templateId)throw new Error('templateId is required');await db.execute(`INSERT INTO product_mockup_rules (product_id,template_id,allowed_positions_json,position_prices_json) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE allowed_positions_json=VALUES(allowed_positions_json),position_prices_json=VALUES(position_prices_json)`,[productId,Number(input.templateId),JSON.stringify(input.allowedPositions||[]),JSON.stringify(input.positionPrices||{})]);return getProductMockupRules(productId);}
