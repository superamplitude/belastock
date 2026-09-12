const $=id=>document.getElementById(id);
const esc=value=>String(value??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const money=(value,currency='BRL')=>value==null?'—':new Intl.NumberFormat('pt-BR',{style:'currency',currency}).format(Number(value));
async function api(url,options={}){const headers={...(options.headers||{}),'content-type':'application/json'};const r=await fetch(url,{...options,headers,credentials:'same-origin'});const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(data.error||`HTTP ${r.status}`);return data}
const jsonValue=id=>{const text=$(id).value.trim();if(!text)return{};try{return JSON.parse(text)}catch{throw new Error(`JSON inválido em ${id}`)}};

window.partnerLogin=async()=>{try{await api('/api/partner/login',{method:'POST',body:JSON.stringify({email:$('p-email').value,password:$('p-password').value})});$('p-auth-message').textContent='';await loadPartnerPanel()}catch(e){$('p-auth-message').textContent=e.message}};
window.partnerLogout=async()=>{await api('/api/partner/logout',{method:'POST'}).catch(()=>{});$('partner-panel').style.display='none';$('partner-auth').style.display='block'};
window.createOwnProduct=async()=>{try{
  const allowed=$('prod-carriers').value.split(',').map(x=>x.trim()).filter(Boolean);
  await api('/api/partner/products',{method:'POST',body:JSON.stringify({name:$('prod-name').value,sku:$('prod-sku').value,price:Number($('prod-price').value||0),stockQuantity:$('prod-stock').value===''?null:Number($('prod-stock').value),shipping:{requiresShipping:true,requiresCarrier:$('prod-carrier').checked,weightKg:$('prod-weight').value===''?null:Number($('prod-weight').value),lengthCm:$('prod-length').value===''?null:Number($('prod-length').value),widthCm:$('prod-width').value===''?null:Number($('prod-width').value),heightCm:$('prod-height').value===''?null:Number($('prod-height').value),allowedCarriers:allowed}})});
  ['prod-name','prod-sku','prod-price','prod-stock','prod-weight','prod-length','prod-width','prod-height','prod-carriers'].forEach(id=>$(id).value='');$('prod-carrier').checked=false;await loadPartnerPanel();
}catch(e){alert(e.message)}};
window.savePaymentGateway=async()=>{try{await api('/api/partner/payment-gateways',{method:'POST',body:JSON.stringify({provider:$('pay-provider').value,displayName:$('pay-name').value,enabled:$('pay-enabled').checked,sandbox:$('pay-sandbox').checked,credentials:jsonValue('pay-credentials'),config:jsonValue('pay-config')})});$('pay-credentials').value='';await loadPartnerPanel()}catch(e){alert(e.message)}};
window.saveShippingCarrier=async()=>{try{await api('/api/partner/shipping-carriers',{method:'POST',body:JSON.stringify({provider:$('ship-provider').value,name:$('ship-name').value,enabled:$('ship-enabled').checked,credentials:jsonValue('ship-credentials'),config:jsonValue('ship-config')})});$('ship-credentials').value='';await loadPartnerPanel()}catch(e){alert(e.message)}};

async function loadProviderCatalogs(){try{
  const [p,s]=await Promise.all([api('/api/partner/payment-gateways'),api('/api/partner/shipping-carriers')]);
  $('pay-provider').innerHTML=p.providers.map(x=>`<option value="${esc(x.provider)}">${esc(x.label)}</option>`).join('');
  $('ship-provider').innerHTML=s.providers.map(x=>`<option value="${esc(x.provider)}">${esc(x.label)}</option>`).join('');
  renderPaymentList(p.items);renderShippingList(s.items);
}catch{}}
function renderPaymentList(items){$('payment-list').innerHTML=(items||[]).map(x=>`<div class="card" style="margin-bottom:8px"><strong>${esc(x.display_name)}</strong> · ${esc(x.provider)} · ${x.enabled?'ATIVO':'inativo'} · ${x.sandbox?'sandbox':'produção'}</div>`).join('')||'<div class="card">Nenhum gateway configurado.</div>'}
function renderShippingList(items){$('shipping-list').innerHTML=(items||[]).map(x=>`<div class="card" style="margin-bottom:8px"><strong>${esc(x.name)}</strong> · ${esc(x.provider)} · ${x.enabled?'ATIVA':'inativa'}</div>`).join('')||'<div class="card">Nenhuma transportadora configurada.</div>'}

async function loadPartnerPanel(){try{
  const p=await api('/api/partner/panel');
  $('partner-auth').style.display='none';$('partner-panel').style.display='block';$('partner-store-name').textContent=p.tenant.name||'LOJA';$('partner-welcome').textContent=`${p.user.name} · ${p.user.role}`;
  $('partner-kpis').innerHTML=[['Produtos',p.listings.length],['Gateways',p.payments.length],['Transportadoras',p.shipping.length],['Pedidos',p.orders.length]].map(([a,b])=>`<div class="card kpi"><span class="muted">${esc(a)}</span><strong>${b}</strong></div>`).join('');
  $('partner-domains').innerHTML=(p.tenant.domains||[]).map(d=>`<div><strong>${esc(d.domain)}</strong> · ${esc(d.status)} · SSL ${esc(d.ssl_status)} ${d.is_primary?'· principal':''}</div>`).join('')||'<p class="muted">Nenhum domínio cadastrado.</p>';
  $('partner-products').innerHTML=p.listings.length?p.listings.map(x=>`<tr><td>${esc(x.store_name||x.name)}</td><td>${esc(x.source_mode)}</td><td>${x.enabled?'ativo':'inativo'} / ${esc(x.status)}</td><td>${money(x.price_override??x.price,p.tenant.default_currency||'BRL')}</td></tr>`).join(''):'<tr><td colspan="4">Nenhum produto.</td></tr>';
  $('partner-orders').innerHTML=p.orders.length?p.orders.map(o=>`<tr><td>${esc(o.order_number)}</td><td>${esc(o.status)}</td><td>${money(o.grand_total,p.tenant.default_currency||'BRL')}</td><td>${esc(o.created_at||'')}</td></tr>`).join(''):'<tr><td colspan="4">Nenhum pedido.</td></tr>';
  await loadProviderCatalogs();
}catch(e){$('partner-panel').style.display='none';$('partner-auth').style.display='block'}}
loadPartnerPanel();
