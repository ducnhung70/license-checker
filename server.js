const http = require('http');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const PORT = 3847;
const HISTORY_DIR = path.join(__dirname, 'scan-history');

// Agent Management State
// agents[id] = { id, name, os, ip, lastSeen, status, pendingCommand, lastResultId }
const activeAgents = new Map();

// Ensure history directory
if (!fs.existsSync(HISTORY_DIR)) fs.mkdirSync(HISTORY_DIR, { recursive: true });

function serveStatic(res, filePath) {
  const ext = path.extname(filePath);
  const mimeTypes = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon'
  };
  const contentType = mimeTypes[ext] || 'text/plain';
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
}

function jsonRes(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => resolve(body));
  });
}

function saveHistory(data) {
  const id = `${Date.now()}-${(data.computerName || 'unknown').replace(/[^a-zA-Z0-9]/g, '')}`;
  const meta = {
    id,
    computerName: data.computerName || 'Unknown',
    userName: data.userName || '',
    osVersion: data.osVersion || '',
    timestamp: data.timestamp || new Date().toISOString(),
    totalApps: data.totalApps || 0,
    warnings: (data.crackWarnings || []).length,
    riskLevel: (data.riskSummary || {}).riskLevel || 'Clean'
  };
  fs.writeFileSync(path.join(HISTORY_DIR, `${id}.json`), JSON.stringify(data, null, 2), 'utf8');
  // Update index
  const indexFile = path.join(HISTORY_DIR, 'index.json');
  let index = [];
  try { index = JSON.parse(fs.readFileSync(indexFile, 'utf8')); } catch {}
  index.unshift(meta);
  if (index.length > 100) index = index.slice(0, 100);
  fs.writeFileSync(indexFile, JSON.stringify(index, null, 2), 'utf8');
  return id;
}

function runScan(target, username, password) {
  return new Promise((resolve, reject) => {
    let cmd;
    const scriptPath = path.join(__dirname, 'scan-remote.ps1');
    if (!target || target === 'localhost' || target === '127.0.0.1') {
      cmd = `powershell -NoProfile -ExecutionPolicy Bypass -File "${path.join(__dirname, 'scan.ps1')}"`;
    } else {
      const args = [`-TargetComputer "${target}"`];
      if (username) args.push(`-Username "${username}"`);
      if (password) args.push(`-Password "${password}"`);
      cmd = `powershell -NoProfile -ExecutionPolicy Bypass -File "${scriptPath}" ${args.join(' ')}`;
    }
    console.log(`[SCAN] Target: ${target || 'localhost'}`);
    exec(cmd, { maxBuffer: 50 * 1024 * 1024, encoding: 'utf8', timeout: 300000 }, (error, stdout, stderr) => {
      if (error) return reject(new Error(error.message));
      try {
        const jsonStart = stdout.indexOf('{');
        if (jsonStart === -1) return reject(new Error('No JSON output'));
        const data = JSON.parse(stdout.substring(jsonStart));
        resolve(data);
      } catch (e) {
        reject(new Error('Parse error: ' + e.message));
      }
    });
  });
}

// Cleanup inactive agents every 10 seconds (inactive > 15s means offline)
setInterval(() => {
  const now = Date.now();
  for (const [id, agent] of activeAgents.entries()) {
    if (now - agent.lastSeen > 15000) {
      activeAgents.delete(id);
    }
  }
}, 10000);

const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = parsedUrl.pathname;

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // === AGENT PING (Heartbeat & Command Polling) ===
  if (pathname === '/api/agents/ping') {
    const id = parsedUrl.searchParams.get('id');
    const name = parsedUrl.searchParams.get('name') || id;
    const os = parsedUrl.searchParams.get('os') || '';
    const ip = req.socket.remoteAddress;

    if (!id) { jsonRes(res, 400, { error: 'Agent ID required' }); return; }

    let agent = activeAgents.get(id);
    if (!agent) {
      agent = { id, name, os, ip, status: 'idle', pendingCommand: null, lastResultId: null };
    }
    agent.lastSeen = Date.now();
    
    let command = agent.pendingCommand;
    if (command) {
      agent.status = 'scanning';
      agent.pendingCommand = null;
    }
    
    activeAgents.set(id, agent);
    jsonRes(res, 200, { success: true, command: command });
    return;
  }

  // === LIST ACTIVE AGENTS ===
  if (pathname === '/api/agents' && req.method === 'GET') {
    const list = Array.from(activeAgents.values()).map(a => ({
      ...a,
      isOnline: (Date.now() - a.lastSeen) < 15000
    }));
    jsonRes(res, 200, list);
    return;
  }

  // === COMMAND AGENT TO SCAN ===
  const agentCommandMatch = pathname.match(/^\/api\/scan\/command\/(.+)$/);
  if (agentCommandMatch && req.method === 'POST') {
    const id = agentCommandMatch[1];
    const agent = activeAgents.get(id);
    if (!agent) { jsonRes(res, 404, { error: 'Agent not found or offline' }); return; }
    
    agent.pendingCommand = 'SCAN';
    agent.status = 'scanning';
    jsonRes(res, 200, { success: true, message: 'Scan command sent' });
    return;
  }

  // === UPLOAD SCAN RESULTS (From Agent) ===
  if (pathname === '/api/scan/upload' && req.method === 'POST') {
    const id = parsedUrl.searchParams.get('id');
    try {
      const data = JSON.parse(await readBody(req));
      const historyId = saveHistory(data);
      
      if (id && activeAgents.has(id)) {
        const agent = activeAgents.get(id);
        agent.status = 'idle';
        agent.lastResultId = historyId;
      }
      
      console.log(`[AGENT UPLOAD] Received scan from ${id || data.computerName}. Total apps: ${data.totalApps}`);
      jsonRes(res, 200, { success: true, historyId });
    } catch (err) {
      console.error('[UPLOAD ERROR]', err.message);
      if (id && activeAgents.has(id)) activeAgents.get(id).status = 'error';
      jsonRes(res, 500, { error: err.message });
    }
    return;
  }

  // === LOCAL SCAN ===
  if (pathname === '/api/scan') {
    const target = parsedUrl.searchParams.get('target') || 'localhost';
    try {
      const data = await runScan(target);
      const historyId = saveHistory(data);
      data._historyId = historyId;
      console.log(`[SCAN] Found ${data.totalApps} apps on ${target}`);
      jsonRes(res, 200, data);
    } catch (err) {
      console.error('[ERROR]', err.message);
      jsonRes(res, 500, { error: err.message });
    }
    return;
  }

  // === REMOTE SCAN (WinRM) ===
  if (pathname === '/api/scan/remote' && req.method === 'POST') {
    try {
      const body = JSON.parse(await readBody(req));
      const { target, username, password } = body;
      if (!target) { jsonRes(res, 400, { error: 'Target required' }); return; }
      const data = await runScan(target, username, password);
      const historyId = saveHistory(data);
      data._historyId = historyId;
      console.log(`[REMOTE] Found ${data.totalApps} apps on ${target}`);
      jsonRes(res, 200, data);
    } catch (err) {
      console.error('[REMOTE ERROR]', err.message);
      jsonRes(res, 500, { error: err.message });
    }
    return;
  }

  // === HISTORY LIST ===
  if (pathname === '/api/history' && req.method === 'GET') {
    try {
      const indexFile = path.join(HISTORY_DIR, 'index.json');
      const index = fs.existsSync(indexFile) ? JSON.parse(fs.readFileSync(indexFile, 'utf8')) : [];
      jsonRes(res, 200, index);
    } catch { jsonRes(res, 200, []); }
    return;
  }

  // === HISTORY DETAIL ===
  const historyMatch = pathname.match(/^\/api\/history\/(.+)$/);
  if (historyMatch && req.method === 'GET') {
    const id = historyMatch[1];
    const file = path.join(HISTORY_DIR, `${id}.json`);
    if (fs.existsSync(file)) {
      try { jsonRes(res, 200, JSON.parse(fs.readFileSync(file, 'utf8'))); }
      catch { jsonRes(res, 500, { error: 'Failed to read history' }); }
    } else { jsonRes(res, 404, { error: 'Not found' }); }
    return;
  }

  // === DELETE HISTORY ===
  if (historyMatch && req.method === 'DELETE') {
    const id = historyMatch[1];
    const file = path.join(HISTORY_DIR, `${id}.json`);
    try {
      if (fs.existsSync(file)) fs.unlinkSync(file);
      const indexFile = path.join(HISTORY_DIR, 'index.json');
      let index = [];
      try { index = JSON.parse(fs.readFileSync(indexFile, 'utf8')); } catch {}
      index = index.filter(i => i.id !== id);
      fs.writeFileSync(indexFile, JSON.stringify(index, null, 2), 'utf8');
      jsonRes(res, 200, { success: true });
    } catch (e) { jsonRes(res, 500, { error: e.message }); }
    return;
  }

  // === EXPORT ===
  if (pathname === '/api/export' && req.method === 'POST') {
    try {
      const data = JSON.parse(await readBody(req));
      const docsPath = process.env.USERPROFILE ? path.join(process.env.USERPROFILE, 'Documents') : __dirname;
      const exportPath = path.join(docsPath, `license-report-${new Date().toISOString().slice(0,10)}.json`);
      fs.writeFileSync(exportPath, JSON.stringify(data, null, 2), 'utf8');
      jsonRes(res, 200, { success: true, path: exportPath });
    } catch (e) { jsonRes(res, 500, { error: e.message }); }
    return;
  }

  // === STATIC FILES ===
  let filePath = pathname === '/' ? '/index.html' : pathname;
  filePath = path.join(__dirname, 'public', filePath);
  serveStatic(res, filePath);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`
  ╔══════════════════════════════════════════════════╗
  ║   License Checker v2.0                           ║
  ║   Server: http://0.0.0.0:${PORT}                    ║
  ║   Local:  http://localhost:${PORT}                   ║
  ║   Agent Management & Remote Scan enabled         ║
  ║   Press Ctrl+C to stop                           ║
  ╚══════════════════════════════════════════════════╝
  `);
});
