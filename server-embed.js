const http = require('http');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

let scanScriptPath = path.join(__dirname, 'scan.ps1');
let remoteScriptPath = path.join(__dirname, 'scan-remote.ps1');
const HISTORY_DIR = path.join(__dirname, 'scan-history');
const activeAgents = new Map();

function ensureHistoryDir(){ if(!fs.existsSync(HISTORY_DIR)) fs.mkdirSync(HISTORY_DIR,{recursive:true}); }

function serveStatic(res, filePath) {
  const ext = path.extname(filePath);
  const mimeTypes = {'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'application/javascript; charset=utf-8','.json':'application/json; charset=utf-8','.png':'image/png','.svg':'image/svg+xml','.ico':'image/x-icon'};
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, { 'Content-Type': mimeTypes[ext]||'text/plain' }); res.end(data);
  });
}

function jsonRes(res,code,obj){res.writeHead(code,{'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(obj));}
function readBody(req){return new Promise(r=>{let b='';req.on('data',c=>b+=c);req.on('end',()=>r(b))});}

function saveHistory(data){
  ensureHistoryDir();
  const id=`${Date.now()}-${(data.computerName||'unknown').replace(/[^a-zA-Z0-9]/g,'')}`;
  const meta={id,computerName:data.computerName||'Unknown',userName:data.userName||'',osVersion:data.osVersion||'',timestamp:data.timestamp||new Date().toISOString(),totalApps:data.totalApps||0,warnings:(data.crackWarnings||[]).length,riskLevel:(data.riskSummary||{}).riskLevel||'Clean'};
  fs.writeFileSync(path.join(HISTORY_DIR,`${id}.json`),JSON.stringify(data,null,2),'utf8');
  const indexFile=path.join(HISTORY_DIR,'index.json');
  let index=[]; try{index=JSON.parse(fs.readFileSync(indexFile,'utf8'))}catch{}
  index.unshift(meta); if(index.length>100)index=index.slice(0,100);
  fs.writeFileSync(indexFile,JSON.stringify(index,null,2),'utf8');
  return id;
}

function runScan(target,username,password){
  return new Promise((resolve,reject)=>{
    let cmd;
    if(!target||target==='localhost'||target==='127.0.0.1'){
      cmd=`powershell -NoProfile -ExecutionPolicy Bypass -File "${scanScriptPath}"`;
    } else {
      const args=[`-TargetComputer "${target}"`];
      if(username)args.push(`-Username "${username}"`);
      if(password)args.push(`-Password "${password}"`);
      cmd=`powershell -NoProfile -ExecutionPolicy Bypass -File "${remoteScriptPath}" ${args.join(' ')}`;
    }
    exec(cmd,{maxBuffer:50*1024*1024,encoding:'utf8',timeout:300000},(error,stdout)=>{
      if(error)return reject(new Error(error.message));
      try{const i=stdout.indexOf('{');if(i===-1)return reject(new Error('No JSON'));resolve(JSON.parse(stdout.substring(i)));}
      catch(e){reject(new Error('Parse: '+e.message));}
    });
  });
}

setInterval(() => {
  const now = Date.now();
  for (const [id, agent] of activeAgents.entries()) {
    if (now - agent.lastSeen > 15000) activeAgents.delete(id);
  }
}, 10000);

function startServer(port, scriptPath) {
  if (scriptPath) { scanScriptPath = scriptPath; remoteScriptPath = path.join(path.dirname(scriptPath),'scan-remote.ps1'); }

  const server = http.createServer(async (req, res) => {
    const parsedUrl = new URL(req.url, `http://localhost:${port}`);
    const pathname = parsedUrl.pathname;
    res.setHeader('Access-Control-Allow-Origin','*');
    res.setHeader('Access-Control-Allow-Methods','GET, POST, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers','Content-Type');
    if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}

    if (pathname === '/api/agents/ping') {
      const id = parsedUrl.searchParams.get('id'), name = parsedUrl.searchParams.get('name') || id, os = parsedUrl.searchParams.get('os') || '';
      if (!id) { jsonRes(res, 400, { error: 'Agent ID required' }); return; }
      let agent = activeAgents.get(id);
      if (!agent) agent = { id, name, os, ip: req.socket.remoteAddress, status: 'idle', pendingCommand: null, lastResultId: null };
      agent.lastSeen = Date.now();
      let command = agent.pendingCommand;
      if (command) { agent.status = 'scanning'; agent.pendingCommand = null; }
      activeAgents.set(id, agent);
      jsonRes(res, 200, { success: true, command: command });
      return;
    }
    if (pathname === '/api/agents' && req.method === 'GET') {
      jsonRes(res, 200, Array.from(activeAgents.values()).map(a => ({ ...a, isOnline: (Date.now() - a.lastSeen) < 15000 })));
      return;
    }
    const agentCommandMatch = pathname.match(/^\/api\/scan\/command\/(.+)$/);
    if (agentCommandMatch && req.method === 'POST') {
      const id = agentCommandMatch[1], agent = activeAgents.get(id);
      if (!agent) { jsonRes(res, 404, { error: 'Not found' }); return; }
      agent.pendingCommand = 'SCAN'; agent.status = 'scanning';
      jsonRes(res, 200, { success: true });
      return;
    }
    if (pathname === '/api/scan/upload' && req.method === 'POST') {
      const id = parsedUrl.searchParams.get('id');
      try {
        const data = JSON.parse(await readBody(req)); const historyId = saveHistory(data);
        if (id && activeAgents.has(id)) { const agent = activeAgents.get(id); agent.status = 'idle'; agent.lastResultId = historyId; }
        jsonRes(res, 200, { success: true, historyId });
      } catch (err) {
        if (id && activeAgents.has(id)) activeAgents.get(id).status = 'error';
        jsonRes(res, 500, { error: err.message });
      }
      return;
    }

    if(pathname==='/api/scan'){
      const target=parsedUrl.searchParams.get('target')||'localhost';
      try{const data=await runScan(target);const hid=saveHistory(data);data._historyId=hid;jsonRes(res,200,data);}
      catch(e){jsonRes(res,500,{error:e.message});} return;
    }
    if(pathname==='/api/scan/remote'&&req.method==='POST'){
      try{const body=JSON.parse(await readBody(req));const data=await runScan(body.target,body.username,body.password);const hid=saveHistory(data);data._historyId=hid;jsonRes(res,200,data);}
      catch(e){jsonRes(res,500,{error:e.message});} return;
    }
    if(pathname==='/api/history'&&req.method==='GET'){
      ensureHistoryDir();
      try{const f=path.join(HISTORY_DIR,'index.json');jsonRes(res,200,fs.existsSync(f)?JSON.parse(fs.readFileSync(f,'utf8')):[]);}
      catch{jsonRes(res,200,[]);} return;
    }
    const hm=pathname.match(/^\/api\/history\/(.+)$/);
    if(hm&&req.method==='GET'){
      const f=path.join(HISTORY_DIR,`${hm[1]}.json`);
      if(fs.existsSync(f)){try{jsonRes(res,200,JSON.parse(fs.readFileSync(f,'utf8')))}catch{jsonRes(res,500,{error:'Read fail'})}}
      else jsonRes(res,404,{error:'Not found'}); return;
    }
    if(hm&&req.method==='DELETE'){
      try{const f=path.join(HISTORY_DIR,`${hm[1]}.json`);if(fs.existsSync(f))fs.unlinkSync(f);
      const idx=path.join(HISTORY_DIR,'index.json');let ix=[];try{ix=JSON.parse(fs.readFileSync(idx,'utf8'))}catch{}
      ix=ix.filter(i=>i.id!==hm[1]);fs.writeFileSync(idx,JSON.stringify(ix,null,2),'utf8');jsonRes(res,200,{success:true});}
      catch(e){jsonRes(res,500,{error:e.message});} return;
    }
    if(pathname==='/api/export'&&req.method==='POST'){
      try{const data=JSON.parse(await readBody(req));const dp=process.env.USERPROFILE?path.join(process.env.USERPROFILE,'Documents'):__dirname;
      const ep=path.join(dp,`license-report-${new Date().toISOString().slice(0,10)}.json`);
      fs.writeFileSync(ep,JSON.stringify(data,null,2),'utf8');jsonRes(res,200,{success:true,path:ep});}
      catch(e){jsonRes(res,500,{error:e.message});} return;
    }
    let filePath=pathname==='/'?'/index.html':pathname;
    filePath=path.join(__dirname,'public',filePath); serveStatic(res,filePath);
  });

  server.listen(port,'0.0.0.0',()=>{console.log(`[SERVER] Running on http://0.0.0.0:${port}`)});
  return server;
}

if(require.main===module){
  startServer(3847);
  console.log(`\n  License Checker v2.0 - http://0.0.0.0:3847\n`);
}

module.exports = { startServer };
