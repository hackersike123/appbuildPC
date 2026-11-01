const fs = require('node:fs');
const path = require('node:path');
const { send, sendHtml } = require('../http-utils');
const { auth } = require('../auth');

module.exports = async function handleSystemRoutes(context) {
  const { req, res, method, url, parts, body, user, id } = context;
  if (method === 'OPTIONS') return send(res, 204, {});
  if (method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true, service: 'pcbuild-local-api' });
  if (method === 'GET' && url.pathname === '/openapi.json') {
    return send(res, 200, JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'openapi.json'), 'utf8')));
  }
  if (method === 'GET' && url.pathname === '/docs') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'access-control-allow-origin': '*' });
    return res.end(`<!doctype html><html><head><title>PCBUILD LOCAL API</title><link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css"></head><body><div id="swagger-ui"></div><script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script><script>SwaggerUIBundle({url:'/openapi.json',dom_id:'#swagger-ui'});</script></body></html>`);
  }
  if (method === 'GET' && url.pathname === '/reset-password') {
    const token = JSON.stringify(url.searchParams.get('token') || '');
    return sendHtml(res, 200, `<!doctype html>
<html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Đặt lại mật khẩu - PCBUILD LOCAL</title>
<style>body{font-family:Arial,sans-serif;background:#070a0f;color:#fff;display:grid;place-items:center;min-height:100vh;margin:0}
main{width:min(390px,calc(100% - 40px));background:#101820;padding:28px;border-radius:16px;box-sizing:border-box}
h1{font-size:22px;text-align:center}.mint{color:#63e6be}label{display:block;margin-top:16px;color:#a8b4c0}
input{width:100%;box-sizing:border-box;padding:13px;margin-top:7px;border:1px solid #33404d;border-radius:10px;background:#0c121a;color:#fff}
button{width:100%;margin-top:22px;padding:14px;border:0;border-radius:10px;background:#63e6be;color:#07100e;font-weight:bold;cursor:pointer}
#message{margin-top:16px;line-height:1.4}</style></head>
<body><main><h1 class="mint">ĐẶT LẠI MẬT KHẨU</h1>
<label>Mật khẩu mới<input id="password" type="password" minlength="8"></label>
<label>Nhập lại mật khẩu<input id="confirmation" type="password" minlength="8"></label>
<button id="submit">CẬP NHẬT MẬT KHẨU</button><div id="message"></div>
<script>
const token=${token}; const message=document.getElementById('message');
document.getElementById('submit').onclick=async()=>{const password=document.getElementById('password').value;
const confirmation=document.getElementById('confirmation').value;
if(password.length<8||password!==confirmation){message.textContent='Mật khẩu phải có ít nhất 8 ký tự và hai ô phải giống nhau.';return;}
const response=await fetch('/api/v1/auth/reset-password',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({token,password})});
const data=await response.json(); message.textContent=data.message||'Đã xảy ra lỗi.';
if(response.ok) document.getElementById('submit').disabled=true;};
</script></main></body></html>`);
  }
};
