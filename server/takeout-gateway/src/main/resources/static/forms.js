/* Shared progressive form controls. Business payloads and original input elements remain intact. */
(() => {
  'use strict';
  let sequence = 0;
  let services = null;
  const uploads = new WeakMap();
  const labels = {keyword:'搜索关键词',phone:'手机号',email:'邮箱',password:'密码',confirmPassword:'确认密码',code:'验证码',image:'图片地址',tag:'标签',reply:'回复内容'};
  const node = (tag, className, text) => { const el=document.createElement(tag);if(className)el.className=className;if(text!==undefined)el.textContent=text;return el; };
  function highlight(target, text, query) {
    target.replaceChildren();const value=String(text),key=String(query).trim();
    if(!key){target.textContent=value;return;}
    let at=0,match;const lower=value.toLocaleLowerCase(),needle=key.toLocaleLowerCase();
    while((match=lower.indexOf(needle,at))!==-1){target.append(document.createTextNode(value.slice(at,match)),node('mark','',value.slice(match,match+key.length)));at=match+key.length;}
    target.append(document.createTextNode(value.slice(at)));
  }
  function labelText(input) {
    const label=input.labels?.[0] || input.closest('label.field');
    const text=label ? [...label.childNodes].filter(n=>n.nodeType===Node.TEXT_NODE || (n.nodeType===Node.ELEMENT_NODE && n.tagName==='SPAN' && !n.className && !n.querySelector('input'))).map(n=>n.textContent).join('').trim() : '';
    return text || input.getAttribute('aria-label') || labels[input.name] || input.placeholder || '填写内容';
  }
  function validation(input) {
    if(input.disabled || input.type==='hidden')return '';
    if(input.validity.valueMissing)return '请填写'+(input.dataset.fieldLabel||'此项');
    if(input.validity.typeMismatch)return input.type==='email'?'请输入完整邮箱，例如 name@example.com':'请输入正确的地址';
    if(input.validity.patternMismatch)return input.name==='phone'?'请输入 11 位手机号':input.autocomplete==='one-time-code'?'请输入完整的 6 位验证码':'请按下方说明填写';
    if(input.validity.tooShort)return `至少输入 ${input.minLength} 个字符`;
    if(input.validity.rangeUnderflow)return `不能小于 ${input.min}`;
    if(input.validity.rangeOverflow)return `不能大于 ${input.max}`;
    if(input.validity.badInput || input.validity.stepMismatch)return '请输入符合要求的数值';
    if(input.type==='password' && input.value){
      if(input.minLength>0 && input.value.length<input.minLength)return `至少输入 ${input.minLength} 个字符`;
      if(input.maxLength>0 && input.value.length>input.maxLength)return `最多输入 ${input.maxLength} 个字符`;
      if(input.dataset.passwordRules && /[^A-Za-z0-9!@#$%^&*._+=?\-]/.test(input.value))return '密码不含空格，仅支持数字、英文字母和 !@#$%^&*._+-=?';
    }
    const password=input.form?.querySelector('[name="password"], [name="newPassword"]');
    if(input.name==='confirmPassword' && password && input.value!==password.value)return '两次输入的密码不一致';
    return input.validity.valid?'':input.validationMessage;
  }
  function hintSatisfied(input) {
    return input.name==='phone' && /^1\d{10}$/.test(input.value.trim())
      || input.type==='password' && Boolean(input.value) && !validation(input);
  }
  function feedback(input, message) {
    const error=document.getElementById(input.dataset.fieldError);
    if(error){error.textContent=message;error.hidden=!message;}
    input.dataset.fieldValidationFailed=message?'true':'';
    const help=document.getElementById(input.id+'-help');
    if(help)help.hidden=hintSatisfied(input);
    input.setAttribute('aria-invalid',String(Boolean(message)));
  }
  function enhanceInput(input) {
    if(input.dataset.formEnhanced || ['hidden','file','checkbox','radio','submit','button','range','color'].includes(input.type))return;
    input.dataset.formEnhanced='true';
    const label=labelText(input),oldLabel=input.labels?.[0] || input.closest('label.field');
    input.dataset.fieldLabel=label;input.id ||= `form-control-${++sequence}`;
    const field=node('span','form-field'),control=node('span','floating-control'),caption=node(oldLabel?'span':'label','floating-label',label);
    caption.htmlFor=input.id;
    if(oldLabel){for(const child of [...oldLabel.childNodes]){if(child.nodeType===Node.TEXT_NODE)child.textContent='';else if(child.tagName==='SPAN' && !child.className && !child.querySelector('input'))child.hidden=true;}}
    const help=node('span','form-help',input.placeholder || (input.required?'必填':'选填'));
    help.id=input.id+'-help';
    const rules=(input.getAttribute('aria-describedby')||'').split(/\s+/).map(id=>document.getElementById(id)).find(el=>el?.classList.contains('auth-rules'));
    if(rules){help.textContent=rules.textContent;input.dataset.passwordRules='true';rules.hidden=true;}
    const existingError=oldLabel?.querySelector('.auth-field-error');
    const error=existingError || node('span','form-error');error.classList.add('form-error');error.id ||= input.id+'-error';error.hidden=true;error.setAttribute('role','alert');
    input.dataset.fieldError=error.id;
    input.setAttribute('aria-describedby',[input.getAttribute('aria-describedby'),help.id,error.id].filter(Boolean).join(' '));
    input.setAttribute('aria-label',label);input.placeholder='';
    input.before(field);control.append(input,caption);field.append(control,help,error);
    const sync=()=>{control.classList.toggle('has-value',input.value!=='');help.hidden=hintSatisfied(input);};sync();
    input.addEventListener('input',sync);input.addEventListener('change',sync);
    input.addEventListener('focus',sync);input.addEventListener('blur',()=>{sync();feedback(input,validation(input));});
    if(input.autocomplete==='one-time-code'){input.inputMode='numeric';help.textContent='6 位验证码，可整段粘贴或使用系统自动填入';}
    if(input.name==='tag' && input.tagName==='INPUT')enhanceTags(input,field,help);
  }
  function enhanceTags(input,field,help) {
    const backing=node('input');backing.type='hidden';backing.name=input.name;backing.value=input.value;
    input.removeAttribute('name');input.removeAttribute('required');input.value='';field.append(backing);
    const list=node('span','tag-input-list');field.prepend(list);help.textContent='输入关键词后按回车添加；点击标签可删除（总长最多 32 字）';
    const tags=()=>backing.value.split(/[,，]/).map(s=>s.trim()).filter(Boolean);
    const render=()=>{list.replaceChildren();for(const tag of tags()){const button=node('button','',tag+' ×');button.type='button';button.setAttribute('aria-label','删除标签 '+tag);button.onclick=()=>{if(input.disabled)return;backing.value=tags().filter(t=>t!==tag).join(',');render();};list.append(button);}};
    const commit=()=>{const tag=input.value.trim().replace(/[,，]/g,' ');if(!tag)return true;const next=[...new Set([...tags(),tag])].join(',');if(next.length>32){feedback(input,'标签总长度不能超过 32 字');return false;}backing.value=next;input.value='';input.dispatchEvent(new Event('input',{bubbles:true}));render();return true;};
    input.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.isComposing){e.preventDefault();commit();}});
    input.addEventListener('blur',commit);render();
  }
  function enhanceSelect(select) {
    if(!select.dataset.selectFeedback){
      select.dataset.selectFeedback='true';select.dataset.fieldLabel=labelText(select);select.id ||= `form-select-${++sequence}`;
      const error=node('span','form-error');error.id=select.id+'-error';error.hidden=true;error.setAttribute('role','alert');select.after(error);
      select.dataset.fieldError=error.id;select.setAttribute('aria-describedby',error.id);
      select.addEventListener('blur',()=>feedback(select,validation(select)));select.addEventListener('change',()=>feedback(select,''));
    }
    if(select.dataset.formSelect || select.options.length<=8)return;
    select.dataset.formSelect='true';const field=node('div','form-field'),search=node('input','input');
    const label=labelText(select);search.placeholder='输入关键词筛选'+label;search.setAttribute('aria-label','搜索'+label);search.autocomplete='off';
    const list=node('div','form-options');list.hidden=true;list.id=`form-options-${++sequence}`;search.setAttribute('aria-controls',list.id);search.setAttribute('aria-expanded','false');
    select.before(field);field.append(search,select,list);enhanceInput(search);
    const render=()=>{list.replaceChildren();const query=search.value.trim();const rows=[...select.options].filter(o=>!o.disabled&&o.textContent.toLocaleLowerCase().includes(query.toLocaleLowerCase()));
      for(const option of rows){const button=node('button');button.type='button';highlight(button,option.textContent,query);button.onclick=()=>{select.value=option.value;select.dispatchEvent(new Event('change',{bubbles:true}));search.value='';list.hidden=true;search.setAttribute('aria-expanded','false');search.dispatchEvent(new Event('input'));select.focus();};list.append(button);}
      if(!rows.length)list.append(node('span','form-help','没有匹配项，请换个关键词'));
      list.hidden=false;search.setAttribute('aria-expanded','true');};
    search.addEventListener('input',render);search.addEventListener('focus',render);
    search.addEventListener('keydown',e=>{if(e.key==='ArrowDown'){e.preventDefault();list.querySelector('button')?.focus();}if(e.key==='Escape'){list.hidden=true;search.setAttribute('aria-expanded','false');}});
    field.addEventListener('focusout',event=>{if(!field.contains(event.relatedTarget)){list.hidden=true;search.setAttribute('aria-expanded','false');}});
  }
  function enhanceUpload(input) {
    if(input.dataset.formUpload)return;input.dataset.formUpload='true';
    input.accept='image/jpeg,image/png,image/webp,image/gif';
    const zone=node('div','upload-zone'),rows=node('div'),error=node('p','form-error');error.setAttribute('role','alert');
    const title=node('span','','点击选择或拖拽图片');const limit=Number(input.dataset.maxFiles || (input.multiple?9:1));
    const hint=node('span','form-help',`JPG、PNG、WebP、GIF · 每张不超过 5MB · 最多 ${limit} 张`);
    input.before(zone);zone.append(title,hint,input);zone.after(rows,error);
    let items=[];const updateFiles=()=>{const dt=new DataTransfer();items.forEach(item=>dt.items.add(item.file));input.files=dt.files;};
    const render=()=>{rows.replaceChildren();for(const item of items){const row=node('div','upload-row'),img=node('img'),info=node('div','upload-info'),name=node('span','',item.file.name),status=node('span','',item.message || '等待上传'),progress=node('progress'),remove=node('button','btn','删除');
      img.src=item.preview;img.alt='图片预览';progress.max=100;progress.value=item.percent;progress.setAttribute('aria-label',item.file.name+'上传进度');remove.type='button';
      remove.onclick=()=>{if(input.disabled)return;item.deleted=true;item.abort?.();URL.revokeObjectURL(item.preview);items=items.filter(x=>x!==item);updateFiles();render();};
      info.append(name,status,progress);row.append(img,info,remove);rows.append(row);item.progress=progress;item.status=status;}
    };
    const add=files=>{if(input.disabled)return;error.textContent='';for(const file of files){if(items.length>=limit){error.textContent=`最多上传 ${limit} 张图片`;break;}if(!/^image\/(jpeg|png|webp|gif)$/.test(file.type)||!file.size||file.size>5*1024*1024){error.textContent='请选择 JPG、PNG、WebP、GIF 图片，每张不超过 5MB';continue;}if(items.some(x=>x.file.name===file.name&&x.file.size===file.size&&x.file.lastModified===file.lastModified))continue;items.push({file,preview:URL.createObjectURL(file),percent:0});}updateFiles();render();};
    input.addEventListener('change',()=>add([...input.files]));
    zone.addEventListener('dragover',e=>{e.preventDefault();if(!input.disabled)zone.classList.add('drag-over');});zone.addEventListener('dragleave',()=>zone.classList.remove('drag-over'));
    zone.addEventListener('drop',e=>{e.preventDefault();zone.classList.remove('drag-over');add([...e.dataTransfer.files]);});
    uploads.set(input,{items:()=>items,async send(upload,active){const urls=[];for(const item of [...items]){if(item.deleted)continue;if(!active())throw new Error('页面或账号已变化，请重新操作');if(!item.url){item.message='上传中';item.status.textContent=item.message;
        try{const result=await upload(item.file,percent=>{if(item.deleted)return;item.percent=percent;item.progress.value=percent;item.status.textContent=percent>=99?'正在确认上传…':`上传中 ${percent}%`;},abort=>{item.abort=abort;});if(item.deleted)continue;if(!active())throw new Error('页面或账号已变化，请重新操作');item.url=typeof result==='string'?result:result.url;item.percent=100;item.progress.value=100;item.status.textContent='已上传';}
        catch(cause){if(item.deleted)continue;item.status.textContent=cause.message||'上传失败，请重试';throw cause;}}
      if(!item.deleted)urls.push(item.url);}return urls;},dispose(){for(const item of items){item.deleted=true;item.abort?.();URL.revokeObjectURL(item.preview);}}});
  }
  function scan(root=document) {
    if(root.nodeType!==1 && root!==document)return;
    const elements=selector=>[...(root.matches?.(selector)?[root]:[]),...root.querySelectorAll(selector)];
    elements('input,textarea').forEach(enhanceInput);elements('select').forEach(enhanceSelect);elements('input[type=file]').forEach(enhanceUpload);
    if(services){elements('form').forEach(setupForm);elements('#storeSearch').forEach(setupStoreSearch);}
  }
  function setupStoreSearch(input) {
    if(input.dataset.suggestions)return;input.dataset.suggestions='true';
    const list=node('div','form-options');list.hidden=true;input.closest('.form-field').append(list);
    let timer,version=0;
    input.addEventListener('input',event=>{clearTimeout(timer);const request=++version;list.replaceChildren();list.hidden=true;const query=input.value.trim();if(!query||event.isComposing)return;
      timer=setTimeout(async()=>{try{const stores=await services.searchStores(query);if(request!==version||!input.isConnected)return;list.replaceChildren();for(const store of stores.slice(0,10)){const button=node('button');button.type='button';highlight(button,store.name,query);button.onclick=()=>{input.value=store.name;list.hidden=true;input.form.requestSubmit();};list.append(button);}if(!stores.length)list.append(node('span','form-help','没有匹配的店铺或菜品'));list.hidden=false;}catch(_){if(request===version){list.replaceChildren(node('span','form-help','搜索暂不可用，请重试'));list.hidden=false;}}},300);
    });
    input.addEventListener('keydown',event=>{if(event.key==='ArrowDown'){event.preventDefault();list.querySelector('button')?.focus();}if(event.key==='Escape')list.hidden=true;});
    input.closest('.form-field').addEventListener('focusout',event=>{if(!input.closest('.form-field').contains(event.relatedTarget))list.hidden=true;});
  }
  function setupForm(form) {
    if(form.dataset.formControls)return;form.dataset.formControls='true';
    if(services.options){for(const name of ['categoryId','goodsId','giftGoodsId']){
      const input=form.querySelector(`input[name="${name}"]`);if(!input)continue;
      services.options(name).then(items=>{
        if(!form.isConnected||!items.length)return;
        const select=node('select','select'),field=node('span','form-field');select.name=name;select.required=input.required;select.disabled=input.disabled;
        const label=input.dataset.fieldLabel.replace(/\s*ID$/, '');select.setAttribute('aria-label',label);select.append(new Option(input.required?'请选择':'不设置',input.required?'':'0'));
        for(const item of items)select.append(new Option(item.name,String(item.id)));
        if(input.value && !items.some(item=>String(item.id)===input.value)&&input.value!=='0')select.append(new Option('当前选项 '+input.value,input.value));
        select.value=input.value;field.append(node('span','form-help',label),select);input.closest('.form-field').replaceWith(field);enhanceSelect(select);
      }).catch(()=>{});
    }}
    const image=form.querySelector('input[name=image]');
    if(image){const label=node('label','field full','图片上传（选填）'),file=node('input');file.type='file';file.name='imageFile';label.append(file);image.closest('label')?.after(label);enhanceUpload(file);}
    const existing=form.querySelector('[name=locationKeyword]');
    const address=form.querySelector('[name=address]');
    if(existing || (address && ['merchant-store','rider-settings'].includes(form.dataset.form))){
      let search=existing;
      if(!search){const label=node('label','field full','搜索地图位置');search=node('input','input');search.name='locationKeyword';search.placeholder='输入小区、街道或学校名';label.append(search);address.closest('label').before(label);enhanceInput(search);const results=node('div','location-results');results.dataset.locationResults='';label.after(results);}
      const details=node('details','full'),summary=node('summary','','选择省 / 市 / 区'),regions=node('div','region-picker');details.append(summary,regions);search.closest('label')?.before(details);
      const selects=[],names=['省 / 自治区 / 直辖市','城市','区 / 县'];let request=0;
      for(let level=0;level<3;level++){const label=node('label','field',names[level]),select=node('select','select');select.setAttribute('aria-label',names[level]);select.disabled=true;select.append(new Option('请选择',''));label.append(select);regions.append(label);selects.push(select);
        select.addEventListener('change',()=>{request++;for(let i=level+1;i<3;i++){selects[i].replaceChildren(new Option('请选择',''));selects[i].disabled=true;selects[i].closest('.form-field')?.querySelector('input')?.dispatchEvent(new Event('input'));}if(select.value&&level<2)void load(select.value,level+1);form.dataset.region=selects.filter(s=>s.value).map(s=>s.selectedOptions[0].textContent).join('');summary.textContent=form.dataset.region||'选择省 / 市 / 区';search.value='';search.dispatchEvent(new Event('input',{bubbles:true}));
          for(const name of ['latitude','longitude','mapAddress','address','doorDetail']){const input=form.elements.namedItem(name);if(input){input.value='';input.dispatchEvent(new Event('input',{bubbles:true}));}}
          form.dataset.coordinateAddress='';
        });}
      const error=node('button','form-error');error.type='button';error.hidden=true;regions.append(error);
      let retryParent='中国',retryLevel=0;
      async function load(parent,level){retryParent=parent;retryLevel=level;const version=++request;error.hidden=true;try{const result=await services.districts(parent);if(version!==request||!form.isConnected)return;if(result.status!=='1')throw new Error();const items=result.districts?.[0]?.districts||[];selects[level].replaceChildren(new Option('请选择',''),...items.map(item=>new Option(item.name,item.adcode)));selects[level].disabled=!items.length;enhanceSelect(selects[level]);}catch(_){if(version===request){error.textContent='地区加载失败，点击重试；也可直接搜索地点';error.hidden=false;}}}
      error.onclick=()=>load(retryParent,retryLevel);let opened=false;details.addEventListener('toggle',()=>{if(details.open&&!opened){opened=true;void load('中国',0);}});
      let timer;
      search.addEventListener('input',event=>{clearTimeout(timer);if(!search.value.trim()||event.isComposing)return;timer=setTimeout(()=>{if(form.isConnected)services.searchPlaces(form);},300);});
    }
  }
  function promptField(message,value='') {
    return new Promise(resolve=>{
      const dialog=node('dialog','dialog'),form=node('form','field-stack'),title=node('h2','','填写信息'),label=node('label','field'),actions=node('div','form-actions');
      const copy=/复制|支付链接/.test(message),cardType=message==='卡类型',secret=/密码/.test(message),card=/完整卡号/.test(message)&&!secret;
      const input=node(cardType?'select':'input',cardType?'select':'input');
      const name=cardType?'卡类型':secret?'支付密码':card?'完整卡号':message.length<20?message:'内容';
      label.append(document.createTextNode(name),input);title.textContent=copy?'复制信息':name;
      if(cardType){input.append(new Option('储蓄卡','储蓄卡'),new Option('信用卡','信用卡'));}
      else{input.type=secret?'password':'text';input.placeholder=message;input.readOnly=copy;input.maxLength=secret?6:card?19:1000;input.required=!copy&&!message.includes('规格格式');if(secret){input.inputMode='numeric';input.pattern='[0-9]{6}';}if(card){input.inputMode='numeric';input.pattern='[0-9]{16,19}';input.placeholder='请输入 16～19 位银行卡号，仅本次提交';}}
      input.value=value;
      const cancel=node('button','btn','取消'),submit=node('button','btn primary',copy?'完成':'确认');cancel.type='button';submit.type='submit';
      cancel.onclick=()=>dialog.close('cancel');actions.append(cancel,submit);form.append(title,label,actions);dialog.append(form);
      form.onsubmit=event=>{event.preventDefault();dialog.close('submit');};
      const previous=document.activeElement;dialog.onclose=()=>{const result=dialog.returnValue==='submit'?input.value:null;dialog.remove();previous?.focus?.();resolve(result);};
      document.body.append(dialog);scan(dialog);dialog.showModal();input.focus();if(copy)input.select();
    });
  }
  const observer=new MutationObserver(records=>{for(const record of records){for(const added of record.addedNodes)scan(added);for(const removed of record.removedNodes){if(removed.nodeType===1&&!removed.isConnected){const inputs=[...(removed.matches('input[type=file]')?[removed]:[]),...removed.querySelectorAll('input[type=file]')];inputs.forEach(input=>uploads.get(input)?.dispose());}}if(record.target.tagName==='SELECT')enhanceSelect(record.target);}});
  observer.observe(document.body,{childList:true,subtree:true});scan();
  document.addEventListener('input',event=>{
    const input=event.target;
    if(input.dataset.formEnhanced)feedback(input,input.dataset.fieldValidationFailed==='true'?validation(input):'');
  });
  document.addEventListener('invalid',e=>{if(e.target.dataset.fieldError){e.preventDefault();feedback(e.target,validation(e.target));}},true);
  document.addEventListener('submit',e=>{if(e.submitter?.formNoValidate)return;let invalid;for(const input of e.target.querySelectorAll('[data-field-error]')){const message=validation(input);feedback(input,message);if(message&&!invalid)invalid=input;}if(invalid){e.preventDefault();e.stopImmediatePropagation();invalid.focus();}},true);
  window.TakeoutForms={scan,highlight,feedback,uploads,validation,prompt:promptField,configure(value){services=value;scan();}};
})();
