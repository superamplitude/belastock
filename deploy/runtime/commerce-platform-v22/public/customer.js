const $=id=>document.getElementById(id);
const esc=value=>String(value??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const money=(value,currency='BRL')=>value==null?'—':new Intl.NumberFormat('pt-BR',{style:'currency',currency}).format(Number(value));
async function api(url,options={}){const headers={...(options.headers||{}),'content-type':'application/json'};const r=await fetch(url,{...options,headers,credentials:'same-origin'});const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(data.error||`HTTP ${r.status}`);return data}

async function loadStore(){try{const s=await api('/api/public/store');$('store-name').textContent=s.name||'BELA STOCK';document.title=`Minha Conta · ${s.name||'Bela Stock'}`}catch{}}
window.customerLogin=async()=>{try{await api('/api/customer/login',{method:'POST',body:JSON.stringify({email:$('login-email').value,password:$('login-password').value})});$('auth-message').textContent='';await loadPanel()}catch(e){$('auth-message').textContent=e.message}};
window.customerRegister=async()=>{try{await api('/api/customer/register',{method:'POST',body:JSON.stringify({name:$('reg-name').value,email:$('reg-email').value,phone:$('reg-phone').value,password:$('reg-password').value})});$('login-email').value=$('reg-email').value;$('login-password').value=$('reg-password').value;await customerLogin()}catch(e){$('auth-message').textContent=e.message}};
window.customerLogout=async()=>{await api('/api/customer/logout',{method:'POST'}).catch(()=>{});$('panel-box').style.display='none';$('auth-box').style.display='block'};
window.saveAddress=async()=>{try{await api('/api/customer/addresses',{method:'POST',body:JSON.stringify({label:$('addr-label').value,postalCode:$('addr-zip').value,street:$('addr-street').value,number:$('addr-number').value,district:$('addr-district').value,city:$('addr-city').value,state:$('addr-state').value,country:'BR'})});await loadPanel()}catch(e){alert(e.message)}};

async function loadPanel(){try{
  const p=await api('/api/customer/panel');
  $('auth-box').style.display='none';$('panel-box').style.display='block';$('customer-welcome').textContent=`${p.customer.name} · ${p.customer.email}`;
  $('customer-kpis').innerHTML=[['Pedidos',p.orders.length],['Entregas',p.shipments.length],['Pagamentos',p.payments.length],['Endereços',p.addresses.length]].map(([a,b])=>`<div class="card kpi"><span class="muted">${esc(a)}</span><strong>${b}</strong></div>`).join('');
  $('orders-list').innerHTML=p.orders.length?p.orders.map(o=>`<tr><td>${esc(o.order_number)}</td><td>${esc(o.status)}</td><td>${money(o.grand_total,o.currency)}</td><td>${esc(o.created_at||'')}</td></tr>`).join(''):'<tr><td colspan="4">Nenhum pedido ainda.</td></tr>';
  $('shipments-list').innerHTML=p.shipments.length?p.shipments.map(s=>`<tr><td>#${s.order_id}</td><td>${esc(s.carrier_name||'—')}</td><td>${esc(s.status)}</td><td>${esc(s.tracking_code||'—')}</td><td>${s.estimate_days==null?'—':`${s.estimate_days} dias`}</td></tr>`).join(''):'<tr><td colspan="5">Nenhuma entrega ainda.</td></tr>';
  $('payments-list').innerHTML=p.payments.length?p.payments.map(x=>`<tr><td>#${x.order_id}</td><td>${esc(x.gateway_name||'—')}</td><td>${esc(x.method||'—')}</td><td>${esc(x.status)}</td><td>${money(x.amount,x.currency)}</td></tr>`).join(''):'<tr><td colspan="5">Nenhum pagamento ainda.</td></tr>';
  $('addresses-list').innerHTML=p.addresses.length?p.addresses.map(a=>`<div class="card" style="margin-bottom:8px"><strong>${esc(a.label||'Endereço')}</strong><br>${esc(a.street)}, ${esc(a.number||'s/n')} · ${esc(a.district||'')} · ${esc(a.city)}/${esc(a.state)} · ${esc(a.postal_code)}</div>`).join(''):'<p class="muted">Nenhum endereço cadastrado.</p>';
}catch(e){$('panel-box').style.display='none';$('auth-box').style.display='block'}}
loadStore();loadPanel();
