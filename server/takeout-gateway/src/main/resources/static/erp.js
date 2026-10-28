/* Store-scoped operating-supplies procurement. All facts and mutations come from ERP APIs. */
window.TakeoutErp = (() => {
  'use strict';
  const esc = v => String(v ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const labels = {DRAFT:'草稿',SUBMITTED:'待审核',CONFIRMED:'已确认',CLOSED:'已关闭',APPROVED:'已通过',REJECTED:'已拒绝',COUNT:'盘点',LOSS:'报损',RECEIPT:'收货',ADJUST:'调整',REVERSAL:'冲销'};
  Object.assign(labels,{suppliers:'新增供应商','supplier-update':'修改供应商','supplier-status':'供应商启停',materials:'建立物料',purchases:'创建采购',submit:'提交采购',confirm:'确认采购',close:'关闭采购',receive:'收货入库','reverse-receipt':'收货冲销',adjust:'提交调整',review:'审核调整',reverse:'调整冲销',pay:'登记付款','payment-correct':'凭证纠错','reverse-payment':'付款冲销','supplier-refund':'供应商退款'});
  const text = v => esc(labels[v] || v);
  const money = v => Number(v || 0).toFixed(2);
  const button = (label,action,id='',extra='') => `<button class="btn ${extra}" type="button" data-erp-action="${action}" data-id="${esc(id)}">${label}</button>`;
  const field = (label,name,example,type='text',extra='') => `<label class="field">${label}<input class="input" name="${name}" placeholder="${example}" type="${type}" required ${extra}></label>`;
  const select = (label,name,rows) => `<label class="field">${label}<select class="select" name="${name}" required><option value="">请选择</option>${rows.map(([id,label])=>`<option value="${esc(id)}">${esc(label)}</option>`).join('')}</select></label>`;
  const form = (action,title,body) => `<form class="page-panel section" data-erp-form="${action}"><h2 class="section-title">${title}</h2><div class="form-grid">${body}</div><p class="help-text" role="alert" data-erp-error></p><div class="form-actions"><button class="btn primary" type="submit">${({pay:'登记已完成的线下付款',purchases:'保存采购草稿',receive:'登记本次收货',adjust:'提交调整审核'})[action] || '保存资料'}</button></div></form>`;
  const table = (headers,rows) => `<div class="table-wrap"><table class="${headers.length<=3?'erp-compact':''}"><thead><tr>${headers.map(h=>`<th scope="col">${h}</th>`).join('')}</tr></thead><tbody>${rows.length?rows.map(row=>`<tr>${row.map(cell=>`<td class="${/^-?\d+(\.\d+)?$/.test(String(cell))?'erp-number':''}">${cell}</td>`).join('')}</tr>`).join(''):`<tr><td colspan="${headers.length}">暂无记录。完成上方操作后可在此查询。</td></tr>`}</tbody></table></div>`;
  async function mount({root,api,toast,live,stores,role,ownerId}) {
    if(!Number.isSafeInteger(ownerId) || ownerId<=0)throw new Error('请重新登录后操作采购库存');
    let store=Number(stores[0]?.id || 0),tab='purchases',detailVersion=0,rows=[],materials=[],suppliers=[],before=0,history=[];
    const pending=new Map(); let busy=false,version=0,supplierFilter=0;
    const storageKey=s=>'erp.pending.'+ownerId+'.'+s;
    function readPending(s) {
      let saved;try{saved=JSON.parse(window.sessionStorage.getItem(storageKey(s)) || '[]');}
      catch(e){throw new Error('本机待确认请求记录无法读取，请先核对采购记录后再操作');}
      if(!Array.isArray(saved) || !saved.every(r=>r && r.store===s && typeof r.key==='string' && /^[A-Za-z0-9_-]{16,128}$/.test(r.key)
        && typeof r.action==='string' && /^[a-z][a-z-]{1,40}$/.test(r.action) && r.payload && typeof r.payload==='object' && !Array.isArray(r.payload)))
        throw new Error('本机待确认请求记录格式异常，请先核对采购记录后再操作');
      return saved;
    }
    function savePending(request,remove=false) {
      const key=storageKey(request.store),saved=readPending(request.store).filter(r=>r.key!==request.key);
      if(!remove)saved.push(request);window.sessionStorage.setItem(key,JSON.stringify(saved));
    }
    function restorePending(s) {
      const saved=readPending(s);
      saved.forEach(r=>pending.set(JSON.stringify([r.store,r.action,r.payload]),r));
    }
    root.innerHTML=`<section data-erp><div class="page-head"><div><h1>采购与库存</h1><p class="help-text">餐盒与经营耗材 · 采购确认后分批收货，按收货金额登记应付。</p></div><label class="field">操作门店<select class="select" data-erp-store>${stores.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join('')}</select></label></div><p class="help-text">耗材按固定基础单位记账，不扣减菜品库存。盘点、报损须由另一位管理员或门店所有者审核。</p><nav class="toolbar" aria-label="采购库存功能">${[['purchases','采购与收货'],['suppliers','供应商'],['materials','物料库存'],['ledger','库存台账'],['adjustments','盘点与报损'],['payments','付款记录'],['payment-events','付款纠错与退款审计'],['finance','经营对账'],['audit','操作审计']].map(([id,label])=>button(label,'tab',id)).join('')}</nav><section data-erp-pending aria-live="polite"></section><div data-erp-body aria-live="polite"></div></section>`;
    const shell=root.querySelector('[data-erp]'),body=shell.querySelector('[data-erp-body]');
    if(role===2)shell.querySelector('nav').insertAdjacentHTML('beforeend',button('事件投递与补偿','tab','deliveries'));
    const active=()=>live() && shell.isConnected;
    const path=resource=>`/api/erp/stores/${store}/${resource}`;
    const call=async(resource,options)=>{if(!active())throw new Error('页面已切换，请重新进入');const requestStore=store,result=await api(path(resource),options);if(!active() || requestStore!==store)throw new Error('页面或门店已切换');return result;};
    const materialName=id=>materials.find(m=>Number(m.id)===Number(id))?.name || `物料 ${id}`;
    const ids=(label,name,records)=>'<div data-erp-picker="'+ (name==='supplierId'?'suppliers':'materials') +'"><label class="field">搜索'+label+'<input class="input" data-erp-search maxlength="100" placeholder="输入名称后点击搜索"></label>'+button('搜索','picker-search')+select(label,name,records.map(r=>[r.id,`${r.name} (${r.unit || r.contact || r.id})`]))+'<div class="form-actions">'+button('上一批','picker-previous')+button('下一批','picker-next')+'</div><p role="status" data-erp-picker-status></p></div>';
    function renderPending() {
      const target=shell.querySelector('[data-erp-pending]');
      target.innerHTML=[...pending.values()].filter(r=>r.store===store).map(r=>`<article class="page-panel"><h2>待核对的未确认请求</h2><p>门店 ${r.store} · ${text(r.action)} · 请求号 ${esc(r.key)}</p><pre>${esc(JSON.stringify(r.payload,null,2))}</pre>${button('核对并重试原请求','retry-pending',r.key)}</article>`).join('');
    }
    async function pickerPage(node,action) {
      const status=node.querySelector('[data-erp-picker-status]'),input=node.querySelector('[data-erp-search]'),selected=node.querySelector('select');
      const state=node.erpPage || {before:0,history:[],rows:null,query:''};
      const next={...state,history:[...state.history]};
      if(action==='picker-search'){next.query=input.value.trim();next.before=0;next.history=[];}
      if(action==='picker-next'){if(state.rows && state.rows.length<50)return;next.history.push(state.before);next.before=Number(state.rows?.at(-1)?.id || selected.options[selected.options.length-1]?.value || 0);}
      if(action==='picker-previous'){next.before=next.history.pop() || 0;}
      const current=(node.erpVersion || 0)+1;node.erpVersion=current;const view=version;
      status.textContent='正在搜索…';
      try {
        const resource=node.dataset.erpPicker;
        const results=await call(`${resource}?limit=50&before=${next.before}&q=${encodeURIComponent(next.query)}${resource==='suppliers'?'&enabled=true':''}`);
        if(!node.isConnected || current!==node.erpVersion || view!==version)return;
        const value=selected.value,label=selected.selectedOptions?.[0]?.textContent;
        selected.innerHTML='<option value="">请选择</option>'+results.map(r=>`<option value="${esc(r.id)}">${esc(r.name)} (${esc(r.unit || r.contact || r.id)})</option>`).join('');
        if(value && !results.some(r=>String(r.id)===value))selected.insertAdjacentHTML('beforeend',`<option value="${esc(value)}">${esc(label)}</option>`);
        selected.value=value;node.erpPage={...next,rows:results};
        status.textContent=`本批 ${results.length} 条，已选项保持；可继续搜索或翻页。`;
      }catch(e){if(node.isConnected && current===node.erpVersion)status.textContent=e.message;}
    }
    function renderList() {
      if(tab==='suppliers')body.innerHTML=form('suppliers','维护供应商',field('供应商名称','name','例如：安心餐盒厂','text','maxlength="100"')+field('联系人与联系方式','contact','例如：王经理，门店采购电话','text','maxlength="100"'))+table(['供应商','联系方式','状态','操作'],rows.map(r=>[esc(r.name),esc(r.contact),r.enabled?'启用':'停用',button(r.enabled?'停用':'启用','supplier-status',`${r.id}:${r.enabled?0:1}`)+button('关联采购','supplier-purchases',r.id)]));
      if(tab==='materials')body.innerHTML=form('materials','建立经营耗材',field('物料名称','name','例如：750ml餐盒','text','maxlength="100"')+field('基础单位（创建后固定）','unit','例如：只、包、卷','text','maxlength="16"'))+table(['物料','当前结存','基础单位'],rows.map(r=>[esc(r.name),esc(r.balance),esc(r.unit)]));
      if(tab==='purchases') {
        body.innerHTML=(supplierFilter?`<p>仅查看供应商 ${supplierFilter} 的采购 ${button('清除供应商筛选','clear-supplier')}</p>`:'')+form('purchases','创建采购单',ids('供应商','supplierId',suppliers.filter(s=>s.enabled))+`<div data-erp-lines class="erp-lines">${purchaseLine()}</div>`+button('增加采购物料','add-line'))+
          table(['单号 / 供应商','状态','订货金额','已收货应付','已付 / 未付','操作'],rows.map(p=>[`${p.id} / ${esc(suppliers.find(s=>s.id===p.supplier_id)?.name || p.supplier_id)}`,text(p.status),money(p.ordered_amount),money(p.payable),`${money(p.paid)} / ${money(Number(p.payable)-Number(p.paid))}`,
            button('明细与收货','detail',p.id)+(p.status==='DRAFT'?button('提交审核','submit',p.id):'')+(p.status==='SUBMITTED'?button('确认采购','confirm',p.id):'')+(p.status!=='CLOSED'?button('关闭未收部分','close',p.id):'')]))+`<section data-erp-detail></section>`;
      }
      if(tab==='ledger')body.innerHTML=`<h2 class="section-title">库存流水</h2><p class="help-text">按基础单位记账。已生效流水不可覆盖；收货按整张收货单冲销，调整按原流水冲销。</p>`+table(['流水 / 来源单据','物料','变动','变动前 → 后','操作人 / 时间','原因','纠正'],rows.map(l=>[`${l.id} / ${text(l.source_type)} ${l.source_id}${l.reversal_of?` / 原流水 ${l.reversal_of}`:''}`,`${esc(materialName(l.material_id))}（${esc(l.unit)}）`,esc(l.delta),`${esc(l.before_qty)} → ${esc(l.after_qty)}`,`${l.operator_id} / ${esc(l.created_at)}`,esc(l.reason),l.source_type==='ADJUST'?button('冲销调整','reverse',l.id):l.source_type==='RECEIPT'?button('冲销整张收货单','reverse-receipt',l.source_id):'—']));
      if(tab==='adjustments')body.innerHTML=form('adjust','提交盘点或报损',ids('物料','materialId',materials)+select('调整类型','kind',[['COUNT','盘点：填写实盘数'],['LOSS','报损：填写损耗数']])+field('数量（基础单位）','quantity','例如：实盘95或报损5','number','min="0" max="999999999" step="0.001"')+field('差异原因','reason','例如：运输破损5只','text','maxlength="255"'))+table(['单号 / 类型','物料','账面 / 实盘','原因','状态 / 制单人','审核'],rows.map(a=>[`${a.id} / ${text(a.kind)}`,esc(materialName(a.material_id)),`${esc(a.book_qty)} / ${esc(a.actual_qty)}`,esc(a.reason),`${text(a.status)} / ${a.operator_id}`,a.status==='SUBMITTED'?button('通过','approve',a.id)+button('拒绝','reject',a.id):`审核人 ${a.reviewer_id}`]));
      if(tab==='payments')body.innerHTML=`<h2 class="section-title">供应商付款记录</h2><p class="help-text">这里只登记实际完成的线下付款凭证；不从应用钱包扣款。请在采购明细页登记。</p>`+table(['付款号','采购单','原金额（元）','原凭证号','操作人 / 时间','纠错或退款'],rows.map(p=>[p.id,p.purchase_id,money(p.amount),esc(p.reference),`${p.operator_id} / ${esc(p.created_at)}`,button('凭证纠错','payment-correct',p.id)+button('冲销错误付款','reverse-payment',p.id)+button('登记供应商退款','supplier-refund',p.id)]));
      if(tab==='payment-events')body.innerHTML='<h2>付款纠错与退款审计</h2><p>原付款和原凭证保留。金额错误先冲销再重新登记；实际退款须登记供应商退款，净已付减少后才可冲销收货。</p>'+table(['记录 / 原付款','采购单','类型','冲减金额','新凭证号','原因','操作人 / 时间'],rows.map(p=>[`${p.id} / ${p.payment_id}`,p.purchase_id,text(p.kind),money(p.amount),esc(p.reference || '—'),esc(p.reason),`${p.operator_id} / ${esc(p.created_at)}`]));
      if(tab==='audit')body.innerHTML=`<h2 class="section-title">操作审计</h2>`+table(['记录','操作','单据','操作人','时间','说明'],rows.map(a=>[a.id,text(a.action),a.document_id,a.operator_id,esc(a.created_at),esc(a.detail)]));
      if(tab==='suppliers')body.querySelectorAll('[data-erp-action=supplier-status]').forEach(b=>b.insertAdjacentHTML('beforebegin',button('编辑资料','supplier-edit',b.dataset.id.split(':')[0])));
      if(!['finance'].includes(tab))body.insertAdjacentHTML('beforeend',`<div class="form-actions">${history.length?button('上一批','previous'):''}${rows.length===50?button('更早记录','next'):''}${button('刷新','refresh')}</div>`);
    }
    function purchaseLine() {return `<fieldset data-erp-line><legend>采购物料</legend>${ids('物料','materialId',materials)}${field('采购数量','quantity','例如：2','number','min="0.001" max="999999999" step="0.001"')}${field('采购单位','purchaseUnit','例如：箱','text','maxlength="16"')}${field('每采购单位含基础单位数量','factor','例如：1箱=100只，填100','number','min="0.001" max="999999999" step="0.001"')}${field('每采购单位价格（元）','unitPrice','例如：30.0000','number','min="0.0001" max="999999999" step="0.0001"')}${button('移除此行','remove-line')}</fieldset>`;}
    async function refresh(resource=tab) {
      shell.querySelectorAll('[data-erp-action=tab]').forEach(b=>{if(b.dataset.id===tab)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');});
      const current=++version;body.innerHTML='<p role="status">正在读取本门店数据…</p>';
      try {
        if(!store){body.innerHTML='<p>账号尚未关联可操作门店，请先维护门店。</p>';return;}
        if(resource==='deliveries') {
          const delivery=await api('/api/admin/outbox');if(!active() || current!==version)return;
          body.innerHTML=`<h2 class="section-title">全平台事件投递</h2><p>等待投递 ${delivery.summary.pending} 条，最高重试 ${delivery.summary.maxRetries} 次。最早等待 ${esc(delivery.summary.oldest || '—')}。</p><p class="help-text">失败记录持久保留，自动退避重试。修复下游故障后，可让未被认领的事件立即重投；已送达事件不能重复补偿。</p>${table(['事件','类型 / 订单','失败次数','创建时间','操作'],delivery.events.map(e=>[e.id,`${esc(e.event_type)} / ${e.order_id}`,e.retry_count,esc(e.create_time),button('立即重投','event-retry',e.id)]))}${button('刷新投递状态','refresh')}`;return;
        }
        const catalogs=await Promise.all([call('materials?limit=50'),call('suppliers?limit=50&enabled=true')]);
        if(current!==version)return;[materials,suppliers]=catalogs;
        if(resource==='finance') {
          const facts=await call('finance');if(current!==version)return;const p=facts.procurement,o=facts.operations;
          body.innerHTML=`<h2 class="section-title">采购应付与付款</h2>${table(['口径','金额（元）'],[['累计订货',money(p.ordered)],['已收货应付',money(p.payable)],['净已付（付款减冲销与退款）',money(p.paid)],['未付',money(p.unpaid)]])}<p class="help-text">${esc(facts.procurementBasis)}</p><h2 class="section-title">订单资金事实</h2>${table(['口径','金额（元）'],[['累计订单收款',money(o.receipts)],['成功退款',money(o.refunds)],['平台待释放托管',money(o.held)],['累计商户净结算',money(o.merchantSettled)],['累计骑手配送收入',money(o.deliveryAllocated)],['平台售后承担',money(o.platformAfterSalesCost)],['商户待偿欠款',money(o.merchantDebt)],['商户累计钱包入账',money(o.walletCredited)],['商户累计偿还欠款',money(o.debtRepaid)]])}<p class="help-text">${esc(o.basis)}。查询时间 ${esc(new Date(o.observedAt).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',hour12:false}))}。</p>${button('刷新对账','refresh')}`;
        }else {const result=await call(`${resource}?limit=50&before=${before}${resource==='purchases' && supplierFilter?`&supplierId=${supplierFilter}`:''}`);if(current===version){rows=result;renderList();}}
      }catch(e){if(active() && current===version)body.innerHTML=`<p role="alert">${esc(e.message)}</p>${button('重试读取','refresh')}`;}
    }
    async function detail(id) {
      const target=body.querySelector('[data-erp-detail]');if(!target)return;
      const purchaseId=Number(id),current=++detailVersion,viewVersion=version;
      const p=rows.find(r=>Number(r.id)===purchaseId);if(!p)return;
      target.innerHTML='<p role="status">正在读取采购明细…</p>';
      const [lines,receipts]=await Promise.all([call(`purchases/${purchaseId}/lines`),call(`receipts?purchaseId=${purchaseId}`)]);
      if(!active() || !target.isConnected || current!==detailVersion || viewVersion!==version)return;
      target.innerHTML=`<h2 class="section-title section">采购单 ${purchaseId}</h2>${table(['物料','订购 / 已收','采购单位','换算至基础单位','单价（元）'],lines.map(l=>[esc(l.name),`${esc(l.quantity)} / ${esc(l.received)}`,esc(l.purchase_unit),`${esc(l.factor)} ${esc(l.unit)}`,esc(l.unit_price)]))}`+
        (p.status==='CONFIRMED'?form('receive','分批收货',select('本单物料','materialId',lines.map(l=>[l.material_id,l.name]))+field('本次收货数量（采购单位）','quantity','例如：本次到货1箱','number','min="0.001" max="999999999" step="0.001"')):'')+
        (Number(p.payable)>Number(p.paid)?form('pay',`登记供应商付款 · 未付 ¥${money(Number(p.payable)-Number(p.paid))}`,field('实际已付款金额（元）','amount','例如：30.00','number','min="0.01" max="999999999" step="0.01"')+field('唯一付款凭证号','reference','例如：银行转账流水号','text','maxlength="100"')):'')+
        `<h2 class="section-title section">本单收货记录</h2>${table(['收货单','时间','操作人','纠正'],receipts.map(r=>[r.id,esc(r.created_at),r.operator_id,button('冲销收货','reverse-receipt',r.id)]))}`;
      target.querySelectorAll('[data-erp-form]').forEach(f=>{f.dataset.purchaseId=String(purchaseId);});
      target.scrollIntoView({block:'nearest',behavior:'smooth'});
    }
    async function write(action,payload,formNode,reviewed=false) {
      if(busy || !active())return;
      const requestStore=store,fingerprint=JSON.stringify([requestStore,action,payload]);
      let request=pending.get(fingerprint);
      if(request && !reviewed && !window.confirm(`请核对门店 ${requestStore} 与原请求内容：\n${JSON.stringify(request.payload,null,2)}\n确认使用原请求号重试？`))return;
      if(!request && [...pending.values()].some(r=>r.store===requestStore && r.action===action)){toast('该操作有未确认请求，请先核对并重试原请求',true);return;}
      if(!request){request={store:requestStore,action,key:crypto.randomUUID(),payload:JSON.parse(JSON.stringify(payload))};pending.set(fingerprint,request);}
      busy=true;const controls=shell.querySelectorAll('button,input,select');controls.forEach(c=>{c.disabled=true;});
      let sent=false;
      try {
        savePending(request);renderPending();sent=true;
        const result=await api(`/api/erp/stores/${requestStore}/${action}`,{method:'POST',headers:{'Idempotency-Key':request.key},body:JSON.stringify(request.payload)});
        pending.delete(fingerprint);savePending(request,true);
        if(active() && store===requestStore){renderPending();toast(`操作成功，单据 ${result.id}`);await refresh();}
      }catch(e){
        if(sent && e.responseReceived){pending.delete(fingerprint);savePending(request,true);if(formNode)delete formNode.dataset.uncertain;}
        if(!active() || store!==requestStore)return;
        renderPending();toast(e.message || '操作失败，请重试核对',true);
        if(formNode?.isConnected){formNode.querySelector('[data-erp-error]').textContent=e.message;if(sent && !e.responseReceived)formNode.dataset.uncertain=JSON.stringify({action,payload:request.payload});}
      }finally{busy=false;controls.forEach(c=>{if(c.isConnected)c.disabled=false;});}
    }

    shell.addEventListener('submit',async e=>{
      const f=e.target.closest('[data-erp-form]');if(!f)return;e.preventDefault();
      if(f.dataset.uncertain){const old=JSON.parse(f.dataset.uncertain);return write(old.action,old.payload,f);}
      const action=f.dataset.erpForm,d=Object.fromEntries(new FormData(f));let payload=d;
      if(action==='purchases')payload={supplierId:Number(d.supplierId),lines:[...f.querySelectorAll('[data-erp-line]')].map(l=>{const get=n=>l.querySelector(`[name="${n}"]`).value;return {materialId:Number(get('materialId')),quantity:get('quantity'),unitPrice:get('unitPrice'),purchaseUnit:get('purchaseUnit'),factor:get('factor')};})};
      if(action==='receive')payload={id:Number(f.dataset.purchaseId),lines:[{materialId:Number(d.materialId),quantity:d.quantity}]};
      if(action==='pay')payload={id:Number(f.dataset.purchaseId),amount:d.amount,reference:d.reference};
      if(action==='adjust')payload={...d,materialId:Number(d.materialId)};
      if(action==='supplier-update')payload={...d,id:Number(f.dataset.supplierId)};
      await write(action,payload,f);
    });
    shell.addEventListener('click',async e=>{
      const b=e.target.closest('[data-erp-action]');if(!b || busy)return;const a=b.dataset.erpAction,id=b.dataset.id;
      try {
        if(a==='tab'){tab=id;before=0;history=[];return refresh();}
        if(a==='refresh')return refresh();
        if(a.startsWith('picker-'))return pickerPage(b.closest('[data-erp-picker]'),a);
        if(a==='retry-pending'){const request=[...pending.values()].find(r=>r.store===store && r.key===id);if(request && window.confirm(`请核对门店 ${store}、操作 ${labels[request.action] || request.action} 及原内容：\n${JSON.stringify(request.payload,null,2)}\n确认使用原请求号重试？`))return write(request.action,request.payload,undefined,true);return;}
        if(a==='next'){history.push(before);before=Number(rows.at(-1)?.id || 0);return refresh();}
        if(a==='previous'){before=history.pop() || 0;return refresh();}
        if(a==='add-line'){const container=body.querySelector('[data-erp-lines]');if(container.children.length<50)container.insertAdjacentHTML('beforeend',purchaseLine());return;}
        if(a==='remove-line'){const line=b.closest('[data-erp-line]');if(line.parentElement.children.length>1)line.remove();return;}
        if(a==='detail')return await detail(id);
        if(a==='supplier-edit') {
          const supplier=rows.find(s=>Number(s.id)===Number(id)),f=body.querySelector('form');
          f.dataset.erpForm='supplier-update';f.dataset.supplierId=id;f.elements.name.value=supplier.name;f.elements.contact.value=supplier.contact;f.scrollIntoView({block:'nearest'});f.elements.name.focus();return;
        }
        if(a==='event-retry') {await api(`/api/admin/outbox/${Number(id)}/retry`,{method:'POST'});toast('已安排重新投递');return refresh();}
        if(a==='supplier-purchases'){tab='purchases';before=0;history=[];supplierFilter=Number(id);return refresh();}
        if(a==='clear-supplier'){supplierFilter=0;before=0;history=[];return refresh();}
        if(a==='supplier-status'){const [supplier,enabled]=id.split(':');return write(a,{id:Number(supplier),enabled:enabled==='1'});}
        if(['payment-correct','reverse-payment','supplier-refund'].includes(a)){
          const reason=window.prompt('请填写原因。仅追加审计记录，原付款保留：');if(!reason?.trim())return;
          const payload={id:Number(id),reason};
          if(a!=='reverse-payment'){payload.reference=window.prompt(a==='supplier-refund'?'实际到账的唯一退款凭证号：':'正确的新付款凭证号：');if(!payload.reference?.trim())return;}
          if(a==='supplier-refund'){payload.amount=window.prompt('实际收到的供应商退款金额（元，最多两位小数）：');if(!payload.amount?.trim())return;}
          if(!window.confirm(a==='reverse-payment'?'确认原付款登记有误？将冲销其尚未冲退余额；实际收到退款请选择供应商退款。':`请核对门店 ${store}、付款 ${id}：\n${JSON.stringify(payload,null,2)}`))return;
          return write(a,payload);
        }
        if(['reverse','reverse-receipt'].includes(a)){const reason=window.prompt('请填写冲销原因。生效后追加反向流水，保留原记录：');if(!reason?.trim())return;return write(a,{id:Number(id),reason});}
        if(['approve','reject'].includes(a))return write('review',{id:Number(id),approve:a==='approve'});
        if(['submit','confirm','close'].includes(a)){if(a==='close' && !window.confirm('关闭后不能继续收货，已收货应付及付款记录保留。确定关闭？'))return;return write(a,{id:Number(id)});}
      }catch(error){if(active())toast(error.message,true);}
    });
    shell.querySelector('[data-erp-store]').addEventListener('change',e=>{store=Number(e.target.value);before=0;history=[];supplierFilter=0;restorePending(store);renderPending();void refresh();});
    restorePending(store);renderPending();await refresh();
  }
  return {mount};
})();
