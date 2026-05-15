// === License Checker v2.0 ===
let scanData = null, filteredApps = [], currentFilter = 'all', currentView = 'scan';
const $ = id => document.getElementById(id);

// --- DOM refs ---
const btnScan=$('btnScan'),btnExport=$('btnExport'),welcomeState=$('welcomeState'),loadingState=$('loadingState'),
resultsState=$('resultsState'),searchInput=$('searchInput'),sortSelect=$('sortSelect'),appList=$('appList'),
appCount=$('appCount'),modalOverlay=$('modalOverlay'),modalClose=$('modalClose'),targetInput=$('targetInput'),
remoteCreds=$('remoteCreds'),navScan=$('navScan'),navHistory=$('navHistory'),navAgents=$('navAgents');

let agentPollInterval = null;

// --- Events ---
document.querySelectorAll('.filter-tab').forEach(t=>t.addEventListener('click',()=>{
  document.querySelectorAll('.filter-tab').forEach(x=>x.classList.remove('active'));
  t.classList.add('active'); currentFilter=t.dataset.filter; renderApps();
}));
searchInput.addEventListener('input',()=>renderApps());
sortSelect.addEventListener('change',()=>renderApps());
btnScan.addEventListener('click',startScan);
btnExport.addEventListener('click',exportReport);
modalClose.addEventListener('click',closeModal);
modalOverlay.addEventListener('click',e=>{if(e.target===modalOverlay)closeModal()});
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeModal()});

// Show credentials for remote
targetInput.addEventListener('input',()=>{
  const v=targetInput.value.trim();
  remoteCreds.classList.toggle('hidden',!v||v==='localhost'||v==='127.0.0.1');
});

// Nav tabs
navScan.addEventListener('click',()=>switchView('scan'));
navAgents.addEventListener('click',()=>{switchView('agents'); startAgentPolling();});
navHistory.addEventListener('click',()=>{switchView('history');loadHistory()});

function switchView(v){
  currentView=v;
  document.querySelectorAll('.nav-tab').forEach(t=>t.classList.toggle('active',t.dataset.view===v));
  $('scanView').classList.toggle('hidden',v!=='scan');
  $('agentsView').classList.toggle('hidden',v!=='agents');
  $('historyView').classList.toggle('hidden',v!=='history');
  
  if (v !== 'agents' && agentPollInterval) {
    clearInterval(agentPollInterval);
    agentPollInterval = null;
  }
}

// --- Agents Polling ---
async function fetchAgents() {
  if (currentView !== 'agents') return;
  try {
    const res = await fetch('/api/agents');
    const agents = await res.json();
    renderAgents(agents);
  } catch (e) {
    console.error('Failed to fetch agents:', e);
  }
}

function startAgentPolling() {
  fetchAgents();
  if (!agentPollInterval) {
    agentPollInterval = setInterval(fetchAgents, 2000);
  }
}

function renderAgents(agents) {
  const el = $('agentsList'), empty = $('agentsEmpty');
  if (!agents || !agents.length) {
    empty.classList.remove('hidden');
    Array.from(el.children).forEach(c => { if (c !== empty) c.remove(); });
    return;
  }
  empty.classList.add('hidden');
  
  let html = '';
  agents.forEach(a => {
    const isOnline = a.isOnline !== false;
    const isScanning = a.status === 'scanning';
    const statusColor = isOnline ? (isScanning ? 'var(--orange)' : 'var(--green)') : 'var(--text3)';
    const statusBg = isOnline ? (isScanning ? 'var(--orange-bg)' : 'var(--green-bg)') : 'rgba(255,255,255,0.05)';
    const statusText = isOnline ? (isScanning ? 'Đang quét...' : 'Sẵn sàng') : 'Offline';
    const btnHtml = isOnline && !isScanning ? 
      `<button class="btn btn-primary" onclick="commandAgentScan('${a.id}', this)" style="padding:6px 12px;font-size:0.8rem">Bắt đầu quét</button>` :
      (isScanning ? `<button class="btn btn-outline" disabled style="padding:6px 12px;font-size:0.8rem">Đang quét...</button>` : '');

    html += `<div class="history-item" style="grid-template-columns: 1fr 150px 120px 120px; cursor: default">
      <div class="hi-computer" style="display:flex;align-items:center;gap:8px">
        <span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${statusColor}"></span>
        ${esc(a.name)}
        <small>${esc(a.os)}</small>
      </div>
      <div class="hi-time">${esc(a.ip)}</div>
      <div class="hi-risk"><span class="crack-risk-badge" style="background:${statusBg};color:${statusColor};border:1px solid ${statusColor};font-size:.65rem">${statusText}</span></div>
      <div class="hi-delete">${btnHtml}</div>
    </div>`;
  });
  
  // Only update DOM if changed to avoid flicker (simple check by length and scanning state, ideally deep check)
  const currentHtml = Array.from(el.children).filter(c => c !== empty).map(c => c.outerHTML).join('');
  // Use innerHTML update for simplicity here, but wrapped in a container
  const tempDiv = document.createElement('div');
  tempDiv.innerHTML = html;
  
  // Re-append empty just in case
  el.innerHTML = '';
  el.appendChild(empty);
  tempDiv.childNodes.forEach(node => el.appendChild(node.cloneNode(true)));
}

async function commandAgentScan(id, btn) {
  btn.disabled = true;
  btn.textContent = 'Đang gửi lệnh...';
  try {
    const res = await fetch(`/api/scan/command/${id}`, { method: 'POST' });
    const result = await res.json();
    if (result.success) {
      showToast('Đã gửi lệnh quét đến thiết bị!', 'success');
      // Tự động chuyển qua tab history sau 5s để xem kết quả, hoặc chờ user tự check
      setTimeout(() => { if(currentView === 'agents') showToast('Khi quét xong, kết quả sẽ xuất hiện trong tab Lịch sử.', 'success'); }, 3000);
    } else {
      throw new Error(result.error);
    }
  } catch (err) {
    showToast('Lỗi gửi lệnh: ' + err.message, 'error');
    btn.disabled = false;
    btn.textContent = 'Bắt đầu quét';
  }
}


// --- Scan ---
async function startScan(){
  const target=targetInput.value.trim()||'localhost';
  welcomeState.classList.add('hidden'); resultsState.classList.add('hidden');
  loadingState.classList.remove('hidden'); btnScan.disabled=true;
  $('loadingTitle').textContent=target==='localhost'?'Đang quét máy local...':'Đang quét '+target+'...';
  $('loadingSubtitle').textContent='Truy quét registry, product keys, chữ ký số...';
  // Reset progress animation
  const pf=document.querySelector('.progress-fill');
  pf.style.animation='none'; pf.offsetHeight; pf.style.animation='progress 30s ease-in-out forwards';

  try{
    let res;
    if(target==='localhost'||target==='127.0.0.1'){
      res=await fetch('/api/scan');
    } else {
      const body={target};
      const u=$('remoteUser')?.value; const p=$('remotePass')?.value;
      if(u)body.username=u; if(p)body.password=p;
      res=await fetch('/api/scan/remote',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    }
    if(!res.ok) throw new Error('Scan failed');
    scanData=await res.json();
    if(scanData.error) throw new Error(scanData.error);
    showResults();
    const w=(scanData.crackWarnings||[]).length;
    showToast(w>0?`Quét hoàn tất! ${scanData.totalApps} ứng dụng, ⚠️ ${w} cảnh báo!`:`Quét hoàn tất! ${scanData.totalApps} ứng dụng ✅`,'success');
  }catch(err){
    showToast('Lỗi: '+err.message,'error');
    welcomeState.classList.remove('hidden'); loadingState.classList.add('hidden');
  }finally{
    btnScan.disabled=false;
  }
}

function showResults(){
  loadingState.classList.add('hidden'); resultsState.classList.remove('hidden'); btnExport.disabled=false;
  const apps=scanData.apps||[], free=apps.filter(a=>a.LicenseType==='Free/Open Source').length,
    commercial=apps.filter(a=>a.LicenseType==='Commercial').length,
    crackWarnings=scanData.crackWarnings||[],
    keysFound=(scanData.softwareKeys||[]).filter(k=>k.keyStatus&&k.keyStatus!=='NotFound').length +
      apps.filter(a=>a.KeyStatus&&a.KeyStatus!=='NotFound').length;

  animateCounter('statTotal',apps.length);
  animateCounter('statFree',free);
  animateCounter('statCommercial',commercial);
  animateCounter('statKeys',keysFound);
  animateCounter('statCrack',crackWarnings.length);

  if(crackWarnings.length>0) $('statCrackCard').classList.add('has-warnings');
  $('systemInfo').innerHTML=`${scanData.computerName||''} &bull; ${scanData.osVersion||''}`;

  updateCrackPanel(); updateKeysPanel(); updateWindowsLicense(); updateOfficeLicense(); renderApps();
}

// --- Keys Panel ---
function updateKeysPanel(){
  const panel=$('keysPanel'), body=$('keysBody'), countEl=$('keysCount');
  const skeys=scanData.softwareKeys||[];
  const appKeys=(scanData.apps||[]).filter(a=>a.KeyStatus&&a.KeyStatus!=='NotFound');
  const allKeys=[...skeys.filter(k=>k.keyStatus&&k.keyStatus!=='NotFound')];
  // Merge app-level keys
  appKeys.forEach(a=>{
    if(!allKeys.find(k=>k.app===a.Name)){
      allKeys.push({app:a.Name,keys:[{Name:'Key',Value:a.ProductKey||''}],keySource:a.KeySource||'',keyStatus:a.KeyStatus||'Found',keyDetails:a.KeyDetails||''});
    }
  });
  if(allKeys.length===0){panel.classList.add('hidden');return;}
  panel.classList.remove('hidden'); countEl.textContent=allKeys.length;
  let html='';
  allKeys.forEach(k=>{
    const sc=k.keyStatus==='Crack'?'ks-crack':k.keyStatus==='Evaluation'?'ks-eval':k.keyStatus==='Found'||k.keyStatus==='Licensed'?'ks-found':'ks-notfound';
    const keyStr=k.keys&&k.keys.length>0?k.keys.map(x=>`${x.Value||''}`).filter(Boolean).join(', '):(k.keyDetails||'N/A');
    html+=`<div class="key-item">
      <div class="key-app">${esc(k.app)}</div>
      <div class="key-value">${esc(keyStr.substring(0,80))}${keyStr.length>80?'...':''}</div>
      <span class="key-status ${sc}">${k.keyStatus}</span>
    </div>`;
  });
  body.innerHTML=html;
}

// --- Crack Panel ---
function updateCrackPanel(){
  const warnings=scanData.crackWarnings||[], panel=$('crackAlertPanel'), body=$('crackAlertBody'), badge=$('crackRiskBadge'), risk=scanData.riskSummary||{};
  if(warnings.length===0){
    panel.classList.remove('hidden');
    panel.style.borderColor='rgba(34,197,94,.3)';
    panel.querySelector('.crack-alert-header').style.background='rgba(34,197,94,.06)';
    panel.querySelector('.crack-alert-title svg').style.color='#22c55e';
    panel.querySelector('.crack-alert-title h3').textContent='✅ Hệ thống sạch - Không phát hiện crack';
    badge.textContent='CLEAN'; badge.className='crack-risk-badge risk-clean';
    body.innerHTML='<div style="text-align:center;padding:12px;color:var(--text2);font-size:.88rem">Không phát hiện crack tools, file hosts sạch, keys hợp lệ.</div>';
    return;
  }
  panel.classList.remove('hidden'); panel.style.borderColor='';
  panel.querySelector('.crack-alert-header').style.background='';
  panel.querySelector('.crack-alert-title svg').style.color='';
  panel.querySelector('.crack-alert-title h3').textContent='🏴‍☠️ Phát hiện dấu hiệu Crack / Vi phạm bản quyền';
  const rl=risk.riskLevel||'Unknown';
  badge.textContent=rl.toUpperCase(); badge.className=`crack-risk-badge risk-${rl.toLowerCase()}`;
  const typeLabels={CrackTool:'🛠️ Crack Tool',KMSActivation:'🔑 KMS',KMSNoDomain:'🏢 KMS Domain',HostsBlock:'📄 Hosts',ScheduledTask:'⏰ Task',SuspiciousProcess:'⚙️ Process',CrackFile:'📁 File',OfficeKMS:'📎 Office KMS',CrossCheck:'🔍 Cross-check',GVLKDetected:'🔐 GVLK',GracePeriodAnomaly:'⏱️ Grace',NonGenuine:'❌ Non-Genuine',DigitalSignature:'🔏 Signature',RegistryTamper:'🗝️ Registry',DefenderDisabled:'🛡️ Defender',ModifiedExe:'⚠️ Modified',C2RVolume:'📦 C2R',ProductVolume:'📦 Volume',CrackedKey:'🔑 Cracked Key'};
  let html='';
  warnings.forEach(w=>{
    const sc=w.Severity==='Critical'?'sev-critical':w.Severity==='High'?'sev-high':'sev-medium';
    html+=`<div class="crack-warning-item"><span class="cw-severity ${sc}">${w.Severity}</span><div class="cw-content"><div class="cw-type">${typeLabels[w.Type]||w.Type}</div><div class="cw-app">${esc(w.App)}</div><div class="cw-detail">${esc(w.Detail)}</div></div></div>`;
  });
  html+=`<div style="margin-top:12px;padding:10px 16px;background:var(--bg);border-radius:6px;border:1px solid var(--border);font-size:.82rem;color:var(--text2)"><strong>Tổng kết:</strong> ${risk.critical||0} Critical, ${risk.high||0} High, ${risk.medium||0} Medium</div>`;
  body.innerHTML=html;
}

// --- Windows License ---
function updateWindowsLicense(){
  const wl=scanData.windowsLicense||{};
  $('windowsProductName').textContent=wl.productName||scanData.osVersion||'Windows';
  const status=wl.licenseStatus||'Unknown';
  const bc=status==='Licensed'?'badge-licensed':status==='Unlicensed'?'badge-unlicensed':'badge-unknown';
  const st=status==='Licensed'?'✓ Đã kích hoạt':status==='Unlicensed'?'✗ Chưa kích hoạt':'? Chưa xác định';
  $('windowsLicenseStatus').innerHTML=`<span class="badge ${bc}">${st}</span>`;
  const isG=wl.isGenuine!==false, verdict=wl.verdict||'';
  let vh='';
  if(verdict){
    const vc=isG?'background:rgba(34,197,94,.08);border:1px solid rgba(34,197,94,.25);color:#22c55e':'background:rgba(239,68,68,.08);border:1px solid rgba(239,68,68,.25);color:#ef4444';
    vh=`<div style="padding:12px 18px;border-radius:10px;font-size:.9rem;font-weight:600;margin-bottom:14px;display:flex;align-items:center;gap:8px;${vc}"><span style="font-size:1.2rem">${isG?'✓':'✗'}</span> ${esc(verdict)}</div>`;
  }
  const rf=wl.redFlags||[];
  let rfh='';
  if(rf.length>0){rfh='<div style="margin:12px 0;padding:14px 18px;background:var(--bg);border-radius:8px;border:1px solid rgba(239,68,68,.15)"><div style="font-size:.78rem;color:#ef4444;text-transform:uppercase;letter-spacing:.5px;font-weight:600;margin-bottom:8px">Chi tiết:</div>';rf.forEach(r=>{rfh+=`<div style="font-size:.84rem;padding:4px 0;border-bottom:1px solid rgba(255,255,255,.03)">● ${esc(r)}</div>`});rfh+='</div>';}
  let dh='';
  if(wl.partialKey)dh+=`<div class="wl-detail-item"><label>Key (cuối)</label><span>XXXXX-${wl.partialKey}</span></div>`;
  if(wl.activationType){const c=wl.activationType==='KMS/Volume'?'#f59e0b':wl.activationType==='OEM'?'#22c55e':'#3b82f6';dh+=`<div class="wl-detail-item"><label>Kiểu kích hoạt</label><span style="color:${c};font-weight:600">${wl.activationType}</span></div>`;}
  if(wl.kmsServer)dh+=`<div class="wl-detail-item"><label>KMS Server</label><span style="color:#ef4444;font-weight:700">${wl.kmsServer}:${wl.kmsPort||1688}</span></div>`;
  $('windowsLicenseDetails').innerHTML=vh+'<div class="wl-details" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px">'+dh+'</div>'+rfh;
}

// --- Office License ---
function updateOfficeLicense(){
  const prods=scanData.officeLicense?.products||[], card=$('officeLicenseCard');
  if(!prods.length){card.classList.add('hidden');return;}
  card.classList.remove('hidden');
  $('officeProductCount').textContent=`${prods.length} sản phẩm`;
  const hasCrack=prods.some(p=>(p.redFlags||[]).length>0||p.gvlkMatch);
  const allLic=prods.every(p=>p.status==='Licensed');
  $('officeLicenseStatus').innerHTML=hasCrack?'<span class="badge badge-crack">⚠️ Nghi vấn</span>':allLic?'<span class="badge badge-licensed">✓ OK</span>':'<span class="badge badge-unknown">Kiểm tra</span>';
  let html='';
  prods.forEach(p=>{
    const sc=p.status==='Licensed'?'var(--green)':'var(--red)';
    const hrf=(p.redFlags||[]).length>0;
    const gvlk=p.gvlkMatch?'<span style="color:#ef4444;font-weight:700;font-size:.72rem;background:rgba(239,68,68,.15);padding:3px 10px;border-radius:12px;margin-left:8px">🔐 GVLK</span>':'';
    html+=`<div style="padding:14px 18px;margin-bottom:10px;background:var(--bg);border-radius:10px;border:1px solid ${hrf?'rgba(239,68,68,.25)':'var(--border)'}">`;
    html+=`<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px"><div style="display:flex;align-items:center;gap:8px"><span style="font-weight:600">${esc(p.name)}</span>${gvlk}</div><span style="padding:3px 10px;border-radius:12px;font-size:.72rem;font-weight:600;background:${p.status==='Licensed'?'var(--green-bg)':'var(--red-bg)'};color:${sc}">${p.status}</span></div>`;
    html+=`<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:8px;font-size:.82rem"><div><span style="color:var(--text3)">Key: </span><span style="font-family:monospace">XXXXX-${p.partialKey||'N/A'}</span></div><div><span style="color:var(--text3)">Kênh: </span><span style="font-weight:600">${p.activationType||'?'}</span></div></div>`;
    if(hrf){html+='<div style="margin-top:10px;padding:10px 14px;background:rgba(239,68,68,.04);border-radius:8px;border:1px solid rgba(239,68,68,.12)">';(p.redFlags||[]).forEach(r=>{html+=`<div style="font-size:.78rem;color:#ef4444;padding:3px 0">⚠️ ${esc(r)}</div>`});html+='</div>';}
    html+='</div>';
  });
  $('officeLicenseDetails').innerHTML=html;
}

// --- App List ---
function getFilteredApps(){
  let apps=scanData.apps||[]; const q=searchInput.value.toLowerCase().trim();
  if(q) apps=apps.filter(a=>a.Name.toLowerCase().includes(q)||(a.Publisher&&a.Publisher.toLowerCase().includes(q)));
  if(currentFilter==='free') apps=apps.filter(a=>a.LicenseType==='Free/Open Source');
  else if(currentFilter==='commercial') apps=apps.filter(a=>a.LicenseType==='Commercial');
  else if(currentFilter==='haskey') apps=apps.filter(a=>a.KeyStatus&&a.KeyStatus!=='NotFound');
  else if(currentFilter==='crack') apps=apps.filter(a=>a.CrackRisk!=='None'&&a.CrackRisk);
  else if(currentFilter==='unknown') apps=apps.filter(a=>a.LicenseType==='Unclassified');
  const s=sortSelect.value;
  apps.sort((a,b)=>{if(s==='name-asc')return a.Name.localeCompare(b.Name);if(s==='name-desc')return b.Name.localeCompare(a.Name);if(s==='size-desc')return(b.SizeMB||0)-(a.SizeMB||0);if(s==='publisher')return(a.Publisher||'').localeCompare(b.Publisher||'');return 0});
  return apps;
}

function renderApps(){
  filteredApps=getFilteredApps(); let html='';
  filteredApps.forEach((app,i)=>{
    const isCrack=app.LicenseType==='Crack Tool'||(app.CrackRisk&&app.CrackRisk!=='None');
    const hasKey=app.KeyStatus&&app.KeyStatus!=='NotFound';
    let bc,bt;
    if(isCrack){bc='badge-crack';bt=app.LicenseType==='Crack Tool'?'🏴‍☠️ CRACK':'⚠️ Nghi vấn';}
    else if(app.LicenseType==='Free/Open Source'){bc='badge-free';bt='Miễn phí';}
    else if(app.LicenseType==='Commercial'){bc='badge-commercial';bt='Thương mại';}
    else if(app.LicenseType==='Trial/Demo'){bc='badge-trial';bt='Dùng thử';}
    else{bc='badge-unknown';bt='Chưa rõ';}
    const sz=app.SizeMB?(app.SizeMB>=1024?(app.SizeMB/1024).toFixed(1)+' GB':app.SizeMB.toFixed(0)+' MB'):'-';
    const rc=isCrack?'app-row crack-risk':hasKey?'app-row has-key':'app-row';
    const keyBadge=hasKey?`<span class="badge badge-key">🔑 ${app.KeyStatus}</span>`:'';
    html+=`<div class="${rc}" onclick="showDetail(${i})">
      <div class="app-name" title="${esc(app.Name)}">${esc(app.Name)} ${keyBadge}</div>
      <div class="app-publisher" title="${esc(app.Publisher)}">${esc(app.Publisher)}</div>
      <div class="app-version">${esc(app.Version)}</div>
      <div class="app-size">${sz}</div>
      <div><span class="badge ${bc}">${bt}</span></div>
      <button class="app-detail-btn" title="Chi tiết">›</button>
    </div>`;
  });
  if(!filteredApps.length) html='<div style="text-align:center;padding:48px;color:var(--text3)">Không tìm thấy.</div>';
  appList.innerHTML=html;
  appCount.textContent=`Hiển thị ${filteredApps.length} / ${(scanData.apps||[]).length} ứng dụng`;
}

function showDetail(i){
  const app=filteredApps[i]; if(!app) return;
  $('modalTitle').textContent=app.Name;
  const fields=[['Nhà phát hành',app.Publisher],['Phiên bản',app.Version],['Ngày cài đặt',app.InstallDate||'N/A'],['Vị trí',app.InstallLocation||'N/A'],['Dung lượng',app.SizeMB?app.SizeMB.toFixed(1)+' MB':'N/A'],['Loại bản quyền',app.LicenseType],['Trạng thái',app.LicenseStatus],['Product Key',app.ProductKey||'Không tìm thấy'],['Nguồn Key',app.KeySource||'N/A'],['Trạng thái Key',app.KeyStatus||'N/A'],['Chi tiết Key',app.KeyDetails||''],['Rủi ro Crack',app.CrackRisk||'None'],['Chi tiết Crack',app.CrackDetails||'Không phát hiện'],['Chữ ký số',app.SignatureStatus||'N/A']];
  let html='';
  fields.forEach(([l,v])=>{
    if(!v&&v!==0)return;
    const warn=(l.includes('Crack')||l.includes('Key')||l.includes('Chữ ký'))&&v&&v!=='None'&&v!=='N/A'&&v!=='Valid'&&v!=='Không phát hiện'&&v!=='Không tìm thấy'&&v!=='NotFound';
    const s=warn?'border-color:rgba(239,68,68,.3);background:rgba(239,68,68,.03)':'';
    html+=`<div class="modal-field"><label>${l}</label><div class="value" style="${s}">${esc(v||'N/A')}</div></div>`;
  });
  $('modalBody').innerHTML=html;
  modalOverlay.classList.remove('hidden');
}
function closeModal(){modalOverlay.classList.add('hidden')}

// --- History ---
async function loadHistory(){
  try{
    const res=await fetch('/api/history');
    const list=await res.json();
    const el=$('historyList');
    let empty=$('historyEmpty');
    if (!empty) {
      empty = document.createElement('div');
      empty.className = 'history-empty';
      empty.id = 'historyEmpty';
      empty.textContent = 'Chưa có lịch sử quét nào.';
    }
    
    if(!list.length){
      empty.classList.remove('hidden');
      el.innerHTML='';
      el.appendChild(empty);
      return;
    }
    
    let html='';
    list.forEach(h=>{
      const wc=h.warnings>0?`<span style="color:var(--red)">${h.warnings}</span>`:'<span style="color:var(--green)">0</span>';
      const rc=h.riskLevel==='Critical'?'risk-critical':h.riskLevel==='High'?'risk-high':h.riskLevel==='Medium'?'risk-medium':'risk-clean';
      html+=`<div class="history-item" onclick="loadHistoryItem('${h.id}')">
        <div class="hi-computer">${esc(h.computerName)}<small>${esc(h.userName||'')}</small></div>
        <div class="hi-time">${esc(h.timestamp)}</div>
        <div class="hi-apps">${h.totalApps} apps</div>
        <div class="hi-warnings">${wc}</div>
        <div class="hi-risk"><span class="crack-risk-badge ${rc}" style="font-size:.65rem;padding:2px 8px">${h.riskLevel}</span></div>
        <div class="hi-delete"><button onclick="event.stopPropagation();deleteHistory('${h.id}',this)" title="Xóa">🗑</button></div>
      </div>`;
    });
    
    empty.classList.add('hidden');
    el.innerHTML=html;
    el.appendChild(empty);
  }catch(e){showToast('Lỗi tải lịch sử: '+e.message,'error')}
}

async function loadHistoryItem(id){
  try{
    const res=await fetch('/api/history/'+id);
    scanData=await res.json();
    switchView('scan');
    welcomeState.classList.add('hidden');
    showResults();
    showToast('Đã tải kết quả quét: '+scanData.computerName,'success');
  }catch(e){showToast('Lỗi: '+e.message,'error')}
}

async function deleteHistory(id,btn){
  try{await fetch('/api/history/'+id,{method:'DELETE'});btn.closest('.history-item').remove();showToast('Đã xóa','success')}catch(e){showToast('Lỗi: '+e.message,'error')}
}

// --- Export ---
async function exportReport(){
  if(!scanData)return;
  try{
    const res=await fetch('/api/export',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(scanData)});
    const r=await res.json();
    if(r.success) showToast('Đã xuất: '+r.path,'success'); else throw new Error(r.error);
  }catch(e){showToast('Lỗi xuất: '+e.message,'error')}
}

// --- Utils ---
function showToast(msg,type='success'){
  const c=$('toastContainer'),t=document.createElement('div');
  t.className=`toast toast-${type}`;t.textContent=msg;c.appendChild(t);
  setTimeout(()=>{t.style.opacity='0';setTimeout(()=>t.remove(),300)},5000);
}
function animateCounter(id,target){
  const el=$(id);let cur=0;const step=Math.max(1,Math.floor(target/30));
  const iv=setInterval(()=>{cur+=step;if(cur>=target){cur=target;clearInterval(iv)}el.textContent=cur},30);
}
function esc(s){if(!s)return'';const d=document.createElement('div');d.textContent=s;return d.innerHTML}
