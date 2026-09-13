import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { db } from '../db.mjs';

const __dirname=path.dirname(fileURLToPath(import.meta.url));
const publicDir=path.resolve(__dirname,'../../public');
const homeKeys=new Set([
  'topbar_1','topbar_2','topbar_3',
  'hero_subtitle','hero_title','hero_text','hero_cta_label','hero_cta_href','hero_autoplay_ms','hero_slides'
]);
const defaults={
  hero_cta_label:'Ver coleção',
  hero_cta_href:'#catalogo',
  hero_autoplay_ms:6500,
  hero_slides:[
    {src:'/assets/hero/hero-01.webp',alt:'Modelo Bela Stock com camiseta branca em fundo lilás',active:true,position:'72% center'},
    {src:'/assets/hero/hero-02.webp',alt:'Modelo Bela Stock com camiseta roxa no ambiente da loja',active:true,position:'73% center'},
    {src:'/assets/hero/hero-03.webp',alt:'Modelo Bela Stock com camiseta roxa em destaque',active:true,position:'74% center'},
    {src:'/assets/hero/hero-04.webp',alt:'Modelo Bela Stock com camiseta branca no ambiente da loja',active:true,position:'76% center'}
  ]
};
const parseJson=value=>{try{return typeof value==='string'?JSON.parse(value):value}catch{return null}};
async function readHome(){
  const [rows]=await db.query(`SELECT setting_key,setting_value_json FROM settings WHERE setting_key LIKE 'home.%' ORDER BY setting_key`);
  const found=Object.fromEntries(rows.map(r=>[r.setting_key.slice(5),parseJson(r.setting_value_json)]));
  return {...defaults,...found};
}
function cleanHref(value){
  const v=String(value||'').trim();
  if(!v)return '#catalogo';
  if(v.startsWith('#')||v.startsWith('/')||/^https:\/\/[^ ]+$/i.test(v))return v;
  throw new Error('hero_cta_href inválido');
}
function cleanSlides(value){
  if(!Array.isArray(value))throw new Error('hero_slides deve ser uma lista');
  return value.slice(0,8).map((item,i)=>{
    const src=String(item?.src||'').trim();
    if(!src)throw new Error(`slide ${i+1}: imagem obrigatória`);
    if(!(src.startsWith('/')||/^https:\/\/[^ ]+$/i.test(src)))throw new Error(`slide ${i+1}: caminho de imagem inválido`);
    return {
      src,
      alt:String(item?.alt||`Destaque Bela Stock ${i+1}`).trim().slice(0,180),
      active:item?.active!==false,
      position:(()=>{const p=String(item?.position||'center center').trim().slice(0,40);return /^(?:center|left|right|top|bottom|\d{1,3}%)(?:\s+(?:center|left|right|top|bottom|\d{1,3}%))?$/.test(p)?p:'center center';})()
    };
  });
}
function normalize(key,value){
  if(['topbar_1','topbar_2','topbar_3','hero_subtitle','hero_title','hero_text','hero_cta_label'].includes(key))return String(value??'').trim().slice(0,key==='hero_text'?600:220);
  if(key==='hero_cta_href')return cleanHref(value);
  if(key==='hero_autoplay_ms')return Math.max(3000,Math.min(Number(value||6500),20000));
  if(key==='hero_slides')return cleanSlides(value);
  return value;
}
export function registerHomeCustomizationRoutes(app,{requireAdmin,requireTenant}){
  app.get('/api/admin/home-settings',{preHandler:requireAdmin},async()=>readHome());
  app.post('/api/admin/home-assets',{preHandler:requireAdmin},async(request,reply)=>{
    try{
      const body=request.body||{};
      const match=String(body.dataUrl||'').match(/^data:(image\/(?:webp|png|jpeg));base64,([A-Za-z0-9+/=]+)$/);
      if(!match)throw new Error('Imagem inválida. Use WEBP, PNG ou JPG.');
      const bytes=Buffer.from(match[2],'base64');
      if(!bytes.length||bytes.length>5*1024*1024)throw new Error('A imagem deve ter no máximo 5 MB.');
      const mime=match[1];
      const valid=(mime==='image/png'&&bytes.length>8&&bytes.subarray(0,8).equals(Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])))||(mime==='image/jpeg'&&bytes.length>3&&bytes[0]===0xff&&bytes[1]===0xd8&&bytes[2]===0xff)||(mime==='image/webp'&&bytes.length>12&&bytes.subarray(0,4).toString('ascii')==='RIFF'&&bytes.subarray(8,12).toString('ascii')==='WEBP');
      if(!valid)throw new Error('Conteúdo da imagem não corresponde ao formato informado.');
      const ext=mime==='image/png'?'.png':mime==='image/jpeg'?'.jpg':'.webp';
      const filename=`hero-user-${Date.now()}-${crypto.randomBytes(4).toString('hex')}${ext}`;
      const dir=path.join(publicDir,'assets','hero');
      await fs.mkdir(dir,{recursive:true});
      await fs.writeFile(path.join(dir,filename),bytes,{flag:'wx'});
      return {src:`/assets/hero/${filename}`};
    }catch(error){return reply.code(400).send({error:error.message});}
  });
  app.put('/api/admin/home-settings',{preHandler:requireAdmin},async(request,reply)=>{
    try{
      const body=request.body||{};
      for(const [key,value] of Object.entries(body)){
        if(!homeKeys.has(key))continue;
        const normalized=normalize(key,value);
        await db.execute(`INSERT INTO settings (setting_key,setting_value_json) VALUES (?,?) ON DUPLICATE KEY UPDATE setting_value_json=VALUES(setting_value_json)`,[`home.${key}`,JSON.stringify(normalized)]);
      }
      return await readHome();
    }catch(error){return reply.code(400).send({error:error.message});}
  });

  app.get('/home-admin.js',async(_request,reply)=>reply.type('application/javascript; charset=utf-8').send(await fs.readFile(path.join(publicDir,'home-admin.js'),'utf8')));
  app.get('/assets/hero/:file',{preHandler:requireTenant},async(request,reply)=>{
    const file=String(request.params.file||'');
    if(!/^[a-zA-Z0-9._-]+\.(?:webp|png|jpe?g)$/i.test(file))return reply.code(404).send({error:'asset_not_found'});
    const ext=path.extname(file).toLowerCase();
    const mime=ext==='.webp'?'image/webp':ext==='.png'?'image/png':'image/jpeg';
    try{
      const data=await fs.readFile(path.join(publicDir,'assets','hero',file));
      return reply.header('cache-control','public, max-age=86400').type(mime).send(data);
    }catch{return reply.code(404).send({error:'asset_not_found'});}
  });
}
