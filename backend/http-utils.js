function send(res, status, body) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'access-control-allow-headers': 'content-type,authorization,ngrok-skip-browser-warning'
  });
  res.end(JSON.stringify(body));
}
function sendHtml(res, status, html) {
  res.writeHead(status, {
    'content-type': 'text/html; charset=utf-8',
    'access-control-allow-origin': '*',
  });
  res.end(html);
}
function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    let rejected = false;
    req.on('data', (chunk) => {
      if (rejected) return;
      raw += chunk;
      if (raw.length > 12_000_000) {
        rejected = true;
        const error = new Error('Payload too large');
        error.statusCode = 413;
        reject(error);
      }
    });
    req.on('end', () => {
      if (rejected) return;
      try { resolve(raw ? JSON.parse(raw) : {}); }
      catch {
        const error = new Error('Invalid JSON');
        error.statusCode = 400;
        reject(error);
      }
    });
    req.on('error', reject);
  });
}

module.exports = { send, sendHtml, readBody };
