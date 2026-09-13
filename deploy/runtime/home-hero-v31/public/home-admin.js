const home$=id=>document.getElementById(id);
const homeToken=()=>localStorage.getItem('bs_admin_token')||'';
const homeEsc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const HOME_DEFAULT_SLIDES=[
  {src:'/assets/hero/hero-01.webp',alt:'Modelo Bela Stock com camiseta branca em fundo lilás',active:true,position:'72% center'},
  {src:'/assets/hero/hero-02.webp',alt:'Modelo Bela Stock com camiseta roxa no ambiente da loja',active:true,position:'73% center'},
  {src:'/assets/hero/hero-03.webp',alt:'Modelo Bela Stock com camiseta roxa em destaque',active:true,position:'74% center'},
  {src:'/assets/hero/hero-04.webp',alt:'Modelo Bela Stock com camiseta branca no ambiente da loja',active:true,position:'76% center'}
];

async function homeApi(url,options={}){
  const headers={...(options.headers||{}),'content-type':'application/json',authorization:`Bearer ${homeToken()}`};
  const r=await fetch(url,{...options,headers});const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(data.error||`HTTP ${r.status}`);return data;
}
function homeSlidesFromDom(){
  return [...document.querySelectorAll('[data-home-slide]')].map(card=>({
    src:card.querySelector('[data-field="src"]').value.trim(),
    alt:card.querySelector('[data-field="alt"]').value.trim(),
    position:card.querySelector('[data-field="position"]').value.trim()||'center center',
    active:card.querySelector('[data-field="active"]').checked
  })).filter(x=>x.src);
}
function homeRenderSlides(slides){
  const items=(Array.isArray(slides)&&slides.length?slides:HOME_DEFAULT_SLIDES).slice(0,8);
  home$('home-slide-editor').innerHTML=items.map((s,i)=>`<div class="hero-admin-card" data-home-slide="${i}">
    <div class="hero-admin-preview"><img src="${homeEsc(s.src)}" alt="${homeEsc(s.alt||'')}"></div>
    <strong>Slide ${i+1}</strong>
    <label>Imagem / caminho<input data-field="src" value="${homeEsc(s.src)}"></label>
    <label>Enviar nova imagem<input data-field="upload" type="file" accept="image/webp,image/png,image/jpeg"></label>
    <label>Descrição acessível<input data-field="alt" value="${homeEsc(s.alt||'')}"></label>
    <label>Enquadramento<input data-field="position" value="${homeEsc(s.position||'center center')}" placeholder="72% center"></label>
    <div class="toolbar"><label class="inline-check"><input data-field="active" type="checkbox" ${s.active!==false?'checked':''}> Ativo</label><button type="button" class="ghost" data-action="remove-slide">Remover slide</button></div>
  </div>`).join('');
  document.querySelectorAll('[data-home-slide] [data-field="src"]').forEach(input=>input.addEventListener('change',e=>{
    const card=e.target.closest('[data-home-slide]');const img=card.querySelector('img');img.src=e.target.value.trim();
  }));
  document.querySelectorAll('[data-home-slide] [data-action="remove-slide"]').forEach(btn=>btn.addEventListener('click',e=>{
    e.target.closest('[data-home-slide]').remove();homeRenumberSlides();
  }));
  document.querySelectorAll('[data-home-slide] [data-field="upload"]').forEach(input=>input.addEventListener('change',async e=>{
    const file=e.target.files?.[0];if(!file)return;
    const state=home$('home-save-state');
    try{
      state.textContent=`Enviando ${file.name}...`;
      if(file.size>5*1024*1024)throw new Error('A imagem deve ter no máximo 5 MB.');
      const dataUrl=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=()=>reject(new Error('Falha ao ler a imagem.'));r.readAsDataURL(file)});
      const uploaded=await homeApi('/api/admin/home-assets',{method:'POST',body:JSON.stringify({filename:file.name,dataUrl})});
      const card=e.target.closest('[data-home-slide]');card.querySelector('[data-field="src"]').value=uploaded.src;card.querySelector('img').src=uploaded.src;
      state.textContent='Imagem enviada. Clique em Salvar e publicar para ativá-la.';
    }catch(error){state.textContent=error.message;e.target.value='';}
  }));
}
function homeRenumberSlides(){
  [...document.querySelectorAll('[data-home-slide]')].forEach((card,i)=>{card.dataset.homeSlide=String(i);const title=card.querySelector('strong');if(title)title.textContent=`Slide ${i+1}`;});
}
window.homeAddSlide=()=>{
  const current=homeSlidesFromDom();
  if(current.length>=8){home$('home-save-state').textContent='Limite de 8 slides.';return;}
  current.push({src:'/assets/hero/hero-01.webp',alt:`Destaque Bela Stock ${current.length+1}`,active:true,position:'center center'});
  homeRenderSlides(current);
};
window.homeLoad=async()=>{
  if(!home$('home-hero'))return;
  const state=home$('home-save-state');
  try{
    state.textContent='Carregando...';
    const h=await homeApi('/api/admin/home-settings');
    home$('home-hero-subtitle').value=h.hero_subtitle||'';
    home$('home-hero-title').value=h.hero_title||'';
    home$('home-hero-text').value=h.hero_text||'';
    home$('home-hero-cta-label').value=h.hero_cta_label||'Ver coleção';
    home$('home-hero-cta-href').value=h.hero_cta_href||'#catalogo';
    home$('home-hero-autoplay').value=Number(h.hero_autoplay_ms||6500);
    home$('home-topbar-1').value=h.topbar_1||'';
    home$('home-topbar-2').value=h.topbar_2||'';
    home$('home-topbar-3').value=h.topbar_3||'';
    homeRenderSlides(h.hero_slides);
    state.textContent='Configurações carregadas.';
  }catch(e){state.textContent=e.message;}
};
window.homeSave=async()=>{
  const state=home$('home-save-state');
  try{
    state.textContent='Salvando...';
    const payload={
      hero_subtitle:home$('home-hero-subtitle').value.trim(),
      hero_title:home$('home-hero-title').value.trim(),
      hero_text:home$('home-hero-text').value.trim(),
      hero_cta_label:home$('home-hero-cta-label').value.trim(),
      hero_cta_href:home$('home-hero-cta-href').value.trim()||'#catalogo',
      hero_autoplay_ms:Number(home$('home-hero-autoplay').value||6500),
      topbar_1:home$('home-topbar-1').value.trim(),
      topbar_2:home$('home-topbar-2').value.trim(),
      topbar_3:home$('home-topbar-3').value.trim(),
      hero_slides:homeSlidesFromDom()
    };
    const saved=await homeApi('/api/admin/home-settings',{method:'PUT',body:JSON.stringify(payload)});
    homeRenderSlides(saved.hero_slides);
    state.textContent='Publicado. A capa pública já usa estas configurações.';
  }catch(e){state.textContent=e.message;}
};

if(typeof window.saveToken==='function'){
  const baseSaveToken=window.saveToken;
  window.saveToken=async()=>{await baseSaveToken();await homeLoad();};
}
document.addEventListener('DOMContentLoaded',()=>{if(homeToken())homeLoad();else homeRenderSlides(HOME_DEFAULT_SLIDES);});
