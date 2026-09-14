#!/usr/bin/env bash
set -Eeuo pipefail

SITE="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="/home/lojabelastock/backups/loja-visual-rc14-v33-$STAMP"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "$(id -un)" = "$APP_USER" ] || fail "Execute como $APP_USER."
[ -d "$SITE/public" ] || fail "Public ausente: $SITE/public"
[ -f "$SITE/public/storefront.js" ] || fail "storefront.js ausente"
[ -f "$SITE/src/server.mjs" ] || fail "server.mjs ausente"
mkdir -p "$BACKUP/public" "$BACKUP/src"
cp -a "$SITE/public/index.html" "$BACKUP/public/index.html.before"
cp -a "$SITE/src/server.mjs" "$BACKUP/src/server.mjs.before"
cp -a "$SITE/package.json" "$BACKUP/package.json.before"

cat > "$SITE/public/index.html" <<'HTML'
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bela Stock — Mega Portal</title>
<meta name="description" content="Bela Stock: mega portal multicanal, multiprodutos e multimercado com inteligência comercial.">
<link rel="stylesheet" href="/styles.css">
<style>
:root{--bsx-ink:#27211f;--bsx-muted:#786f6a;--bsx-purple:#7b2e8f;--bsx-purple2:#69237e;--bsx-orange:#e96c2d;--bsx-green:#2e9b57;--bsx-line:#e8ddd5;--bsx-cream:#fbf4ec;--bsx-panel:#fffdfb}
body.store-page{margin:0;background:#fffdfb;color:var(--bsx-ink);font-family:Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",Arial,sans-serif;font-size:16px}
body.store-page .topbar{display:none!important}
.bsx-wrap{width:min(1180px,calc(100% - 48px));margin:auto}
.bsx-head{height:82px;border-bottom:1px solid #eadfe9;background:#fff;display:flex;align-items:center;position:sticky;top:0;z-index:40}
.bsx-head .bsx-wrap{display:grid;grid-template-columns:245px minmax(280px,1fr) auto;gap:28px;align-items:center}
.bsx-brand{display:flex;align-items:center;gap:9px;font-weight:900;font-size:29px;letter-spacing:-.045em;color:#6c2b86}
.bsx-bag{width:42px;height:46px;border-radius:4px 4px 7px 7px;background:linear-gradient(145deg,#261235,#7a248d 56%,#9a45ae);position:relative;box-shadow:inset 0 0 18px rgba(255,255,255,.22)}
.bsx-bag:before{content:"";position:absolute;left:11px;top:-12px;width:18px;height:18px;border:2px solid #7b2d91;border-bottom:0;border-radius:13px 13px 0 0}
.bsx-bag:after{content:"B";position:absolute;inset:0;display:grid;place-items:center;color:#a05caf;font-size:25px;font-weight:900}
.bsx-brandtext{display:flex;flex-direction:column;line-height:1}.bsx-brandword span{color:#6e6268;font-weight:500}.bsx-tag{font-size:7px;font-weight:700;color:#51484e;letter-spacing:.025em;margin-top:-5px}
.bsx-search{display:flex;height:44px;background:#f5eff4;border-radius:999px;overflow:hidden;margin:0}
.bsx-search input{width:100%;border:0;outline:0;background:transparent;padding:0 20px;color:#5f565a;min-height:44px;border-radius:0}
.bsx-search button{width:49px;min-width:49px;min-height:44px;padding:0;border:0;border-radius:50%;background:#7f2a98;color:#fff;font-size:20px;display:grid;place-items:center}
.bsx-nav{display:flex;align-items:center;gap:22px;font-weight:750;font-size:15px;white-space:nowrap}
.bsx-nav a,.bsx-nav button{background:none;border:0;padding:0;color:var(--bsx-ink);font-weight:750;border-radius:0}
.bsx-cart{position:relative}.bsx-cart span{position:absolute;top:-11px;right:-16px;background:#ef6b28;color:#fff;border-radius:50%;width:21px;height:21px;display:grid;place-items:center;font-size:11px;font-weight:900}
.bsx-hero{background:radial-gradient(circle at 74% 37%,rgba(226,174,232,.38),transparent 30%),linear-gradient(120deg,#fffaf4 0,#fbf2ed 45%,#f9ecf8 100%);border-bottom:1px solid #eee3db}
.bsx-hero .bsx-wrap{min-height:570px;display:grid;grid-template-columns:1.06fr .94fr;gap:42px;align-items:center}
.bsx-copy{padding:56px 0 48px}.bsx-kicker{color:#8c2da5;font-weight:900;font-size:13px;letter-spacing:.18em;margin-bottom:16px}
.bsx-copy h1{font-family:Georgia,"Times New Roman",serif;font-size:62px;line-height:.91;letter-spacing:-.035em;margin:0 0 18px;font-weight:800;color:var(--bsx-ink)}
.bsx-copy h1 em{display:block;color:#8c2da5;font-weight:500}.bsx-copy p{max-width:565px;color:#7a6f68;font-size:17px;line-height:1.48;margin:0 0 23px}
.bsx-actions{display:flex;gap:13px;align-items:center}.bsx-btn{display:inline-flex;align-items:center;justify-content:center;height:50px;padding:0 22px;border-radius:14px;font-weight:850;border:1px solid #e5d9d2}
.bsx-btn.primary{background:#ef6b28;color:#fff;border-color:#ef6b28}.bsx-btn.secondary{background:#fff;color:#2e2926}
.bsx-checks{display:flex;gap:14px;flex-wrap:wrap;margin-top:27px;color:#766d68;font-size:13px;font-weight:750}.bsx-checks span:before{content:"✓";color:var(--bsx-green);margin-right:5px}
.bsx-orbit{height:470px;position:relative}.bsx-rings{position:absolute;left:50%;top:49%;width:430px;height:430px;transform:translate(-50%,-50%);border:1px dashed rgba(170,98,185,.35);border-radius:50%}.bsx-rings:after{content:"";position:absolute;inset:58px;border:1px dashed rgba(170,98,185,.35);border-radius:50%}
.bsx-core{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:188px;height:188px;border-radius:50%;background:#6a267b;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:0 20px 50px rgba(92,36,105,.18)}
.bsx-core strong{font-family:Georgia,"Times New Roman",serif;font-size:37px}.bsx-core small{font-size:12px;font-weight:850;letter-spacing:.16em;margin-top:8px}
.bsx-bubble{position:absolute;background:#fff;border:1px solid #eadfd9;border-radius:999px;min-width:98px;height:46px;display:flex;align-items:center;justify-content:center;font-weight:850;font-size:14px;box-shadow:0 7px 16px rgba(70,45,30,.025)}
.bsx-b1{left:49%;top:8%;transform:translateX(-50%)}.bsx-b2{right:0;top:29%}.bsx-b3{right:1%;bottom:19%}.bsx-b4{left:37%;bottom:3%}.bsx-b5{left:0;bottom:25%}.bsx-b6{left:-2%;top:26%}
.bsx-depart{padding:52px 0 60px;background:#fffdfa}.bsx-depart-head{display:flex;align-items:end;justify-content:space-between;gap:40px}.bsx-depart h2{font-family:Georgia,"Times New Roman",serif;font-size:43px;margin:7px 0 0;letter-spacing:-.025em;color:var(--bsx-ink)}.bsx-intro{max-width:390px;color:#7c726c;font-size:14px;line-height:1.5}
.bsx-cards{display:grid;grid-template-columns:repeat(4,1fr);gap:18px;margin-top:33px}.bsx-card{min-height:172px;border:1px solid #e9ddd6;border-radius:23px;padding:27px 22px;background:#fff;display:flex;gap:17px;position:relative}.bsx-ico{width:70px;height:70px;border-radius:17px;background:#f4eee7;color:#c14f32;display:grid;place-items:center;flex:0 0 auto}.bsx-ico svg{width:42px;height:42px;stroke:currentColor;fill:none;stroke-width:2.2}.bsx-card h3{font-size:19px;margin:5px 0 9px;color:var(--bsx-ink)}.bsx-card p{font-size:13px;line-height:1.55;color:#7d736d;margin:0}.bsx-badge{position:absolute;right:17px;bottom:16px;background:linear-gradient(90deg,#8b2d99,#ef6b28);color:#fff;border-radius:999px;padding:6px 14px;font-size:9px;font-weight:900}
.bsx-catalog{background:#f7f3f6;padding:54px 0 70px;border-top:1px solid #eee4ea}.bsx-catalog-head{display:flex;align-items:end;justify-content:space-between;gap:24px;margin-bottom:26px}.bsx-catalog h2{font-family:Georgia,"Times New Roman",serif;color:var(--bsx-ink);font-size:43px;margin:7px 0 0}.bsx-catalog .product-grid{grid-template-columns:repeat(auto-fill,minmax(245px,1fr));gap:18px}.bsx-catalog .product-card{border-radius:22px;border:1px solid #e8dde5;box-shadow:0 10px 30px rgba(54,35,65,.06)}.bsx-catalog .product-media{background:linear-gradient(145deg,#f3ecf7,#fff5ec);color:#7b2e8f}.bsx-catalog .product-bottom .btn{background:#e56a2e;border-radius:12px}.bsx-reload{background:#fff!important;color:#7b2e8f!important;border:1px solid #e1d6e5!important;border-radius:12px!important}
.bsx-foot{padding:28px 24px 42px;color:#817772;font-size:13px;text-align:center;border-top:1px solid #eee4ea;background:#fff}
.bsx-hidden-legacy{display:none!important}
body.store-page .drawer{z-index:90}body.store-page .backdrop{z-index:80}
@media(max-width:1000px){.bsx-head{height:auto;padding:16px 0}.bsx-head .bsx-wrap{grid-template-columns:1fr auto}.bsx-search{grid-column:1/-1;grid-row:2}.bsx-nav a:not(.bsx-cart-link):not(.bsx-login){display:none}.bsx-hero .bsx-wrap{grid-template-columns:1fr}.bsx-copy{padding-bottom:15px}.bsx-orbit{height:420px}.bsx-cards{grid-template-columns:repeat(2,1fr)}.bsx-depart-head{align-items:start;flex-direction:column;gap:8px}}
@media(max-width:600px){.bsx-wrap{width:min(100% - 28px,1180px)}.bsx-brand{font-size:24px}.bsx-bag{width:34px;height:38px}.bsx-nav{gap:15px}.bsx-copy{padding-top:42px}.bsx-copy h1{font-size:46px}.bsx-copy p{font-size:15px}.bsx-actions{align-items:stretch;flex-direction:column}.bsx-btn{width:100%}.bsx-checks{display:grid;gap:8px}.bsx-orbit{height:335px}.bsx-rings{width:310px;height:310px}.bsx-rings:after{inset:43px}.bsx-core{width:135px;height:135px}.bsx-core strong{font-size:28px}.bsx-bubble{height:38px;min-width:79px;font-size:11px}.bsx-b2,.bsx-b3{right:-2%}.bsx-b6{left:-2%}.bsx-depart{padding-top:38px}.bsx-depart h2,.bsx-catalog h2{font-size:35px}.bsx-cards{grid-template-columns:1fr}.bsx-card{min-height:140px}.bsx-catalog-head{align-items:start;flex-direction:column}.bsx-head{position:relative}}
</style>
</head>
<body class="store-page">
<div class="topbar" id="topbar" aria-hidden="true"></div>
<header class="bsx-head"><div class="bsx-wrap">
  <a class="bsx-brand" href="/"><span class="bsx-bag"></span><span class="bsx-brandtext"><span class="bsx-brandword"><span>Bela</span><strong>Stock</strong></span><span class="bsx-tag">VISTA-SE BEM E COMUNIQUE-SE MELHOR</span></span></a>
  <form class="bsx-search" id="store-search"><input id="store-search-input" aria-label="Buscar" placeholder="Buscar em todos os departamentos"><button type="submit" aria-label="Pesquisar">⌕</button></form>
  <nav class="bsx-nav"><a href="#departamentos">Eletrônicos</a><a href="#departamentos">Beleza</a><a href="#departamentos">Acessórios</a><button class="bsx-cart" id="cart-open" type="button">Carrinho <span id="cart-count">0</span></button><a class="bsx-login" href="/cliente">Entrar</a></nav>
</div></header>
<main>
<section class="bsx-hero"><div class="bsx-wrap">
  <div class="bsx-copy">
    <div class="bsx-kicker">BELA STOCK · PORTAL MULTICANAL</div>
    <h1>Um mega portal.<em>Muitos produtos.</em>Uma inteligência<br>comercial.</h1>
    <p>Eletrônicos, acessórios, maquiagem, casa, pets, moda, dropshipping, private label e produtos personalizados reunidos em uma operação inteligente.</p>
    <div class="bsx-actions"><a class="bsx-btn primary" href="#catalogo">Explorar departamentos</a><a class="bsx-btn secondary" href="#catalogo">Ver destaques inteligentes</a></div>
    <div class="bsx-checks"><span>Estoque próprio e dropshipping</span><span>Brasil e Estados Unidos</span><span>Margens protegidas</span></div>
  </div>
  <div class="bsx-orbit" aria-label="Ecossistema Bela Stock">
    <div class="bsx-rings"></div><div class="bsx-core"><strong>Bela Stock</strong><small>IA + MULTICANAL</small></div>
    <a class="bsx-bubble bsx-b1" href="#catalogo">Eletrônicos</a><a class="bsx-bubble bsx-b2" href="#catalogo">Beleza</a><a class="bsx-bubble bsx-b3" href="#catalogo">Casa</a><a class="bsx-bubble bsx-b4" href="#catalogo">Acessórios</a><a class="bsx-bubble bsx-b5" href="#catalogo">Pets</a><a class="bsx-bubble bsx-b6" href="#catalogo">Personalizados</a>
  </div>
</div></section>
<section class="bsx-depart" id="departamentos"><div class="bsx-wrap">
  <div class="bsx-depart-head"><div><div class="bsx-kicker" style="margin:0">MEGA CATÁLOGO</div><h2>Departamentos Bela Stock</h2></div><p class="bsx-intro">Cada segmento possui suas próprias regras de margem, fornecedor, entrega, conformidade e inteligência de preço.</p></div>
  <div class="bsx-cards">
    <a class="bsx-card" href="#catalogo"><span class="bsx-ico"><svg viewBox="0 0 48 48"><path d="M10 16h28v22H10zM16 16V9h16v7M6 38h36"/></svg></span><span><h3>Eletrônicos</h3><p>Tecnologia, áudio e soluções conectadas.</p></span></a>
    <a class="bsx-card" href="#catalogo"><span class="bsx-ico"><svg viewBox="0 0 48 48"><path d="M17 9h14v8H17zM14 17h20v25H14zM21 23h6v12h-6z"/></svg></span><span><h3>Beleza</h3><p>Maquiagem, cuidados e bem-estar.</p></span></a>
    <a class="bsx-card" href="#catalogo"><span class="bsx-ico"><svg viewBox="0 0 48 48"><path d="M6 23 24 8l18 15v19H6zM18 42V29h12v13"/></svg></span><span><h3>Casa</h3><p>Utilidades e itens para todos os ambientes.</p></span></a>
    <a class="bsx-card" href="#catalogo"><span class="bsx-ico"><svg viewBox="0 0 48 48"><path d="M10 8h28v34H10zM16 14h16v20H16zM20 38h8"/></svg></span><span><h3>Personalizados</h3><p>Produtos com estampas e composições exclusivas.</p></span><b class="bsx-badge">DESTAQUE IA</b></a>
  </div>
</div></section>
<section class="bsx-catalog" id="catalogo"><div class="bsx-wrap">
  <div class="bsx-catalog-head"><div><div class="bsx-kicker" style="margin:0">CATÁLOGO INTELIGENTE</div><h2>Produtos</h2></div><button class="bsx-reload" id="reload-products" type="button">Atualizar catálogo</button></div>
  <div id="products" class="product-grid"><div class="card">Carregando catálogo...</div></div>
</div></section>
</main>

<div class="bsx-hidden-legacy" aria-hidden="true">
  <section id="hero"><div id="hero-slider"><div id="hero-track"></div><div id="hero-subtitle"></div><div id="hero-title"></div><div id="hero-text"></div><a id="hero-cta"></a><button id="hero-prev" type="button"></button><button id="hero-next" type="button"></button><div id="hero-dots"></div></div></section>
</div>

<aside id="cart-drawer" class="drawer" aria-hidden="true">
  <div class="drawer-head"><div><div class="eyebrow">SEU PEDIDO</div><h2>Carrinho</h2></div><button class="icon-btn" id="cart-close" type="button">×</button></div>
  <div id="cart-items"></div><div id="cart-totals" class="totals"></div>
  <div class="card compact"><h3>Entrega</h3><select id="shipping-method"><option value="pickup">Retirada no local</option></select><button class="btn ghost full" id="quote-cart" type="button">Calcular total</button></div>
  <div class="card compact"><h3>Entrar para finalizar</h3><div class="tabs"><button id="tab-login" class="tab active" type="button">Entrar</button><button id="tab-register" class="tab" type="button">Criar conta</button></div>
    <div id="login-box"><input id="login-email" type="email" placeholder="E-mail"><input id="login-password" type="password" placeholder="Senha"><button class="btn full" id="login-btn" type="button">Entrar</button></div>
    <div id="register-box" hidden><input id="reg-name" placeholder="Nome"><input id="reg-email" type="email" placeholder="E-mail"><input id="reg-phone" placeholder="Telefone"><input id="reg-password" type="password" placeholder="Senha (mín. 8 caracteres)"><button class="btn full" id="register-btn" type="button">Criar conta e entrar</button></div>
    <div id="auth-info" class="muted"></div>
  </div>
  <div class="card compact"><h3>Endereço</h3><input id="addr-postal" placeholder="CEP"><input id="addr-street" placeholder="Rua"><div class="row"><input id="addr-number" placeholder="Número"><input id="addr-complement" placeholder="Complemento"></div><input id="addr-district" placeholder="Bairro"><div class="row"><input id="addr-city" placeholder="Cidade"><input id="addr-state" placeholder="UF"></div></div>
  <div class="card compact"><h3>Pagamento</h3><select id="payment-provider"><option value="manual_pix">PIX</option></select><button class="btn full" id="checkout-btn" type="button">Finalizar pedido</button><div id="checkout-result" class="notice"></div></div>
</aside>
<div id="drawer-backdrop" class="backdrop" hidden></div>
<footer class="bsx-foot"><strong>Bela Stock</strong> · Portal multicanal inteligente</footer>
<script src="/storefront.js"></script>
<script>
(function(){
  const form=document.getElementById('store-search');
  const input=document.getElementById('store-search-input');
  if(!form||!input)return;
  form.addEventListener('submit',function(e){
    e.preventDefault();
    const q=input.value.trim().toLowerCase();
    document.querySelectorAll('#products .product-card').forEach(function(card){
      card.style.display=!q||card.textContent.toLowerCase().includes(q)?'':'none';
    });
    document.getElementById('catalogo')?.scrollIntoView({behavior:'smooth',block:'start'});
  });
})();
</script>
</body>
</html>
HTML

node - "$SITE/src/server.mjs" <<'NODE'
const fs=require('fs');
const file=process.argv[2];
let s=fs.readFileSync(file,'utf8');
s=s.replace(/version:'3\.2\.0'/g,"version:'3.3.0'");
s=s.replace(/version:'3\.1\.0'/g,"version:'3.3.0'");
fs.writeFileSync(file,s);
NODE

node - "$SITE/package.json" <<'NODE'
const fs=require('fs');
const file=process.argv[2];
const p=JSON.parse(fs.readFileSync(file,'utf8'));
p.version='3.3.0';
p.description='Bela Stock AI Commerce - layout RC14 restaurado na loja Node com catalogo e checkout nativos';
fs.writeFileSync(file,JSON.stringify(p,null,2)+'\n');
NODE

cd "$SITE"
node --check src/server.mjs
node --check public/storefront.js

grep -q 'Um mega portal' public/index.html
grep -q 'Muitos produtos' public/index.html
grep -q 'Departamentos Bela Stock' public/index.html
grep -q 'id="products"' public/index.html
grep -q 'id="cart-open"' public/index.html
grep -q 'id="cart-drawer"' public/index.html
if grep -q 'VISTA SUA MELHOR VERSÃO' public/index.html; then fail "Layout antigo ainda presente"; fi

echo "BELA_STOCK_VERSION=$(node -p "require('./package.json').version")"
echo "BACKUP=$BACKUP"
echo "LOJA_VISUAL=RC14_APPROVED_REFERENCE"
ok "Layout público da loja corrigido sem remover catálogo, carrinho, login ou checkout."
