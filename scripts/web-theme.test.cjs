const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
let chromium,browser;
try{({chromium}=require('playwright'));}catch(error){if(error.code!=='MODULE_NOT_FOUND')throw error;}
before(async()=>{if(chromium)browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH});});
after(async()=>{await browser?.close();});
const tokens={paper:'bg_primary',surface:'bg_card',input:'input',ink:'text_primary',muted:'text_secondary',line:'divider',accent:'primary','accent-dark':'tag_text','accent-soft':'tag_bg','on-accent':'on_primary',green:'success','green-soft':'success_light',warning:'warning','warning-soft':'warning_light',red:'error','red-soft':'error_light','control-border':'control_border'};
const luminance=color=>{
 const values=color.startsWith('#')?color.slice(1).match(/../g).map(v=>parseInt(v,16)):color.match(/[\d.]+/g).slice(0,3).map(Number);
 return values.map(v=>v/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);
};
const contrast=(a,b)=>{const values=[luminance(a),luminance(b)].sort((x,y)=>y-x);return (values[0]+.05)/(values[1]+.05);};

test('web and native semantic palettes agree and text retains contrast in both themes',()=>{
 const css=fs.readFileSync(path.join(root,'web/theme.css'),'utf8');
 for(const [index,mode] of ['base','dark'].entries()){
  const body=css.matchAll(/(?:^:root|\[data-theme="dark"\])\s*\{([^}]+)\}/gm);
  const vars=Object.fromEntries([...body][index][1].matchAll(/--([\w-]+):\s*(#[\da-f]+)/gi).map(m=>[m[1],m[2]]));
  const native=Object.fromEntries(JSON.parse(fs.readFileSync(path.join(root,`entry/src/main/resources/${mode}/element/color.json`),'utf8')).color.map(item=>[item.name,item.value]));
  for(const [web,app] of Object.entries(tokens))assert.equal(vars[web].toUpperCase(),native[app].toUpperCase(),`${mode}: ${web}`);
  for(const [fg,bg] of [['ink','paper'],['muted','surface'],['muted','input'],['on-accent','accent'],['accent-dark','accent-soft'],['red','red-soft'],['green','green-soft'],['warning','warning-soft']])assert.ok(contrast(vars[fg],vars[bg])>=4.5,`${mode}: ${fg} on ${bg}`);
  assert.ok(contrast(vars['control-border'],vars.input)>=3,`${mode}: control outline`);
 }
});

for(const theme of ['light','dark'])test(`${theme}: real shared controls retain target size, contrast, focus and form state`,{skip:!chromium&&'Playwright is required'},async()=>{
 const page=await browser.newPage({viewport:{width:375,height:812},reducedMotion:'reduce'});
 try{
  await page.setContent(`<html data-theme="${theme}"><body><main class="main"><section class="page-panel"><h1>订单与地址</h1><form><label class="field">邮箱<input class="input" name="email" type="email" placeholder="例如 name@example.com" required></label><div class="form-actions"><button class="btn">取消</button><button class="btn primary" type="submit">保存</button></div></form></section></main></body></html>`);
  for(const file of ['theme.css','app.css','forms.css'])await page.addStyleTag({path:path.join(root,'web',file)});
  await page.addScriptTag({path:path.join(root,'web/forms.js')});
  const metrics=await page.evaluate(()=>{
   const button=document.querySelector('.btn.primary'),input=document.querySelector('input'),card=document.querySelector('.page-panel');
   const b=getComputedStyle(button),i=getComputedStyle(input),c=getComputedStyle(card);
   return {button:{fg:b.color,bg:b.backgroundColor,radius:b.borderRadius,height:button.getBoundingClientRect().height},input:{radius:i.borderRadius,font:i.fontSize,height:input.getBoundingClientRect().height},card:{radius:c.borderRadius},overflow:document.documentElement.scrollWidth>innerWidth};
  });
  assert.ok(contrast(metrics.button.fg,metrics.button.bg)>=4.5);
  assert.ok(metrics.button.height>=44);assert.ok(metrics.input.height>=52);
  assert.equal(metrics.button.radius,'14px');assert.equal(metrics.input.radius,'14px');assert.equal(metrics.card.radius,'18px');
  assert.equal(metrics.input.font,'16px');assert.equal(metrics.overflow,false);
  await page.locator('input').fill('invalid');await page.locator('input').blur();
  assert.equal(await page.locator('.form-error').isVisible(),true);
  await page.locator('input').fill('person@example.com');assert.equal(await page.locator('.form-error').isVisible(),false);
  await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(()=>parseFloat(getComputedStyle(document.activeElement).outlineWidth)>=2),true);
  await page.emulateMedia({reducedMotion:'reduce'});
  assert.equal(await page.locator('.btn.primary').evaluate(el=>getComputedStyle(el).transitionDuration),'0s');
 }finally{await page.close();}
});
