/* Store-scoped operating-supplies procurement. All facts and mutations come from ERP APIs. */
window.TakeoutErp = (() => {
  'use strict';
  const esc = v => String(v ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const labels = {DRAFT:'草稿',SUBMITTED:'待审核',CONFIRMED:'已确认',CLOSED:'已关闭',APPROVED:'已通过',REJECTED:'已拒绝',COUNT:'盘点',LOSS:'报损',RECEIPT:'收货',ADJUST:'调整',REVERSAL:'冲销'};
  Object.assign(labels,{suppliers:'新增供应商','supplier-update':'修改供应商','supplier-status':'供应商启停',materials:'建立物料',purchases:'创建采购',submit:'提交采购',confirm:'确认采购',close:'关闭采购',receive:'收货入库','reverse-receipt':'收货冲销',adjust:'提交调整',review:'审核调整',reverse:'调整冲销',pay:'登记付款'});
  const text = v => esc(labels[v] || v);
  const money = v => Number(v || 0).toFixed(2);
  const button = (label,action,id='',extra='') => `<button class="btn ${extra}" type="button" data-erp-action="${action}" data-id="${esc(id)}">${label}</button>`;
  const field = (label,name,example,type='text',extra='') => `<label class="field">${label}<input class="input" name="${name}" placeholder="${example}" type="${type}" required ${extra}></label>`;
  const select = (label,name,rows) => `<label class="field">${label}<select class="select" name="${name}" required><option value="">请选择</option>${rows.map(([id,label])=>`<option value="${esc(id)}">${esc(label)}</option>`).join('')}</select></label>`;
  const form = (action,title,body) => `<form class="page-panel section" data-erp-form="${action}"><h2 class="section-title">${title}</h2><div class="form-grid">${body}</div><p class="help-text" role="alert" data-erp-error></p><div class="form-actions"><button class="btn primary" type="submit">${({pay:'登记已完成的线下付款',purchases:'保存采购草稿',receive:'登记本次收货',adjust:'提交调整审核'})[action] || '保存资料'}</button></div></form>`;
  const table = (headers,rows) => `<div class="table-wrap"><table class="${headers.length<=3?'erp-compact':''}"><thead><tr>${headers.map(h=>`<th scope="col">${h}</th>`).join('')}</tr></thead><tbody>${rows.length?rows.map(row=>`<tr>${row.map(cell=>`<td class="${/^-?\d+(\.\d+)?$/.test(String(cell))?'erp-number':''}">${cell}</td>`).join('')}</tr>`).join(''):`<tr><td colspan="${headers.length}">暂无记录。完成上方操作后可在此查询。</td></tr>`}</tbody></table></div>`;
  async function mount({root,api,toast,live,stores,role}) {
    let store=Number(stores[0]?.id || 0),tab='purchases',purchase=0,rows=[],materials=[],suppliers=[],before=0,history=[];
    const pending=new Map(); let busy=false,version=0;
    root.innerHTML=`<section data-erp><div class="page-head"><div><h1>采购与库存</h1><p class="help-text">餐盒与经营耗材 · 采购确认后分批收货，按收货金额登记应付。</p></div><label class="field">操作门店<select class="select" data-erp-store>${stores.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join('')}</select></label></div><p class="help-text">耗材按固定基础单位记账，不扣减菜品库存。盘点、报损须由另一位管理员或门店所有者审核。</p><nav class="toolbar" aria-label="采购库存功能">${[['purchases','采购与收货'],['suppliers','供应商'],['materials','物料库存'],['ledger','库存台账'],['adjustments','盘点与报损'],['payments','付款记录'],['finance','经营对账'],['audit','操作审计']].map(([id,label])=>button(label,'tab',id)).join('')}</nav><div data-erp-body aria-live="polite"></div></section>`;
    const shell=root.querySelector('[data-erp]'),body=shell.querySelector('[data-erp-body]');
    if(role===2)shell.querySelector('nav').insertAdjacentHTML('beforeend',button('事件投递与补偿','tab','deliveries'));
    const active=()=>live() && shell.isConnected;
    const path=resource=>`/api/erp/stores/${store}/${resource}`;
    const call=async(resource,options)=>{if(!active())throw new Error('页面已切换，请重新进入');const result=await api(path(resource),options);if(!active())throw new Error('页面已切换');return result;};
    const materialName=id=>materials.find(m=>Number(m.id)===Number(id))?.name || `物料 ${id}`;
    const ids=(label,name,records)=>select(label,name,records.map(r=>[r.id,`${r.name} (${r.unit || r.contact || r.id})`]));
    function renderList() {
      if(tab==='suppliers')body.innerHTML=form('suppliers','维护供应商',field('供应商名称','name','例如：安心餐盒厂','text','maxlength="100"')+field('联系人与联系方式','contact','例如：王经理，门店采购电话','text','maxlength="100"'))+table(['供应商','联系方式','状态','操作'],rows.map(r=>[esc(r.name),esc(r.contact),r.enabled?'启用':'停用',button(r.enabled?'停用':'启用','supplier-status',`${r.id}:${r.enabled?0:1}`)+button('关联采购','supplier-purchases',r.id)]));
      if(tab==='materials')body.innerHTML=form('materials','建立经营耗材',field('物料名称','name','例如：750ml餐盒','text','maxlength="100"')+field('基础单位（创建后固定）','unit','例如：只、包、卷','text','maxlength="16"'))+table(['物料','当前结存','基础单位'],rows.map(r=>[esc(r.name),esc(r.balance),esc(r.unit)]));
      if(tab==='purchases') {
        body.innerHTML=form('purchases','创建采购单',ids('供应商','supplierId',suppliers.filter(s=>s.enabled))+`<div data-erp-lines class="erp-lines">${purchaseLine()}</div>`+button('增加采购物料','add-line'))+
          table(['单号 / 供应商','状态','订货金额','已收货应付','已付 / 未付','操作'],rows.map(p=>[`${p.id} / ${esc(suppliers.find(s=>s.id===p.supplier_id)?.name || p.supplier_id)}`,text(p.status),money(p.ordered_amount),money(p.payable),`${money(p.paid)} / ${money(Number(p.payable)-Number(p.paid))}`,
            button('明细与收货','detail',p.id)+(p.status==='DRAFT'?button('提交审核','submit',p.id):'')+(p.status==='SUBMITTED'?button('确认采购','confirm',p.id):'')+(p.status!=='CLOSED'?button('关闭未收部分','close',p.id):'')]))+`<section data-erp-detail></section>`;
      }
      if(tab==='ledger')body.innerHTML=`<h2 class="section-title">库存流水</h2><p class="help-text">按基础单位记账。已生效流水不可覆盖；收货按整张收货单冲销，调整按原流水冲销。</p>`+table(['流水 / 来源单据','物料','变动','变动前 → 后','操作人 / 时间','原因','纠正'],rows.map(l=>[`${l.id} / ${text(l.source_type)} ${l.source_id}${l.reversal_of?` / 原流水 ${l.reversal_of}`:''}`,`${esc(materialName(l.material_id))}（${esc(l.unit)}）`,esc(l.delta),`${esc(l.before_qty)} → ${esc(l.after_qty)}`,`${l.operator_id} / ${esc(l.created_at)}`,esc(l.reason),l.source_type==='ADJUST'?button('冲销调整','reverse',l.id):l.source_type==='RECEIPT'?button('冲销整张收货单','reverse-receipt',l.source_id):'—']));
      if(tab==='adjustments')body.innerHTML=form('adjust','提交盘点或报损',ids('物料','materialId',materials)+select('调整类型','kind',[['COUNT','盘点：填写实盘数'],['LOSS','报损：填写损耗数']])+field('数量（基础单位）','quantity','例如：实盘95或报损5','number','min="0" max="999999999" step="0.001"')+field('差异原因','reason','例如：运输破损5只','text','maxlength="255"'))+table(['单号 / 类型','物料','账面 / 实盘','原因','状态 / 制单人','审核'],rows.map(a=>[`${a.id} / ${text(a.kind)}`,esc(materialName(a.material_id)),`${esc(a.book_qty)} / ${esc(a.actual_qty)}`,esc(a.reason),`${text(a.status)} / ${a.operator_id}`,a.status==='SUBMITTED'?button('通过','approve',a.id)+button('拒绝','reject',a.id):`审核人 ${a.reviewer_id}`]));
      if(tab==='payments')body.innerHTML=`<h2 class="section-title">供应商付款记录</h2><p class="help-text">这里只登记实际完成的线下付款凭证；不从应用钱包扣款。请在采购明细页登记。</p>`+table(['付款号','采购单','金额（元）','凭证号','操作人 / 时间'],rows.map(p=>[p.id,p.purchase_id,money(p.amount),esc(p.reference),`${p.operator_id} / ${esc(p.created_at)}`]));
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
        [materials,suppliers]=await Promise.all([call('materials?limit=100'),call('suppliers?limit=100')]);
        if(current!==version)return;
        if(resource==='finance') {
          const facts=await call('finance');if(current!==version)return;const p=facts.procurement,o=facts.operations;
          body.innerHTML=`<h2 class="section-title">采购应付与付款</h2>${table(['口径','金额（元）'],[['累计订货',money(p.ordered)],['已收货应付',money(p.payable)],['已付（线下凭证登记）',money(p.paid)],['未付',money(p.unpaid)]])}<p class="help-text">${esc(facts.procurementBasis)}</p><h2 class="section-title">订单资金事实</h2>${table(['口径','金额（元）'],[['累计订单收款',money(o.receipts)],['成功退款',money(o.refunds)],['平台待释放托管',money(o.held)],['累计商户结算',money(o.merchantSettled)],['已结算订单配送分配',money(o.deliveryAllocated)]])}<p class="help-text">${esc(o.basis)}。查询时间 ${esc(new Date(o.observedAt).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',hour12:false}))}。</p>${button('刷新对账','refresh')}`;
        }else {rows=await call(`${resource}?limit=50&before=${before}`);if(current===version)renderList();}
      }catch(e){if(active() && current===version)body.innerHTML=`<p role="alert">${esc(e.message)}</p>${button('重试读取','refresh')}`;}
    }
    async function detail(id) {
      const target=body.querySelector('[data-erp-detail]');if(!target)return;
      purchase=Number(id);const p=rows.find(r=>Number(r.id)===purchase);const [lines,receipts]=await Promise.all([call(`purchases/${purchase}/lines`),call(`receipts?purchaseId=${purchase}`)]);
      if(!active() || !target.isConnected)return;
      target.innerHTML=`<h2 class="section-title section">采购单 ${purchase}</h2>${table(['物料','订购 / 已收','采购单位','换算至基础单位','单价（元）'],lines.map(l=>[esc(l.name),`${esc(l.quantity)} / ${esc(l.received)}`,esc(l.purchase_unit),`${esc(l.factor)} ${esc(l.unit)}`,esc(l.unit_price)]))}`+
        (p.status==='CONFIRMED'?form('receive','分批收货',select('本单物料','materialId',lines.map(l=>[l.material_id,l.name]))+field('本次收货数量（采购单位）','quantity','例如：本次到货1箱','number','min="0.001" max="999999999" step="0.001"')):'')+
        (Number(p.payable)>Number(p.paid)?form('pay',`登记供应商付款 · 未付 ¥${money(Number(p.payable)-Number(p.paid))}`,field('实际已付款金额（元）','amount','例如：30.00','number','min="0.01" max="999999999" step="0.01"')+field('唯一付款凭证号','reference','例如：银行转账流水号','text','maxlength="100"')):'')+
        `<h2 class="section-title section">本单收货记录</h2>${table(['收货单','时间','操作人','纠正'],receipts.map(r=>[r.id,esc(r.created_at),r.operator_id,button('冲销收货','reverse-receipt',r.id)]))}`;
      target.scrollIntoView({block:'nearest',behavior:'smooth'});
    }
    async function write(action,payload,formNode) {
      if(busy || !active())return;busy=true;
      const fingerprint=JSON.stringify([store,action,payload]);
      let request=pending.get(fingerprint);if(!request){request={key:crypto.randomUUID(),payload};pending.set(fingerprint,request);}
      const controls=shell.querySelectorAll('button,input,select');controls.forEach(c=>{c.disabled=true;});
      try {
        const result=await call(action,{method:'POST',headers:{'Idempotency-Key':request.key},body:JSON.stringify(request.payload)});
        pending.delete(fingerprint);toast(`操作成功，单据 ${result.id}`);await refresh();
      }catch(e){
        if(!active())return;
        if(e.responseReceived)pending.delete(fingerprint);
        toast(e.message || '操作失败，请重试核对',true);
        if(formNode?.isConnected){formNode.querySelector('[data-erp-error]').textContent=e.message;if(!e.responseReceived)formNode.dataset.uncertain=JSON.stringify({action,payload});}
      }finally{busy=false;controls.forEach(c=>{if(c.isConnected)c.disabled=false;});}
    }
    shell.addEventListener('submit',async e=>{
      const f=e.target.closest('[data-erp-form]');if(!f)return;e.preventDefault();
      if(f.dataset.uncertain){const old=JSON.parse(f.dataset.uncertain);return write(old.action,old.payload,f);}
      const action=f.dataset.erpForm,d=Object.fromEntries(new FormData(f));let payload=d;
      if(action==='purchases')payload={supplierId:Number(d.supplierId),lines:[...f.querySelectorAll('[data-erp-line]')].map(l=>{const get=n=>l.querySelector(`[name="${n}"]`).value;return {materialId:Number(get('materialId')),quantity:get('quantity'),unitPrice:get('unitPrice'),purchaseUnit:get('purchaseUnit'),factor:get('factor')};})};
      if(action==='receive')payload={id:purchase,lines:[{materialId:Number(d.materialId),quantity:d.quantity}]};
      if(action==='pay')payload={id:purchase,amount:d.amount,reference:d.reference};
      if(action==='adjust')payload={...d,materialId:Number(d.materialId)};
      if(action==='supplier-update')payload={...d,id:Number(f.dataset.supplierId)};
      await write(action,payload,f);
    });
    shell.addEventListener('click',async e=>{
      const b=e.target.closest('[data-erp-action]');if(!b || busy)return;const a=b.dataset.erpAction,id=b.dataset.id;
      try {
        if(a==='tab'){tab=id;before=0;history=[];return refresh();}
        if(a==='refresh')return refresh();
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
        if(a==='supplier-purchases'){tab='purchases';before=0;rows=await call(`purchases?supplierId=${Number(id)}`);renderList();return;}
        if(a==='supplier-status'){const [supplier,enabled]=id.split(':');return write(a,{id:Number(supplier),enabled:enabled==='1'});}
        if(['reverse','reverse-receipt'].includes(a)){const reason=window.prompt('请填写冲销原因。生效后追加反向流水，保留原记录：');if(!reason?.trim())return;return write(a,{id:Number(id),reason});}
        if(['approve','reject'].includes(a))return write('review',{id:Number(id),approve:a==='approve'});
        if(['submit','confirm','close'].includes(a)){if(a==='close' && !window.confirm('关闭后不能继续收货，已收货应付及付款记录保留。确定关闭？'))return;return write(a,{id:Number(id)});}
      }catch(error){if(active())toast(error.message,true);}
    });
    shell.querySelector('[data-erp-store]').addEventListener('change',e=>{store=Number(e.target.value);purchase=0;before=0;history=[];pending.clear();void refresh();});
    await refresh();
  }
  return {mount};
})();
