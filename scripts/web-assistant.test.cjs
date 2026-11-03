const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const fixture=fs.readFileSync('scripts/web-browse.test.cjs','utf8');
const browser=new Function('require',fixture.slice(0,fixture.indexOf('const cardCount='))+';return browser;')(require);
function chat(options={}){
  const b=browser('0',options);b.state.page='assistant';
  const form=b.element('assistantForm'),submit={disabled:false,isConnected:true,textContent:'发送'},preset={disabled:false};
  form.dataset.form='assistant';form.elements={question:{value:'我的订单到哪了',focus(){}}};
  form.querySelector=()=>submit;form.querySelectorAll=()=>[preset];
  b.context.document.querySelectorAll=selector=>selector==='#app form[data-form]'?[form]:[];
  b.bindForms();
  const send=()=>{form.formData={question:form.elements.question.value};return form.onsubmit({preventDefault(){},submitter:submit});};
  return {...b,form,submit,preset,send};
}
test('preset questions use the form submission path and cannot submit twice while waiting',async()=>{
  let finish;const b=chat({onRequest(path){if(path==='/api/assistant/chat')return new Promise(resolve=>{finish=()=>resolve({ok:true,status:200,json:async()=>({code:200,data:{answer:'请在订单页查看进度'}})});});}});
  b.renderShell();assert.match(b.element('nav').innerHTML,/auth-icons\.svg\?v=20261102-headset#headset/);
  await b.renderPage();assert.equal(b.element('app').classes.has('assistant-page'),true);
  assert.equal((b.element('app').innerHTML.match(/data-action="assistant-question"/g)||[]).length,6);
  let pending;b.form.requestSubmit=()=>{pending=b.send();};
  await b.handleAction('assistant-question','我的订单到哪了');
  assert.equal(b.submit.disabled,true);assert.equal(b.preset.disabled,true);assert.equal(b.form.elements.question.readOnly,true);
  await b.handleAction('assistant-question','余额还有多少');
  assert.equal(b.calls.filter(call=>call.path==='/api/assistant/chat').length,1);
  assert.equal(b.form.elements.question.value,'我的订单到哪了');
  finish();await pending;
  assert.equal(b.state.assistantHistory.length,2);
  assert.match(b.element('chatHistory').innerHTML,/请在订单页查看进度/);
  assert.equal(b.form.elements.question.value,'');assert.equal(b.submit.disabled,false);assert.equal(b.preset.disabled,false);
  b.state.page='cart';await b.renderPage();assert.equal(b.element('app').classes.has('assistant-page'),false);
});
test('failed replies keep the draft for retry and do not duplicate history',async()=>{
  const b=chat({onRequest(path){if(path==='/api/assistant/chat')return {ok:false,status:503,json:async()=>({code:503,message:'请稍后重试'})};}});
  await b.send();
  assert.equal(b.form.elements.question.value,'我的订单到哪了');assert.equal(b.state.assistantHistory.length,0);
  assert.equal(b.submit.disabled,false);assert.equal(b.form.elements.question.readOnly,false);
  b.form.elements.question.value='   ';await b.send();assert.equal(b.calls.filter(c=>c.path==='/api/assistant/chat').length,1);
});
test('a delayed reply cannot restore another account’s chat history',async()=>{
  let finish;const b=chat({onRequest(path){if(path==='/api/assistant/chat')return new Promise(resolve=>{finish=()=>resolve({ok:true,status:200,json:async()=>({code:200,data:{answer:'旧账号的私密回复'}})});});}});
  const pending=b.send();b.resetAccountState();finish();await pending;
  assert.equal(b.state.assistantHistory.length,0);assert.doesNotMatch(b.element('chatHistory').innerHTML,/旧账号的私密回复/);
});
