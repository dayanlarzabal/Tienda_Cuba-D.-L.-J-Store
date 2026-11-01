#!/usr/bin/env bash
# HANDMADE D.L.J STORE — genera la tienda web (carpeta site/) para publicarla en GitHub Pages.
# Lee los datos del servidor de las variables del repositorio:
#   SUPABASE_URL, SUPABASE_ANON_KEY y (opcional) APP_DOWNLOAD_URL.

SUPABASE_URL="${SUPABASE_URL:-}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"
APP_DOWNLOAD_URL="${APP_DOWNLOAD_URL:-}"

set -euo pipefail

SUPABASE_URL="$(echo "${SUPABASE_URL}" | tr -d ' \r\n"')"
SUPABASE_URL="${SUPABASE_URL%/}"
SUPABASE_ANON_KEY="$(echo "${SUPABASE_ANON_KEY}" | tr -d ' \r\n"')"
APP_DOWNLOAD_URL="$(echo "${APP_DOWNLOAD_URL}" | tr -d ' \r\n"')"

case "${SUPABASE_URL}" in https://*) ;; *) echo "ERROR: falta la variable SUPABASE_URL (debe empezar por https://)"; exit 1;; esac
case "${SUPABASE_ANON_KEY}" in eyJ*|sb_publishable_*) ;; *) echo "ERROR: falta la variable SUPABASE_ANON_KEY (clave anon o publishable)"; exit 1;; esac
if [ -n "${APP_DOWNLOAD_URL}" ]; then
  case "${APP_DOWNLOAD_URL}" in http://*|https://*) ;; *) echo "ERROR: APP_DOWNLOAD_URL debe empezar por http:// o https://"; exit 1;; esac
fi

echo "▶ Generando la tienda web…"
rm -rf site
mkdir -p site
touch site/.nojekyll

cat > site/config.js <<DLJ_CFG
window.DLJ = { url: "${SUPABASE_URL}", key: "${SUPABASE_ANON_KEY}", appUrl: "${APP_DOWNLOAD_URL}" };
DLJ_CFG

cat > site/index.html <<'DLJ_WEB'
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>HANDMADE D.L.J STORE</title>
<meta name="description" content="Apps y juegos para Android, arte, pintura, escultura y artesanías hechas a mano. Pagos en Transfermóvil, USDT, TRX y Bitcoin.">
<meta property="og:title" content="HANDMADE D.L.J STORE">
<meta property="og:description" content="Apps y juegos para Android, arte, pintura, escultura y artesanías hechas a mano.">
<meta name="theme-color" content="#061C41">
<link rel="icon" href="logo.png">
<style>
:root{--deep:#030F26;--navy:#061C41;--navy2:#0E2B5C;--coral:#F87171;--coral2:#E5484D;--gold:#E6C27A;--bg:#F4F6FB;--ink:#0B1630;--muted:#6B7794;--line:#E3E8F2;--ok:#16A34A;--warn:#F59E0B;--bad:#DC2626;--shadow:0 10px 30px rgba(6,28,65,.09)}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased}
button,input,textarea{font:inherit;color:inherit}
button{cursor:pointer;border:0;background:none}
a{color:inherit}
.wrap{max-width:1120px;margin:0 auto;padding:0 20px}
/* header */
header.top{position:sticky;top:0;z-index:30;background:rgba(3,15,38,.92);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);color:#fff}
header.top .wrap{display:flex;align-items:center;gap:12px;height:64px}
.brand{display:flex;align-items:center;gap:10px;text-decoration:none;min-width:0}
.brand img{width:38px;height:38px;border-radius:10px;flex:none}
.brand b{font-size:14px;letter-spacing:1.4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.spacer{flex:1}
.seg{display:inline-flex;background:rgba(255,255,255,.12);border-radius:30px;padding:3px}
.seg button{padding:6px 11px;border-radius:30px;font-size:12px;font-weight:800;color:rgba(255,255,255,.7)}
.seg button.on{background:var(--coral);color:#fff}
.seg.light{background:var(--line)}
.seg.light button{color:var(--muted)}
.seg.light button.on{background:var(--navy);color:#fff}
.ibtn{position:relative;width:42px;height:42px;border-radius:14px;background:rgba(255,255,255,.12);color:#fff;font-size:19px;display:grid;place-items:center}
.ibtn .n{position:absolute;top:-4px;right:-4px;min-width:19px;height:19px;border-radius:10px;background:var(--coral2);font-size:11px;font-weight:800;display:grid;place-items:center;padding:0 5px}
/* hero */
.hero{background:linear-gradient(135deg,var(--deep),var(--navy) 55%,var(--navy2));color:#fff;border-radius:0 0 34px 34px;padding:34px 0 30px}
.hero h1{margin:0 0 8px;font-size:clamp(28px,5vw,44px);line-height:1.1;letter-spacing:-.8px}
.hero p{margin:0 0 20px;color:rgba(255,255,255,.75);max-width:560px}
.hero .row{display:flex;flex-wrap:wrap;gap:12px;align-items:center}
.search{flex:1;min-width:220px;display:flex;align-items:center;gap:10px;background:#fff;color:var(--ink);border-radius:18px;padding:0 16px}
.search input{flex:1;border:0;outline:0;background:none;height:50px;font-weight:600}
.gold{color:var(--gold);font-weight:700;font-size:13px;letter-spacing:1px}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;height:50px;padding:0 22px;border-radius:16px;font-weight:800;text-decoration:none;white-space:nowrap}
.btn.coral{background:linear-gradient(135deg,var(--coral),var(--coral2));color:#fff;box-shadow:0 8px 20px rgba(248,113,113,.4)}
.btn.navy{background:var(--navy);color:#fff}
.btn.ghost{background:#fff;border:1.5px solid var(--line);color:var(--navy)}
.btn.block{width:100%}
.btn[disabled]{opacity:.45;pointer-events:none}
/* chips + grid */
.chips{display:flex;gap:10px;overflow-x:auto;padding:22px 0 6px;scrollbar-width:none}
.chips::-webkit-scrollbar{display:none}
.chip{flex:none;display:flex;align-items:center;gap:7px;background:#fff;border-radius:30px;padding:10px 16px;font-weight:700;box-shadow:0 4px 14px rgba(6,28,65,.05)}
.chip.on{background:var(--navy);color:#fff}
h2.sec{margin:26px 0 14px;font-size:20px;letter-spacing:-.3px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:18px;padding-bottom:40px}
.card{background:#fff;border-radius:22px;box-shadow:var(--shadow);overflow:hidden;display:flex;flex-direction:column;cursor:pointer;transition:transform .2s}
.card:hover{transform:translateY(-3px)}
.pic{position:relative;aspect-ratio:1/1;background:linear-gradient(135deg,var(--navy2),var(--navy));display:grid;place-items:center;font-size:54px;overflow:hidden}
.pic img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.badge{position:absolute;left:10px;top:10px;background:rgba(255,255,255,.95);color:var(--navy);border-radius:30px;padding:4px 10px;font-size:11px;font-weight:800}
.cbody{padding:12px 14px 14px;display:flex;align-items:flex-end;gap:8px;justify-content:space-between}
.cbody .t{min-width:0}
.cbody b{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cbody small{font-weight:700}
.cbody .p{display:block;margin-top:5px;font-weight:900}
.plus{flex:none;width:40px;height:40px;border-radius:13px;background:linear-gradient(135deg,var(--coral),var(--coral2));color:#fff;font-size:22px;font-weight:700}
.empty{text-align:center;padding:60px 20px;color:var(--muted)}
.empty h3{color:var(--ink);margin:0 0 6px}
/* overlay */
.ov{position:fixed;inset:0;z-index:50;background:rgba(3,15,38,.55);display:flex;justify-content:center;align-items:flex-end;animation:fade .2s}
.sheet{background:var(--bg);width:100%;max-width:560px;max-height:94vh;overflow-y:auto;border-radius:28px 28px 0 0;padding:22px 20px calc(24px + env(safe-area-inset-bottom));animation:up .25s}
.sheet.wide{max-width:760px}
@media(min-width:700px){.ov{align-items:center}.sheet{border-radius:28px;max-height:90vh}}
@keyframes fade{from{opacity:0}}@keyframes up{from{transform:translateY(30px);opacity:0}}
.shead{display:flex;align-items:center;gap:10px;margin-bottom:14px}
.shead h3{margin:0;flex:1;font-size:21px;letter-spacing:-.4px}
.x{width:38px;height:38px;border-radius:12px;background:#fff;font-size:18px;box-shadow:0 3px 10px rgba(6,28,65,.08)}
.panel{background:#fff;border-radius:20px;padding:16px;box-shadow:var(--shadow);margin-bottom:14px}
.pill{display:inline-flex;align-items:center;gap:5px;border-radius:30px;padding:4px 11px;font-size:12px;font-weight:800}
.big{font-size:30px;font-weight:900;letter-spacing:-.8px}
.muted{color:var(--muted)}
.tile{display:flex;gap:12px;background:#fff;border:1px solid var(--line);border-radius:16px;padding:12px;margin-bottom:10px}
.tile i{flex:none;width:38px;height:38px;border-radius:12px;background:rgba(6,28,65,.07);display:grid;place-items:center;font-style:normal;font-size:19px}
.tile b{display:block}.tile span{color:var(--muted);font-size:14px}
.pimg{border-radius:20px;overflow:hidden;margin-bottom:16px}
.pimg .pic{aspect-ratio:16/10}
/* forms */
label.f{display:block;margin-bottom:12px;font-size:13px;font-weight:700;color:var(--muted)}
label.f input,label.f textarea{display:block;width:100%;margin-top:6px;background:#fff;border:1.5px solid var(--line);border-radius:14px;padding:14px 15px;outline:0;color:var(--ink);font-weight:600}
label.f input:focus,label.f textarea:focus{border-color:var(--navy)}
.err{color:var(--bad);font-weight:700;margin:6px 0 12px;font-size:14px}
.method{display:flex;align-items:center;gap:12px;width:100%;text-align:left;background:#fff;border:1.5px solid var(--line);border-radius:18px;padding:13px 14px;margin-bottom:10px}
.method.on{border-color:var(--coral);box-shadow:var(--shadow)}
.method.off{opacity:.45;pointer-events:none}
.method i{flex:none;width:42px;height:42px;border-radius:13px;background:rgba(6,28,65,.08);display:grid;place-items:center;font-style:normal;font-size:20px}
.method .m{flex:1}.method .m b{display:block}.method .m small{color:var(--muted)}
.method .a{font-weight:900}
.copyrow{display:flex;align-items:center;gap:8px;background:var(--bg);border:1px solid var(--line);border-radius:14px;padding:10px 12px;margin-top:10px}
.copyrow div{flex:1;min-width:0}.copyrow small{display:block;color:var(--muted);font-weight:700;font-size:12px}
.copyrow code{display:block;font:700 14px ui-monospace,Menlo,Consolas,monospace;word-break:break-all}
.copyrow button{background:#fff;border:1px solid var(--line);border-radius:10px;padding:8px 12px;font-weight:800;font-size:13px}
.bank{background:linear-gradient(135deg,var(--deep),var(--navy),var(--navy2));color:#fff;border-radius:24px;padding:22px;margin-bottom:14px;box-shadow:0 14px 30px rgba(6,28,65,.35)}
.bank .chip2{display:inline-block;width:42px;height:30px;border-radius:7px;background:linear-gradient(135deg,var(--gold),#B8914A)}
.bank .num{font:700 clamp(17px,5vw,23px) ui-monospace,Menlo,Consolas,monospace;letter-spacing:2px;margin:26px 0 14px}
.bank small{color:rgba(255,255,255,.55);letter-spacing:1.5px;font-size:10px}
.warn{display:flex;gap:10px;background:#FFF4E5;border:1px solid rgba(245,158,11,.4);border-radius:16px;padding:12px;margin-bottom:14px;font-weight:600;font-size:14px}
.steps{padding-left:0;list-style:none;margin:6px 0 14px;counter-reset:s}
.steps li{counter-increment:s;display:flex;gap:10px;margin-bottom:9px;font-size:14.5px}
.steps li:before{content:counter(s);flex:none;width:24px;height:24px;border-radius:50%;background:rgba(248,113,113,.18);color:var(--coral2);font-weight:800;font-size:13px;display:grid;place-items:center}
.qr{display:grid;place-items:center;background:#fff;border:1px solid var(--line);border-radius:16px;padding:12px;margin:0 auto 6px;width:fit-content;min-height:60px}
.status{display:inline-flex;align-items:center;gap:6px;border-radius:30px;padding:5px 11px;font-size:12px;font-weight:800}
.order{background:#fff;border-radius:20px;padding:16px;box-shadow:var(--shadow);margin-bottom:12px}
.order .h{display:flex;align-items:center;gap:8px;justify-content:space-between;margin-bottom:6px}
.order .it{font-weight:600;margin:3px 0}
.dl{display:flex;align-items:center;gap:10px;background:rgba(22,163,74,.08);border-radius:14px;padding:10px 12px;margin-top:10px}
.dl b{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.dl a{background:var(--ok);color:#fff;text-decoration:none;font-weight:800;border-radius:11px;padding:9px 14px}
.note{border-radius:14px;padding:10px 12px;margin-top:10px;font-size:13.5px}
.cartrow{display:flex;gap:12px;align-items:center;background:#fff;border-radius:18px;padding:10px;box-shadow:var(--shadow);margin-bottom:12px}
.cartrow .pic{width:72px;height:72px;aspect-ratio:auto;border-radius:14px;font-size:30px;flex:none}
.cartrow .t{flex:1;min-width:0}.cartrow .t b{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.qty{display:flex;align-items:center;gap:2px;background:var(--bg);border-radius:12px}
.qty button{width:32px;height:32px;font-weight:800;font-size:17px}
.qty span{min-width:20px;text-align:center;font-weight:800}
.toast{position:fixed;left:50%;bottom:calc(24px + env(safe-area-inset-bottom));transform:translateX(-50%);z-index:90;background:var(--navy);color:#fff;border-radius:14px;padding:12px 18px;font-weight:700;box-shadow:0 10px 30px rgba(0,0,0,.3);max-width:90vw;text-align:center;animation:up .2s}
footer{background:var(--deep);color:rgba(255,255,255,.7);padding:30px 0 40px;font-size:14px}
footer b{color:#fff}
.spin{width:34px;height:34px;border:4px solid var(--line);border-top-color:var(--coral);border-radius:50%;margin:60px auto;animation:r .8s linear infinite}
@keyframes r{to{transform:rotate(360deg)}}
.okmark{width:96px;height:96px;border-radius:50%;background:linear-gradient(135deg,var(--coral),var(--coral2));color:#fff;font-size:52px;display:grid;place-items:center;margin:6px auto 18px;box-shadow:0 14px 30px rgba(248,113,113,.45)}
</style>
</head>
<body>
<noscript><p style="padding:24px">Esta tienda necesita JavaScript. / This store needs JavaScript.</p></noscript>
<div id="root"></div>
<script src="config.js"></script>
<script>
(() => {
'use strict';

// ───────────────────────── Configuración ─────────────────────────
const CFG = window.DLJ || {};
const BASE = String(CFG.url || '').replace(/\/+$/, '');
const KEY = String(CFG.key || '');

// ───────────────────────── Textos (ES / EN) ─────────────────────────
const T = {
  es: {
    brandSub: 'Apps · Arte · Artesanías', heroTitle: 'Piezas con identidad propia',
    heroSub: 'Apps y juegos para Android, arte, pintura, escultura y artesanías hechas a mano.',
    search: 'Buscar apps, cuadros, lámparas…', all: 'Todo', catalog: 'Catálogo',
    priceIn: 'Precios en', add: 'Añadir al carrito', added: 'Añadido al carrito',
    cart: 'Carrito', cartEmpty: 'Tu carrito está vacío', cartEmptyTxt: 'Explora la tienda y añade lo que te guste.',
    total: 'Total', checkout: 'Continuar al pago', orders: 'Mis pedidos',
    noOrders: 'Aún no tienes pedidos en este navegador.', digital: 'Entrega digital',
    digitalTxt: 'El enlace de descarga se libera cuando verificamos tu pago.', physical: 'Pieza física',
    physicalTxt: 'Coordinaremos el envío contigo por teléfono o WhatsApp.', share: 'Compartir', linkCopied: 'Enlace copiado',
    yourData: 'Tus datos', name: 'Nombre completo', phone: 'WhatsApp / teléfono (con código de país)',
    address: 'Dirección de entrega', payMethod: 'Método de pago', notAvail: 'No disponible',
    cont: 'Continuar', back: 'Atrás', exact: 'Monto exacto', destCard: 'Tarjeta destino', storeAddr: 'Dirección de la tienda',
    bank1: 'Abre Transfermóvil y elige «Transferir».', bank2: 'Pega la tarjeta destino y envía el monto exacto.',
    bank3: 'Copia el número de transacción del SMS o comprobante.', bank4: 'Pégalo aquí abajo y confirma.',
    refBank: 'Nº de transacción de Transfermóvil', refTx: 'TXID de la transacción (64 caracteres)',
    warnTron: 'Envía solo {a} por la red TRON (TRC20). Otra red o activo puede perder los fondos para siempre.',
    warnBtc: 'Envía solo Bitcoin (BTC) por la red Bitcoin. Otra red o activo puede perder los fondos para siempre.',
    rate: 'Tasa fijada por la tienda: {r}', openWallet: 'Abrir mi wallet', copy: 'Copiar', copied: 'Copiado',
    submit: 'Ya pagué · Enviar a verificación', sending: 'Enviando…',
    eName: 'Escribe tu nombre', ePhone: 'Teléfono no válido', eAddr: 'Escribe la dirección de entrega',
    eMethod: 'Elige un método de pago', eBank: 'Escribe el número de transacción (mínimo 6 caracteres)',
    eTx: 'El TXID debe tener 64 caracteres hexadecimales (0-9, a-f)',
    okTitle: '¡Pedido recibido!', okTxt: 'Verificaremos tu pago. Tu compra se libera en cuanto quede confirmado.',
    code: 'Código de pedido', sendWa: 'Enviar comprobante por WhatsApp',
    keep: 'Guarda tu código. Podrás ver el estado en «Mis pedidos» desde este mismo navegador.',
    st_pending: 'Pendiente de verificación', st_verified: 'Pago verificado', st_rejected: 'Pago rechazado', st_delivered: 'Entregado',
    pendingNote: 'Estamos verificando tu pago. Si tardamos, envía el comprobante por WhatsApp.',
    reason: 'Motivo', download: 'Descargar', refresh: 'Actualizar', loadErr: 'No pudimos cargar la tienda.',
    retry: 'Reintentar', none: 'Pronto habrá productos.', noRes: 'Sin resultados.', offline: 'Sin conexión con el servidor. Inténtalo de nuevo.',
    getApp: 'Descargar la app Android', foot: 'Los pagos se verifican manualmente antes de entregar tu compra.',
    holder: 'TITULAR / DESTINO', contact: 'Contactar por WhatsApp', close: 'Cerrar', paywith: 'Pagar con', payTotal: 'Total a pagar',
    waHello: 'Hola, acabo de pagar mi pedido {c}.', waMethod: 'Método', waAmount: 'Monto', waRef: 'Referencia', waName: 'Nombre',
    kind: {app:'App',game:'Juego',art:'Arte',painting:'Pintura',sculpture:'Escultura',craft:'Artesanía'},
    kinds: {app:'Apps',game:'Juegos',art:'Arte',painting:'Pinturas',sculpture:'Esculturas',craft:'Artesanías'}
  },
  en: {
    brandSub: 'Apps · Art · Crafts', heroTitle: 'Pieces with their own identity',
    heroSub: 'Android apps and games, art, paintings, sculpture and handmade crafts.',
    search: 'Search apps, paintings, lamps…', all: 'All', catalog: 'Catalog',
    priceIn: 'Prices in', add: 'Add to cart', added: 'Added to cart',
    cart: 'Cart', cartEmpty: 'Your cart is empty', cartEmptyTxt: 'Browse the store and add what you like.',
    total: 'Total', checkout: 'Continue to payment', orders: 'My orders',
    noOrders: 'You have no orders in this browser yet.', digital: 'Digital delivery',
    digitalTxt: 'The download link is unlocked once we verify your payment.', physical: 'Physical piece',
    physicalTxt: 'We will arrange shipping with you by phone or WhatsApp.', share: 'Share', linkCopied: 'Link copied',
    yourData: 'Your details', name: 'Full name', phone: 'WhatsApp / phone (with country code)',
    address: 'Delivery address', payMethod: 'Payment method', notAvail: 'Not available',
    cont: 'Continue', back: 'Back', exact: 'Exact amount', destCard: 'Destination card', storeAddr: 'Store address',
    bank1: 'Open Transfermóvil and choose “Transfer”.', bank2: 'Paste the destination card and send the exact amount.',
    bank3: 'Copy the transaction number from the SMS or receipt.', bank4: 'Paste it below and confirm.',
    refBank: 'Transfermóvil transaction no.', refTx: 'Transaction ID (64 characters)',
    warnTron: 'Send only {a} on the TRON network (TRC20). Another network or asset may lose the funds forever.',
    warnBtc: 'Send only Bitcoin (BTC) on the Bitcoin network. Another network or asset may lose the funds forever.',
    rate: 'Rate set by the store: {r}', openWallet: 'Open my wallet', copy: 'Copy', copied: 'Copied',
    submit: 'I paid · Send for verification', sending: 'Sending…',
    eName: 'Enter your name', ePhone: 'Invalid phone number', eAddr: 'Enter the delivery address',
    eMethod: 'Choose a payment method', eBank: 'Enter the transaction number (at least 6 characters)',
    eTx: 'The TXID must be 64 hexadecimal characters (0-9, a-f)',
    okTitle: 'Order received!', okTxt: 'We will verify your payment. Your purchase is released as soon as it is confirmed.',
    code: 'Order code', sendWa: 'Send receipt via WhatsApp',
    keep: 'Keep your code. You can track it under “My orders” from this same browser.',
    st_pending: 'Pending verification', st_verified: 'Payment verified', st_rejected: 'Payment rejected', st_delivered: 'Delivered',
    pendingNote: 'We are verifying your payment. If it takes long, send the receipt via WhatsApp.',
    reason: 'Reason', download: 'Download', refresh: 'Refresh', loadErr: 'We could not load the store.',
    retry: 'Retry', none: 'Products coming soon.', noRes: 'No results.', offline: 'Cannot reach the server. Please try again.',
    getApp: 'Get the Android app', foot: 'Payments are verified manually before your purchase is delivered.',
    holder: 'ACCOUNT HOLDER', contact: 'Contact on WhatsApp', close: 'Close', paywith: 'Pay with', payTotal: 'Total to pay',
    waHello: 'Hi, I just paid my order {c}.', waMethod: 'Method', waAmount: 'Amount', waRef: 'Reference', waName: 'Name',
    kind: {app:'App',game:'Game',art:'Art',painting:'Painting',sculpture:'Sculpture',craft:'Craft'},
    kinds: {app:'Apps',game:'Games',art:'Art',painting:'Paintings',sculpture:'Sculptures',craft:'Crafts'}
  }
};

const KINDS = {
  app: {ico: '📱', c: '#4F46E5'}, game: {ico: '🎮', c: '#F59E0B'}, art: {ico: '✨', c: '#9333EA'},
  painting: {ico: '🎨', c: '#E5484D'}, sculpture: {ico: '🗿', c: '#92400E'}, craft: {ico: '🛠️', c: '#0D9488'}
};
const STATUS_COLOR = {pending: '#F59E0B', verified: '#16A34A', rejected: '#DC2626', delivered: '#2563EB'};
const STATUS_ICO = {pending: '⏳', verified: '✔', rejected: '✖', delivered: '📦'};

// Métodos de pago y sus decimales (igual que el servidor)
const METHODS = [
  {id: 'transfermovilCup', cur: 'CUP', type: 'bank', ico: '💳', name: 'Transfermóvil CUP'},
  {id: 'transfermovilMlc', cur: 'MLC', type: 'bank', ico: '💳', name: 'Transfermóvil MLC'},
  {id: 'usdtTrc20', cur: 'USDT', type: 'tron', ico: '🪙', name: 'USDT · TRC20'},
  {id: 'trx', cur: 'TRX', type: 'tron', ico: '⚡', name: 'TRX · TRON'},
  {id: 'btc', cur: 'BTC', type: 'btc', ico: '₿', name: 'Bitcoin · BTC'}
];
const DEC = {CUP: 0, MLC: 2, USDT: 2, TRX: 2, BTC: 8};

// ───────────────────────── Utilidades ─────────────────────────
const ls = {
  get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* sin almacenamiento */ } }
};

function h(tag, props, ...kids) {
  const el = document.createElement(tag);
  if (props) {
    for (const k of Object.keys(props)) {
      const v = props[k];
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else if (k === 'style') el.style.cssText = v;
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? '' : v);
    }
  }
  for (const kid of kids.flat(Infinity)) {
    if (kid == null || kid === false) continue;
    el.append(kid);
  }
  return el;
}

const safeUrl = u => (/^https?:\/\//i.test(String(u || '')) ? String(u) : '');
const round = (v, d) => { const f = Math.pow(10, d); return Math.round((v + Number.EPSILON) * f) / f; };
const digits = s => String(s || '').replace(/\D/g, '');
const fmtCard = s => digits(s).replace(/(.{4})/g, '$1 ').trim();
const isTx = s => /^[0-9a-fA-F]{64}$/.test(String(s || '').trim());

const state = {
  lang: ls.get('dlj_lang', (navigator.language || 'es').toLowerCase().startsWith('es') ? 'es' : 'en'),
  cur: ls.get('dlj_cur', /-cu$/i.test(navigator.language || '') ? 'CUP' : 'USDT'),
  products: [], settings: {}, loading: true, error: '',
  cart: ls.get('dlj_cart', []),         // [{id, qty}]
  tokens: ls.get('dlj_orders', []),     // [{id, code, token}]
  orderData: [], kind: null, q: '', ov: null, co: null
};
const t = (k, vars) => {
  let s = (T[state.lang] && T[state.lang][k]) || T.es[k] || k;
  if (vars) for (const v of Object.keys(vars)) s = s.replace('{' + v + '}', vars[v]);
  return s;
};

function money(v, cur) {
  const d = DEC[cur];
  return Number(v).toLocaleString(state.lang === 'es' ? 'es' : 'en', {minimumFractionDigits: d, maximumFractionDigits: d}) + ' ' + cur;
}
const priceOf = (p, cur) => Number(cur === 'CUP' ? p.price_cup : cur === 'MLC' ? p.price_mlc : p.price_usdt) || 0;

function toast(msg) {
  document.querySelectorAll('.toast').forEach(n => n.remove());
  const n = h('div', {class: 'toast', text: msg});
  document.body.append(n);
  setTimeout(() => n.remove(), 2400);
}
async function copy(text, label) {
  try { await navigator.clipboard.writeText(text); }
  catch (e) {
    const ta = h('textarea', {style: 'position:fixed;opacity:0'}); ta.value = text; document.body.append(ta); ta.select();
    try { document.execCommand('copy'); } catch (e2) { /* nada */ } ta.remove();
  }
  toast((label ? label + ' · ' : '') + t('copied'));
}

// ───────────────────────── Servidor ─────────────────────────
async function api(path, opts) {
  let res;
  try {
    res = await fetch(BASE + path, Object.assign({}, opts, {
      headers: Object.assign({apikey: KEY, 'Content-Type': 'application/json'}, (opts && opts.headers) || {})
    }));
  } catch (e) { throw new Error(t('offline')); }
  const txt = await res.text();
  let body = null;
  try { body = txt ? JSON.parse(txt) : null; } catch (e) { /* no JSON */ }
  if (!res.ok) throw new Error((body && (body.message || body.msg || body.error)) || ('Error ' + res.status));
  return body;
}
const rpc = (name, args) => api('/rest/v1/rpc/' + name, {method: 'POST', body: JSON.stringify(args || {})});

async function load() {
  state.loading = true; state.error = ''; render();
  try {
    const [products, settings] = await Promise.all([
      api('/rest/v1/products?select=*&active=eq.true&order=sort.asc,created_at.desc'),
      api('/rest/v1/store_settings?select=*&id=eq.1')
    ]);
    state.products = products || [];
    state.settings = (settings && settings[0]) || {};
    cleanCart();
  } catch (e) { state.error = e.message; }
  state.loading = false; render();
  openFromHash();
  refreshOrders(true);
}

async function refreshOrders(quiet) {
  if (!state.tokens.length) return;
  try {
    state.orderData = await rpc('my_orders', {p_tokens: state.tokens.map(o => o.token)}) || [];
    if (state.ov === 'orders') renderOverlay();
  } catch (e) { if (!quiet) toast(e.message); }
}

// ───────────────────────── Carrito y montos ─────────────────────────
function cleanCart() {
  state.cart = state.cart.filter(c => state.products.some(p => p.id === c.id) && c.qty > 0);
  ls.set('dlj_cart', state.cart);
}
const prod = id => state.products.find(p => p.id === id);
const cartItems = () => state.cart.map(c => ({p: prod(c.id), qty: c.qty})).filter(c => c.p);
const cartCount = () => state.cart.reduce((s, c) => s + c.qty, 0);
const hasPhysical = () => cartItems().some(c => !c.p.is_digital);
function totalIn(cur) { return cartItems().reduce((s, c) => s + priceOf(c.p, cur) * c.qty, 0); }

function addToCart(id) {
  const c = state.cart.find(x => x.id === id);
  if (c) c.qty = Math.min(50, c.qty + 1); else state.cart.push({id, qty: 1});
  ls.set('dlj_cart', state.cart); render(); toast(t('added'));
}
function setQty(id, d) {
  const c = state.cart.find(x => x.id === id); if (!c) return;
  c.qty += d; if (c.qty <= 0) state.cart = state.cart.filter(x => x.id !== id);
  ls.set('dlj_cart', state.cart); render(); renderOverlay();
}

function methodAvailable(m) {
  const s = state.settings;
  switch (m.id) {
    case 'transfermovilCup': return !!s.cup_card;
    case 'transfermovilMlc': return !!s.mlc_card;
    case 'usdtTrc20': return !!s.tron_address;
    case 'trx': return !!s.tron_address && Number(s.trx_per_usdt) > 0;
    case 'btc': return !!s.btc_address && Number(s.btc_usdt_price) > 0;
    default: return false;
  }
}
function amountFor(m) {
  const s = state.settings;
  switch (m.id) {
    case 'transfermovilCup': return round(totalIn('CUP'), 0);
    case 'transfermovilMlc': return round(totalIn('MLC'), 2);
    case 'usdtTrc20': return round(totalIn('USDT'), 2);
    case 'trx': return round(totalIn('USDT') * Number(s.trx_per_usdt), 2);
    case 'btc': return round(totalIn('USDT') / Number(s.btc_usdt_price), 8);
    default: return 0;
  }
}
const amountText = m => amountFor(m).toFixed(DEC[m.cur]);

// ───────────────────────── Vistas ─────────────────────────
function pic(p, cls) {
  const k = KINDS[p.kind] || KINDS.app;
  const img = safeUrl(p.image_url);
  return h('div', {class: cls || 'pic', style: 'background:linear-gradient(135deg,' + k.c + ',#061C41)'},
    k.ico, img ? h('img', {src: img, alt: p.name, loading: 'lazy', onerror: e => e.target.remove()}) : null);
}

function render() {
  const root = document.getElementById('root');
  root.replaceChildren(header(), hero(), main(), footer());
}

function header() {
  const lang = h('div', {class: 'seg'}, ['es', 'en'].map(l =>
    h('button', {class: state.lang === l ? 'on' : '', text: l.toUpperCase(), onclick: () => { state.lang = l; ls.set('dlj_lang', l); document.documentElement.lang = l; render(); renderOverlay(); }})));
  return h('header', {class: 'top'}, h('div', {class: 'wrap'},
    h('a', {class: 'brand', href: '#'}, h('img', {src: 'logo.png', alt: ''}), h('b', {text: (state.settings.business_name || 'HANDMADE D.L.J STORE').toUpperCase()})),
    h('div', {class: 'spacer'}), lang,
    h('button', {class: 'ibtn', 'aria-label': t('orders'), onclick: () => { state.ov = 'orders'; renderOverlay(); refreshOrders(false); }}, '🧾'),
    h('button', {class: 'ibtn', 'aria-label': t('cart'), onclick: () => { state.ov = 'cart'; renderOverlay(); }}, '🛍️',
      cartCount() ? h('span', {class: 'n', text: String(cartCount())}) : null)));
}

function currencySwitch(light) {
  return h('div', {class: 'seg' + (light ? ' light' : '')}, ['USDT', 'CUP', 'MLC'].map(c =>
    h('button', {class: state.cur === c ? 'on' : '', text: c, onclick: () => { state.cur = c; ls.set('dlj_cur', c); render(); renderOverlay(); }})));
}

function hero() {
  const app = safeUrl(CFG.appUrl);
  return h('section', {class: 'hero'}, h('div', {class: 'wrap'},
    h('div', {class: 'gold', text: t('brandSub').toUpperCase()}),
    h('h1', {text: t('heroTitle')}), h('p', {text: t('heroSub')}),
    h('div', {class: 'row'},
      h('label', {class: 'search'}, '🔍', h('input', {type: 'search', placeholder: t('search'), value: state.q, 'aria-label': t('search'),
        oninput: e => { state.q = e.target.value; renderGrid(); }})),
      app ? h('a', {class: 'btn coral', href: app, text: '⬇ ' + t('getApp')}) : null),
    h('div', {class: 'row', style: 'margin-top:14px'}, h('span', {style: 'color:rgba(255,255,255,.7);font-weight:600', text: t('priceIn')}), currencySwitch(false))));
}

function main() {
  const wrap = h('main', {class: 'wrap'});
  if (state.loading) { wrap.append(h('div', {class: 'spin'})); return wrap; }
  if (state.error) {
    wrap.append(h('div', {class: 'empty'}, h('h3', {text: t('loadErr')}), h('p', {text: state.error}), h('button', {class: 'btn navy', text: t('retry'), onclick: load})));
    return wrap;
  }
  const kinds = Object.keys(KINDS).filter(k => state.products.some(p => p.kind === k));
  wrap.append(h('div', {class: 'chips'},
    h('button', {class: 'chip' + (state.kind ? '' : ' on'), text: t('all'), onclick: () => { state.kind = null; render(); }}),
    kinds.map(k => h('button', {class: 'chip' + (state.kind === k ? ' on' : ''), onclick: () => { state.kind = state.kind === k ? null : k; render(); }}, KINDS[k].ico, ' ', t('kinds')[k]))));
  wrap.append(h('h2', {class: 'sec', text: state.kind ? t('kinds')[state.kind] : t('catalog')}));
  wrap.append(h('div', {id: 'grid'}));
  queueMicrotask(renderGrid);
  return wrap;
}

function renderGrid() {
  const g = document.getElementById('grid'); if (!g) return;
  const q = state.q.trim().toLowerCase();
  const list = state.products.filter(p => (!state.kind || p.kind === state.kind) &&
    (!q || [p.name, p.subtitle, p.description].join(' ').toLowerCase().includes(q)));
  if (!list.length) {
    g.className = '';
    g.replaceChildren(h('div', {class: 'empty'}, h('h3', {text: state.products.length ? t('noRes') : t('none')})));
    return;
  }
  g.className = 'grid';
  g.replaceChildren(...list.map(card));
}

function card(p) {
  return h('article', {class: 'card', onclick: () => openProduct(p.id)},
    h('div', {class: 'pic', style: 'background:linear-gradient(135deg,' + (KINDS[p.kind] || KINDS.app).c + ',#061C41)'},
      (KINDS[p.kind] || KINDS.app).ico,
      safeUrl(p.image_url) ? h('img', {src: safeUrl(p.image_url), alt: p.name, loading: 'lazy', onerror: e => e.target.remove()}) : null,
      p.badge ? h('span', {class: 'badge', text: p.badge}) : null),
    h('div', {class: 'cbody'},
      h('div', {class: 't'}, h('b', {text: p.name}), h('small', {style: 'color:' + (KINDS[p.kind] || KINDS.app).c, text: t('kind')[p.kind] || ''}),
        h('span', {class: 'p', text: money(priceOf(p, state.cur), state.cur)})),
      h('button', {class: 'plus', 'aria-label': t('add'), text: '+', onclick: e => { e.stopPropagation(); addToCart(p.id); }})));
}

function footer() {
  const wa = digits(state.settings.whatsapp);
  return h('footer', null, h('div', {class: 'wrap'},
    h('b', {text: state.settings.business_name || 'HANDMADE D.L.J STORE'}), h('p', {text: t('foot')}),
    wa ? h('a', {href: 'https://wa.me/' + wa, target: '_blank', rel: 'noopener', style: 'color:var(--gold);font-weight:800', text: t('contact')}) : null));
}

// ───────────────────────── Ventanas ─────────────────────────
function closeOv() { state.ov = null; state.co = null; state.prodId = null; const o = document.getElementById('ov'); if (o) o.remove(); if (location.hash.startsWith('#p=')) history.replaceState(null, '', location.pathname + location.search); }

function renderOverlay() {
  const old = document.getElementById('ov');
  if (!state.ov) { if (old) old.remove(); return; }
  let body;
  if (state.ov === 'product') body = productSheet();
  else if (state.ov === 'cart') body = cartSheet();
  else if (state.ov === 'checkout') body = checkoutSheet();
  else if (state.ov === 'orders') body = ordersSheet();
  else return;
  const scroll = old ? old.firstChild.scrollTop : 0;
  const ov = h('div', {id: 'ov', class: 'ov', onclick: e => { if (e.target.id === 'ov') closeOv(); }}, body);
  if (old) old.replaceWith(ov); else document.body.append(ov);
  ov.firstChild.scrollTop = scroll;
}

function sheet(title, children, wide) {
  return h('div', {class: 'sheet' + (wide ? ' wide' : '')},
    h('div', {class: 'shead'}, h('h3', {text: title}), h('button', {class: 'x', 'aria-label': t('close'), text: '✕', onclick: closeOv})), children);
}

function openProduct(id) {
  state.prodId = id; state.ov = 'product'; renderOverlay();
  history.replaceState(null, '', '#p=' + id);
}
function openFromHash() {
  const m = /^#p=([0-9a-fA-F-]{36})$/.exec(location.hash);
  if (m && prod(m[1])) openProduct(m[1]);
}

function productSheet() {
  const p = prod(state.prodId); if (!p) return sheet('', []);
  const k = KINDS[p.kind] || KINDS.app;
  const link = location.origin + location.pathname + '#p=' + p.id;
  return sheet(p.name, [
    h('div', {class: 'pimg'}, pic(p)),
    h('div', {style: 'display:flex;gap:8px;flex-wrap:wrap;margin-bottom:8px'},
      h('span', {class: 'pill', style: 'background:' + k.c + '1a;color:' + k.c, text: k.ico + ' ' + (t('kind')[p.kind] || '')}),
      p.badge ? h('span', {class: 'pill', style: 'background:#E5484D1a;color:#E5484D', text: p.badge}) : null),
    p.subtitle ? h('p', {class: 'muted', style: 'margin:4px 0 14px;font-weight:600', text: p.subtitle}) : null,
    h('div', {class: 'panel'},
      h('div', {style: 'display:flex;align-items:center;justify-content:space-between'}, h('b', {class: 'muted', text: t('priceIn')}), currencySwitch(true)),
      h('div', {class: 'big', style: 'margin:8px 0 4px', text: money(priceOf(p, state.cur), state.cur)}),
      h('div', {class: 'muted', style: 'font-weight:600;font-size:14px', text: ['USDT', 'CUP', 'MLC'].filter(c => c !== state.cur).map(c => money(priceOf(p, c), c)).join('  ·  ')})),
    p.description ? h('p', {style: 'white-space:pre-wrap;color:#3B4663', text: p.description}) : null,
    h('div', {class: 'tile'}, h('i', {text: p.is_digital ? '⚡' : '🚚'}), h('div', null, h('b', {text: p.is_digital ? t('digital') : t('physical')}), h('span', {text: p.is_digital ? t('digitalTxt') : t('physicalTxt')}))),
    h('div', {style: 'display:flex;gap:10px;margin-top:6px'},
      h('button', {class: 'btn coral', style: 'flex:1', text: '🛍️ ' + t('add'), onclick: () => { addToCart(p.id); }}),
      h('button', {class: 'btn ghost', text: '↗ ' + t('share'), onclick: async () => {
        if (navigator.share) { try { await navigator.share({title: p.name, url: link}); return; } catch (e) { /* cancelado */ } }
        copy(link, t('linkCopied'));
      }}))
  ]);
}

function cartSheet() {
  const items = cartItems();
  if (!items.length) return sheet(t('cart'), h('div', {class: 'empty'}, h('h3', {text: t('cartEmpty')}), h('p', {text: t('cartEmptyTxt')})));
  return sheet(t('cart'), [
    items.map(({p, qty}) => h('div', {class: 'cartrow'}, pic(p),
      h('div', {class: 't'}, h('b', {text: p.name}), h('span', {class: 'muted', style: 'font-size:13px', text: p.is_digital ? t('digital') : t('physical')}),
        h('div', {style: 'font-weight:900;margin-top:4px', text: money(priceOf(p, state.cur) * qty, state.cur)})),
      h('div', {class: 'qty'}, h('button', {text: '−', onclick: () => setQty(p.id, -1)}), h('span', {text: String(qty)}), h('button', {text: '+', onclick: () => setQty(p.id, 1)})))),
    h('div', {class: 'panel'},
      h('div', {style: 'display:flex;justify-content:space-between;align-items:center'}, h('b', {class: 'muted', text: t('total')}), currencySwitch(true)),
      h('div', {class: 'big', style: 'margin-top:6px', text: money(totalIn(state.cur), state.cur)}),
      h('div', {class: 'muted', style: 'font-weight:600;font-size:14px;margin-top:4px', text: ['USDT', 'CUP', 'MLC'].filter(c => c !== state.cur).map(c => money(totalIn(c), c)).join('  ·  ')})),
    h('button', {class: 'btn coral block', text: '🔒 ' + t('checkout'), onclick: startCheckout})
  ]);
}

// ───────────────────────── Pago ─────────────────────────
function startCheckout() {
  const saved = ls.get('dlj_profile', {});
  state.co = {step: 1, name: saved.name || '', phone: saved.phone || '', address: saved.address || '', method: null, ref: '', busy: false, error: '', order: null};
  state.ov = 'checkout'; renderOverlay();
  // Refresca precios y datos de cobro antes de pagar
  Promise.all([api('/rest/v1/products?select=*&active=eq.true'), api('/rest/v1/store_settings?select=*&id=eq.1')]).then(([p, s]) => {
    state.products = p || state.products; state.settings = (s && s[0]) || state.settings; cleanCart(); if (state.ov === 'checkout' && state.co && state.co.step === 1) renderOverlay();
  }).catch(() => {});
}

function checkoutSheet() {
  const co = state.co;
  if (!co) return sheet('', []);
  if (co.step === 3) return successSheet();
  if (co.step === 2) return paySheet();
  const physical = hasPhysical();
  const field = (key, label, extra) => h('label', {class: 'f'}, label,
    extra && extra.area
      ? h('textarea', {rows: 2, text: co[key], oninput: e => { co[key] = e.target.value; }})
      : h('input', Object.assign({value: co[key], oninput: e => { co[key] = e.target.value; }}, extra && extra.attrs)));
  return sheet(t('checkout'), [
    h('h4', {style: 'margin:0 0 10px', text: '1 · ' + t('yourData')}),
    field('name', t('name'), {attrs: {autocomplete: 'name'}}),
    field('phone', t('phone'), {attrs: {type: 'tel', autocomplete: 'tel', placeholder: '+53 5xxxxxxx'}}),
    physical ? field('address', t('address'), {area: true}) : null,
    h('h4', {style: 'margin:18px 0 10px', text: '2 · ' + t('payMethod')}),
    METHODS.filter(m => (m.id !== 'trx' && m.id !== 'btc') || methodAvailable(m)).map(m => {
      const ok = methodAvailable(m);
      return h('button', {class: 'method' + (co.method === m.id ? ' on' : '') + (ok ? '' : ' off'), onclick: () => { co.method = m.id; renderOverlay(); }},
        h('i', {text: m.ico}), h('div', {class: 'm'}, h('b', {text: m.name}), h('small', {text: ok ? '' : t('notAvail')})),
        ok ? h('span', {class: 'a', text: money(amountFor(m), m.cur)}) : null);
    }),
    co.error ? h('div', {class: 'err', text: co.error}) : null,
    h('button', {class: 'btn coral block', style: 'margin-top:8px', text: t('cont') + ' →', onclick: () => {
      if (co.name.trim().length < 3) { co.error = t('eName'); return renderOverlay(); }
      if (digits(co.phone).length < 8) { co.error = t('ePhone'); return renderOverlay(); }
      if (physical && co.address.trim().length < 8) { co.error = t('eAddr'); return renderOverlay(); }
      if (!co.method) { co.error = t('eMethod'); return renderOverlay(); }
      co.error = ''; co.step = 2; co.ref = ''; renderOverlay();
    }})
  ]);
}

function paySheet() {
  const co = state.co;
  const m = METHODS.find(x => x.id === co.method);
  const s = state.settings;
  const amt = amountText(m);
  const body = [];

  if (m.type === 'bank') {
    const card = m.id === 'transfermovilCup' ? s.cup_card : s.mlc_card;
    body.push(h('div', {class: 'bank'},
      h('div', {style: 'display:flex;justify-content:space-between;align-items:center'}, h('span', {class: 'chip2'}), h('span', {class: 'pill', style: 'background:rgba(255,255,255,.14);color:#fff', text: m.cur})),
      h('div', {class: 'num', text: fmtCard(card)}),
      h('small', {text: t('holder')}), h('div', {style: 'font-weight:700;letter-spacing:1.2px', text: String(s.business_name || '').toUpperCase()})));
    body.push(h('div', {class: 'panel'},
      h('div', {class: 'muted', style: 'font-weight:700', text: t('exact')}),
      h('div', {class: 'big', text: amt + ' ' + m.cur}),
      h('div', {class: 'copyrow'}, h('div', null, h('small', {text: t('exact')}), h('code', {text: amt})), h('button', {text: t('copy'), onclick: () => copy(amt, t('exact'))})),
      h('div', {class: 'copyrow'}, h('div', null, h('small', {text: t('destCard')}), h('code', {text: fmtCard(card)})), h('button', {text: t('copy'), onclick: () => copy(digits(card), t('destCard'))}))));
    body.push(h('ol', {class: 'steps'}, ['bank1', 'bank2', 'bank3', 'bank4'].map(k => h('li', {text: t(k)}))));
  } else {
    const isBtc = m.type === 'btc';
    const addr = isBtc ? s.btc_address : s.tron_address;
    const uri = isBtc ? 'bitcoin:' + addr + '?amount=' + amt : 'tron:' + addr;
    body.push(h('div', {class: 'bank'},
      h('span', {class: 'pill', style: 'background:rgba(255,255,255,.14);color:var(--gold)', text: isBtc ? 'Bitcoin' : 'TRON · TRC20'}),
      h('div', {style: 'color:rgba(255,255,255,.6);margin-top:14px;font-weight:600', text: t('exact')}),
      h('div', {style: 'font-size:clamp(24px,7vw,32px);font-weight:900;letter-spacing:-.8px', text: amt + ' ' + m.cur}),
      m.id === 'trx' ? h('div', {style: 'color:rgba(255,255,255,.55);font-size:13px;margin-top:4px', text: t('rate', {r: '1 USDT = ' + s.trx_per_usdt + ' TRX'})}) : null,
      isBtc ? h('div', {style: 'color:rgba(255,255,255,.55);font-size:13px;margin-top:4px', text: t('rate', {r: '1 BTC = ' + s.btc_usdt_price + ' USDT'})}) : null));
    body.push(h('div', {class: 'warn'}, '⚠️', h('span', {text: isBtc ? t('warnBtc') : t('warnTron', {a: m.cur})})));
    const qr = h('div', {class: 'qr', id: 'qrbox'});
    body.push(h('div', {class: 'panel'}, qr,
      h('div', {class: 'copyrow'}, h('div', null, h('small', {text: t('exact')}), h('code', {text: amt})), h('button', {text: t('copy'), onclick: () => copy(amt, t('exact'))})),
      h('div', {class: 'copyrow'}, h('div', null, h('small', {text: t('storeAddr')}), h('code', {text: addr})), h('button', {text: t('copy'), onclick: () => copy(addr, t('storeAddr'))})),
      h('a', {class: 'btn ghost block', style: 'margin-top:12px', href: uri, text: '↗ ' + t('openWallet')})));
    drawQR(qr, isBtc ? uri : addr);
  }

  const refLabel = m.type === 'bank' ? t('refBank') : t('refTx');
  body.push(h('label', {class: 'f'}, refLabel, h('input', {value: co.ref, autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false', oninput: e => { co.ref = e.target.value; }})));
  if (co.error) body.push(h('div', {class: 'err', text: co.error}));
  body.push(h('div', {style: 'display:flex;gap:10px'},
    h('button', {class: 'btn ghost', text: '← ' + t('back'), onclick: () => { co.step = 1; co.error = ''; renderOverlay(); }}),
    h('button', {class: 'btn coral', style: 'flex:1', disabled: co.busy, text: co.busy ? t('sending') : t('submit'), onclick: submitOrder})));
  return sheet(t('paywith') + ' ' + m.name, body);
}

let qrLoader = null;
function loadQR() {
  if (window.QRCode) return Promise.resolve();
  if (!qrLoader) qrLoader = new Promise((res, rej) => {
    const s = document.createElement('script');
    s.src = 'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js';
    s.onload = res; s.onerror = () => { qrLoader = null; rej(new Error('qr')); };
    document.head.append(s);
  });
  return qrLoader;
}
function drawQR(box, text) {
  loadQR().then(() => {
    const el = document.getElementById('qrbox') || box;
    el.replaceChildren();
    new window.QRCode(el, {text, width: 176, height: 176, colorDark: '#061C41', colorLight: '#ffffff', correctLevel: window.QRCode.CorrectLevel.M});
  }).catch(() => { box.style.display = 'none'; });
}

async function submitOrder() {
  const co = state.co;
  const m = METHODS.find(x => x.id === co.method);
  const ref = co.ref.trim();
  if (m.type === 'bank' ? (ref.length < 6 || ref.length > 40) : !isTx(ref)) { co.error = m.type === 'bank' ? t('eBank') : t('eTx'); return renderOverlay(); }
  co.error = ''; co.busy = true; renderOverlay();
  try {
    const r = await rpc('create_order', {
      p_lines: cartItems().map(c => ({product_id: c.p.id, qty: c.qty})),
      p_method: m.id, p_reference: ref, p_name: co.name.trim(), p_phone: co.phone.trim(),
      p_address: hasPhysical() ? co.address.trim() : '', p_wallet: ''
    });
    state.tokens.unshift({id: r.id, code: r.code, token: r.access_token});
    ls.set('dlj_orders', state.tokens);
    ls.set('dlj_profile', {name: co.name.trim(), phone: co.phone.trim(), address: co.address.trim()});
    co.order = {code: r.code, amount: Number(r.amount), method: m, ref, name: co.name.trim(), phone: co.phone.trim(), address: hasPhysical() ? co.address.trim() : '', items: cartItems().map(c => c.p.name + ' ×' + c.qty)};
    state.cart = []; ls.set('dlj_cart', state.cart);
    co.step = 3; co.busy = false; render(); renderOverlay(); refreshOrders(true);
  } catch (e) { co.busy = false; co.error = e.message; renderOverlay(); }
}

function successSheet() {
  const o = state.co.order;
  const wa = digits(state.settings.whatsapp);
  const msg = t('waHello', {c: o.code}) + '\n\n' + o.items.map(i => '• ' + i).join('\n') + '\n\n' +
    t('waMethod') + ': ' + o.method.name + '\n' + t('waAmount') + ': ' + o.amount.toFixed(DEC[o.method.cur]) + ' ' + o.method.cur + '\n' +
    t('waRef') + ': ' + o.ref + '\n' + t('waName') + ': ' + o.name + '\n' + o.phone + (o.address ? '\n' + o.address : '');
  return sheet(t('okTitle'), [
    h('div', {class: 'okmark', text: '✓'}),
    h('p', {class: 'muted', style: 'text-align:center', text: t('okTxt')}),
    h('div', {class: 'panel'}, statusPill('pending'),
      h('div', {class: 'copyrow'}, h('div', null, h('small', {text: t('code')}), h('code', {text: o.code})), h('button', {text: t('copy'), onclick: () => copy(o.code, t('code'))}))),
    h('p', {class: 'muted', style: 'font-size:14px', text: t('keep')}),
    wa ? h('a', {class: 'btn coral block', style: 'margin-bottom:10px', target: '_blank', rel: 'noopener', href: 'https://wa.me/' + wa + '?text=' + encodeURIComponent(msg), text: '💬 ' + t('sendWa')}) : null,
    h('button', {class: 'btn navy block', text: t('orders'), onclick: () => { state.co = null; state.ov = 'orders'; renderOverlay(); }})
  ]);
}

// ───────────────────────── Pedidos ─────────────────────────
function statusPill(st) {
  const c = STATUS_COLOR[st] || '#6B7794';
  return h('span', {class: 'status', style: 'background:' + c + '1f;color:' + c, text: (STATUS_ICO[st] || '') + ' ' + t('st_' + st)});
}

function ordersSheet() {
  const list = state.orderData;
  return sheet(t('orders'), [
    h('button', {class: 'btn ghost block', style: 'height:44px;margin-bottom:14px', text: '↻ ' + t('refresh'), onclick: () => refreshOrders(false)}),
    !state.tokens.length ? h('div', {class: 'empty'}, h('p', {text: t('noOrders')})) : null,
    list.map(o => { const mm = METHODS.find(x => x.id === o.method) || {name: o.method, cur: 'USDT'}; return h('div', {class: 'order'},
      h('div', {class: 'h'}, h('b', {text: o.code}), statusPill(o.status)),
      h('div', {class: 'muted', style: 'font-size:13px;margin-bottom:6px', text: new Date(o.created_at).toLocaleString(state.lang === 'es' ? 'es' : 'en')}),
      (o.items || []).map(i => h('div', {class: 'it', text: i.name + ' ×' + i.qty})),
      h('div', {style: 'display:flex;justify-content:space-between;margin-top:8px'},
        h('span', {class: 'muted', style: 'font-weight:600', text: mm.name}),
        h('b', {text: Number(o.amount).toFixed(DEC[mm.cur]) + ' ' + mm.cur})),
      o.status === 'pending' ? h('div', {class: 'note', style: 'background:#F59E0B14', text: t('pendingNote')}) : null,
      o.status === 'rejected' && o.seller_note ? h('div', {class: 'note', style: 'background:#DC262614', text: t('reason') + ': ' + o.seller_note}) : null,
      (o.status === 'verified' || o.status === 'delivered') ? (o.items || []).filter(i => i.download_url && safeUrl(i.download_url)).map(i =>
        h('div', {class: 'dl'}, h('b', {text: i.name}), h('a', {href: safeUrl(i.download_url), target: '_blank', rel: 'noopener', text: '⬇ ' + t('download')}))) : null); })
  ], true);
}

// ───────────────────────── Arranque ─────────────────────────
document.documentElement.lang = state.lang;
if (!BASE || !KEY) {
  document.getElementById('root').append(h('div', {class: 'empty'}, h('h3', {text: 'Tienda sin configurar'}), h('p', {text: 'Faltan SUPABASE_URL y SUPABASE_ANON_KEY.'})));
} else {
  render(); load();
  setInterval(() => { if (document.visibilityState === 'visible' && state.orderData.some(o => o.status === 'pending')) refreshOrders(true); }, 60000);
  window.addEventListener('hashchange', openFromHash);
}
})();
</script>
</body>
</html>
DLJ_WEB

base64 -d > site/logo.png <<'DLJ_B64'
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
DLJ_B64

echo "✔ Tienda web lista en site/"
