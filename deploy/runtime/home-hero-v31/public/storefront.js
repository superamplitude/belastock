const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'}).format(Number(v||0));
let cartToken=localStorage.getItem('bs_cart_token')||'';
let currentCart=null;
let loggedCustomer=null;
let heroIndex=0;
let heroTimer=null;
let heroSlides=[];
let topbarTimer=null;

const defaultHeroSlides=[
  {src:'/assets/hero/hero-01.webp',alt:'Modelo Bela Stock com camiseta branca em fundo lilás',active:true,position:'72% center'},
  {src:'/assets/hero/hero-02.webp',alt:'Modelo Bela Stock com camiseta roxa no ambiente da loja',active:true,position:'73% center'},
  {src:'/assets/hero/hero-03.webp',alt:'Modelo Bela Stock com camiseta roxa em destaque',active:true,position:'74% center'},
  {src:'/assets/hero/hero-04.webp',alt:'Modelo Bela Stock com camiseta branca no ambiente da loja',active:true,position:'76% center'}
];

async function api(url,options={}){
  const headers={...(options.headers||{})};if(options.body&&!headers['content-type'])headers['content-type']='application/json';if(cartToken)headers['x-cart-token']=cartToken;
  const r=await fetch(url,{...options,headers,credentials:'same-origin'});const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(data.error||`HTTP ${r.status}`);return data;
}
async function ensureCart(){if(cartToken){try{currentCart=await api('/api/cart');return currentCart}catch{localStorage.removeItem('bs_cart_token');cartToken='';}}const c=await api('/api/cart',{method:'POST'});cartToken=c.token;localStorage.setItem('bs_cart_token',cartToken);currentCart=await api('/api/cart');return currentCart;}

function openCart(){ $('cart-drawer').classList.add('open');$('cart-drawer').setAttribute('aria-hidden','false');$('drawer-backdrop').hidden=false; }
function closeCart(){ $('cart-drawer').classList.remove('open');$('cart-drawer').setAttribute('aria-hidden','true');$('drawer-backdrop').hidden=true; }

function normalizeSlides(value){
  const source=Array.isArray(value)?value:defaultHeroSlides;
  const slides=source.filter(x=>x&&x.active!==false&&typeof x.src==='string'&&x.src.trim()).slice(0,8).map((x,i)=>({
    src:x.src.trim(),
    alt:String(x.alt||`Destaque Bela Stock ${i+1}`),
    position:String(x.position||'center center')
  }));
  return slides.length?slides:defaultHeroSlides;
}
function showHero(index){
  const nodes=[...document.querySelectorAll('.hero-slide')];
  const dots=[...document.querySelectorAll('.hero-dot')];
  if(!nodes.length)return;
  heroIndex=(index+nodes.length)%nodes.length;
  nodes.forEach((node,i)=>{const active=i===heroIndex;node.classList.toggle('is-active',active);node.setAttribute('aria-hidden',active?'false':'true');});
  dots.forEach((dot,i)=>{const active=i===heroIndex;dot.classList.toggle('is-active',active);dot.setAttribute('aria-current',active?'true':'false');});
}
function startHero(ms){
  if(heroTimer)clearInterval(heroTimer);
  if(heroSlides.length<2)return;
  const delay=Math.max(3000,Math.min(Number(ms||6500),20000));
  heroTimer=setInterval(()=>showHero(heroIndex+1),delay);
}
function renderHero(home={}){
  if(home.hero_subtitle)$('hero-subtitle').textContent=home.hero_subtitle;
  if(home.hero_title)$('hero-title').textContent=home.hero_title;
  if(home.hero_text)$('hero-text').textContent=home.hero_text;
  if(home.hero_cta_label)$('hero-cta').textContent=home.hero_cta_label;
  if(home.hero_cta_href)$('hero-cta').setAttribute('href',home.hero_cta_href);
  heroSlides=normalizeSlides(home.hero_slides);
  $('hero-track').innerHTML=heroSlides.map((s,i)=>`<article class="hero-slide ${i===0?'is-active':''}" aria-hidden="${i===0?'false':'true'}"><img src="${esc(s.src)}" alt="${esc(s.alt)}" style="object-position:${esc(s.position)}" loading="${i===0?'eager':'lazy'}" decoding="async"></article>`).join('');
  $('hero-dots').innerHTML=heroSlides.length>1?heroSlides.map((_,i)=>`<button class="hero-dot ${i===0?'is-active':''}" type="button" aria-label="Ir para banner ${i+1}" aria-current="${i===0?'true':'false'}" data-index="${i}"></button>`).join(''):'';
  $('hero-prev').hidden=heroSlides.length<2;$('hero-next').hidden=heroSlides.length<2;
  document.querySelectorAll('.hero-dot').forEach(dot=>dot.addEventListener('click',()=>{showHero(Number(dot.dataset.index));startHero(home.hero_autoplay_ms);}));
  heroIndex=0;showHero(0);startHero(home.hero_autoplay_ms);
}
function renderTopbar(home={}){
  const items=[home.topbar_1,home.topbar_2,home.topbar_3].filter(v=>typeof v==='string'&&v.trim());
  if(!items.length)return;
  let i=0;$('topbar').textContent=items[0];
  if(topbarTimer)clearInterval(topbarTimer);
  if(items.length>1)topbarTimer=setInterval(()=>{$('topbar').textContent=items[++i%items.length]},5000);
}
function applyHome(home={}){renderTopbar(home);renderHero(home);}

async function loadStore(){
  const store=await api('/api/public/store');
  $('payment-provider').innerHTML=(store.paymentGateways?.length?store.paymentGateways:[{provider:'manual_pix',displayName:'PIX'}]).map(p=>`<option value="${esc(p.provider)}">${esc(p.displayName||p.provider)}</option>`).join('');
  $('shipping-method').innerHTML=(store.shippingCarriers?.length?store.shippingCarriers:[{id:'pickup',provider:'pickup',name:'Retirada no local'}]).map(s=>`<option value="${esc(s.id||s.provider)}">${esc(s.name||s.provider)}</option>`).join('');
}

async function loadProducts(){
  try{
    const [home,p]=await Promise.all([api('/api/public/home'),api('/api/public/products?limit=100')]);
    applyHome(home);
    $('products').innerHTML=p.items.length?p.items.map(x=>`<article class="product-card"><div class="product-media">${x.source_mode==='supplier'?'FORNECEDOR':'BELA STOCK'}</div><div class="product-body"><div class="eyebrow">${esc(x.sku)}</div><h3>${esc(x.name)}</h3><p class="muted">${esc(x.short_description||'Produto Bela Stock')}</p><div class="product-bottom"><strong>${money(x.price)}</strong><button class="btn" onclick="addProduct(${x.id},'${esc(x.slug).replace(/'/g,'&#39;')}')">Adicionar</button></div></div></article>`).join(''):'<div class="card">O catálogo está operacional e aguarda produtos publicados no Super Admin.</div>';
  }catch(e){$('products').innerHTML=`<div class="card error">${esc(e.message)}</div>`;}
}

window.addProduct=async(id,slug)=>{try{const detail=await api(`/api/public/products/${encodeURIComponent(slug||id)}`);const variant=detail.variants?.[0]||null;await api('/api/cart/items',{method:'POST',body:JSON.stringify({productId:id,variantId:variant?.id||null,quantity:1})});await refreshCart();openCart();}catch(e){alert(e.message)}};
window.removeCartItem=async id=>{try{await api(`/api/cart/items/${id}`,{method:'DELETE'});await refreshCart();}catch(e){alert(e.message)}};
window.changeQty=async(id,value)=>{try{await api(`/api/cart/items/${id}`,{method:'PUT',body:JSON.stringify({quantity:Number(value)})});await refreshCart();}catch(e){alert(e.message);await refreshCart();}};

async function refreshCart(){
  try{currentCart=await api('/api/cart');const count=currentCart.items.reduce((n,x)=>n+Number(x.quantity||0),0);$('cart-count').textContent=count;$('cart-items').innerHTML=currentCart.items.length?currentCart.items.map(x=>`<div class="cart-line"><div><strong>${esc(x.product_name)}</strong><div class="muted">${esc(x.variant_sku||x.product_sku||'')}</div></div><div class="row"><input class="qty" type="number" min="1" max="99" value="${x.quantity}" onchange="changeQty(${x.id},this.value)"><strong>${money(Number(x.unit_price)*Number(x.quantity))}</strong><button class="icon-btn" onclick="removeCartItem(${x.id})">×</button></div></div>`).join(''):'<p class="muted">Seu carrinho está vazio.</p>';$('cart-totals').innerHTML=`<span>Subtotal</span><strong>${money(currentCart.totals.subtotal)}</strong>`;
  }catch(e){$('cart-items').innerHTML=`<p class="error">${esc(e.message)}</p>`;}
}

async function quote(){try{const q=await api('/api/checkout/quote',{method:'POST',body:JSON.stringify({shippingMethod:$('shipping-method').value})});$('cart-totals').innerHTML=`<span>Subtotal</span><strong>${money(q.totals.subtotal)}</strong><span>Frete</span><strong>${money(q.totals.shippingTotal)}</strong><span>Total</span><strong>${money(q.totals.grandTotal)}</strong>`;return q;}catch(e){alert(e.message);throw e;}}

async function login(email,password){const r=await api('/api/customer/login',{method:'POST',body:JSON.stringify({email,password})});loggedCustomer=r.customer;$('auth-info').textContent=`Conectado como ${r.customer.name}`;return r.customer;}
async function register(){const payload={name:$('reg-name').value,email:$('reg-email').value,phone:$('reg-phone').value,password:$('reg-password').value};await api('/api/customer/register',{method:'POST',body:JSON.stringify(payload)});return login(payload.email,payload.password);}

async function checkout(){try{if(!currentCart?.items?.length)throw new Error('Carrinho vazio');if(!loggedCustomer)throw new Error('Entre ou crie uma conta para finalizar.');const shippingMethod=$('shipping-method').value;const payload={shippingMethod,paymentProvider:$('payment-provider').value};if(shippingMethod!=='pickup'){payload.address={postalCode:$('addr-postal').value,street:$('addr-street').value,number:$('addr-number').value,complement:$('addr-complement').value,district:$('addr-district').value,city:$('addr-city').value,state:$('addr-state').value,country:'BR'};}
    const result=await api('/api/checkout',{method:'POST',body:JSON.stringify(payload)});$('checkout-result').innerHTML=`<strong>Pedido ${esc(result.orderNumber)}</strong><br>Status: ${esc(result.status)}<br>Total: ${money(result.totals.grandTotal)}<br>${esc(result.payment.instructions||'')}${result.payment.pixKey?`<br>PIX: <strong>${esc(result.payment.pixKey)}</strong>`:''}`;
    localStorage.removeItem('bs_cart_token');cartToken='';await ensureCart();await refreshCart();
  }catch(e){$('checkout-result').textContent=e.message;}}

$('hero-prev').onclick=()=>{showHero(heroIndex-1);startHero()};
$('hero-next').onclick=()=>{showHero(heroIndex+1);startHero()};
$('hero-slider').addEventListener('mouseenter',()=>{if(heroTimer)clearInterval(heroTimer)});
$('hero-slider').addEventListener('mouseleave',()=>startHero());
$('cart-open').onclick=openCart;$('cart-close').onclick=closeCart;$('drawer-backdrop').onclick=closeCart;$('reload-products').onclick=loadProducts;$('quote-cart').onclick=quote;$('checkout-btn').onclick=checkout;
$('tab-login').onclick=()=>{$('login-box').hidden=false;$('register-box').hidden=true;$('tab-login').classList.add('active');$('tab-register').classList.remove('active')};
$('tab-register').onclick=()=>{$('login-box').hidden=true;$('register-box').hidden=false;$('tab-register').classList.add('active');$('tab-login').classList.remove('active')};
$('login-btn').onclick=async()=>{try{await login($('login-email').value,$('login-password').value)}catch(e){$('auth-info').textContent=e.message}};
$('register-btn').onclick=async()=>{try{await register()}catch(e){$('auth-info').textContent=e.message}};

await ensureCart();await Promise.all([loadStore(),loadProducts(),refreshCart()]);
