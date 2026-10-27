(async()=>{
const { chromium } = require('playwright');
const { readFileSync } = require('fs');
const svg = readFileSync(process.argv[2], 'utf8');
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
await p.setContent(`<html><body style="margin:0">${svg.replace('<svg ', '<svg width="1024" height="1024" ')}</body></html>`);
await p.screenshot({ path: process.argv[3], omitBackground: false }); await b.close();
})();
