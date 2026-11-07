const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
let chromium;
try { ({chromium}=require('playwright')); } catch(error) { if(error.code!=='MODULE_NOT_FOUND')throw error; }
const testUI=(name,body)=>test(name,{skip:!chromium && 'Playwright is required for browser interaction checks'},body);
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'../server/takeout-gateway/src/main/resources/static');
let browser;
before(async()=>{if(chromium)browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH});});
after(async()=>{await browser?.close();});
async function fixture(markup){const page=await browser.newPage();await page.setContent(`<style>:root{--line:#ddd;--ink:#342c26;--surface:#fff;--paper:#fff8f0;--muted:#6b6058;--accent:#b94c25;--accent-dark:#94391c;--red:#a32222}body{max-width:440px;padding:20px}input{box-sizing:border-box}</style><form>${markup}<button type="submit">保存</button></form>`);await page.addStyleTag({path:path.join(root,'forms.css')});await page.addScriptTag({path:path.join(root,'forms.js')});return page;}

testUI('floating labels survive filled values; errors appear on blur, clear while editing',async()=>{
 const page=await fixture('<label class="field">邮箱<input name="email" type="email" required placeholder="例如 name@example.com"></label>');
 const input=page.locator('[name=email]');await input.fill('invalid');
 assert.equal(await page.locator('.form-error').isVisible(),false);
 assert.equal(await page.locator('.floating-label').textContent(),'邮箱');
 assert.equal(await page.locator('.form-help').textContent(),'例如 name@example.com');
 await input.blur();assert.match(await page.locator('.form-error').textContent(),/完整邮箱/);
 await input.fill('name@example.com');assert.equal(await page.locator('.form-error').isVisible(),false);
 assert.equal(await page.locator('.floating-control').evaluate(el=>el.classList.contains('has-value')),true);
 await page.close();
});
testUI('phone uses one feedback row and clears the hint as soon as eleven digits match',async()=>{
 const page=await fixture('<label class="field">手机号<input name="phone" type="tel" required pattern="1[0-9]{10}" placeholder="请输入 11 位手机号"></label>');
 const input=page.locator('[name=phone]'),help=page.locator('.form-help'),error=page.locator('.form-error');
 await input.fill('1310013100');assert.equal(await help.isVisible(),true);assert.equal(await error.isVisible(),false);
 await input.blur();assert.equal(await help.isVisible(),false);assert.equal(await error.isVisible(),true);
 await input.fill('131001310');assert.equal(await help.isVisible(),false);assert.equal(await error.isVisible(),true);
 await input.fill('13100131000');assert.equal(await help.isVisible(),false);assert.equal(await error.isVisible(),false);
 await input.blur();assert.equal(await help.isVisible(),false);assert.equal(await error.isVisible(),false);
 await input.fill('1310013100');assert.equal(await help.isVisible(),true);assert.equal(await error.isVisible(),false);
 await input.blur();assert.equal(await help.isVisible(),false);assert.equal(await error.isVisible(),true);
 await page.close();
});
testUI('password help stays on one row and clears only when the field requirements match',async()=>{
 const page=await fixture('<label class="field">密码<input name="password" type="password" required minlength="6" maxlength="64" aria-describedby="authPasswordRules" placeholder="请输入 6 至 64 位密码"></label><p class="auth-rules" id="authPasswordRules">6 至 64 位，支持数字、英文字母和 !@#$%^&amp;*._+-=?</p><label class="field">确认密码<input name="confirmPassword" type="password" minlength="6" required placeholder="再次输入相同密码"></label>');
 const password=page.locator('[name=password]'),field=password.locator('..').locator('..'),help=field.locator('.form-help'),error=field.locator('.form-error');
 await password.fill('Abc');assert.equal(await help.isVisible(),true);assert.equal(await error.isVisible(),false);assert.equal(await page.locator('#authPasswordRules').isVisible(),false);
 await password.blur();assert.equal(await help.isVisible(),false);assert.equal(await error.isVisible(),true);
 await password.fill('Abcd');assert.equal(await help.isVisible(),false);assert.equal(await error.isVisible(),true);
 await password.fill('Abc123!');assert.equal(await help.isVisible(),false);assert.equal(await error.isVisible(),false);
 await password.fill('Abc123 ');assert.equal(await help.isVisible(),true);assert.equal(await error.isVisible(),false);await password.blur();assert.equal(await error.isVisible(),true);
 await password.fill('Abc123!');
 const confirm=page.locator('[name=confirmPassword]'),confirmation=confirm.locator('..').locator('..');
 await confirm.fill('Other1!');await confirm.blur();assert.equal(await confirmation.locator('.form-help').isVisible(),false);assert.equal(await confirmation.locator('.form-error').isVisible(),true);
 await confirm.fill('Abc123!');assert.equal(await confirmation.locator('.form-help').isVisible(),false);assert.equal(await confirmation.locator('.form-error').isVisible(),false);
 await page.close();
});
testUI('login password hides its hint when entered without applying new-password character rules',async()=>{
 const page=await fixture('<label class="field">密码<input name="password" type="password" autocomplete="current-password" required placeholder="请输入密码"></label>');
 await page.locator('input').fill('旧密码');assert.equal(await page.locator('.form-help').isVisible(),false);assert.equal(await page.locator('.form-error').isVisible(),false);
 await page.close();
});
testUI('searchable select preserves original value/index and highlights literal matches',async()=>{
 const options=Array.from({length:12},(_,i)=>`<option value="${i}">分类 ${i}</option>`).join('');
 const page=await fixture(`<label class="field">分类<select name="category">${options}</select></label>`);
 await page.getByRole('textbox').fill('分类 10');
 assert.equal(await page.locator('.form-options button').count(),1);assert.equal(await page.locator('mark').textContent(),'分类 10');
 await page.locator('.form-options button').click();assert.equal(await page.locator('select').inputValue(),'10');await page.close();
});
testUI('Enter creates deduplicated removable tags without submitting the form',async()=>{
 const page=await fixture('<label class="field">标签<input name="tag" value="新品"></label>');
 await page.evaluate(()=>{window.submits=0;document.querySelector('form').onsubmit=e=>{e.preventDefault();window.submits++;};});
 const input=page.getByRole('textbox');await input.fill('微辣');await input.press('Enter');await input.fill('微辣');await input.press('Enter');
 assert.equal(await page.locator('input[name=tag]').inputValue(),'新品,微辣');assert.equal(await page.evaluate(()=>window.submits),0);
 await page.getByRole('button',{name:'删除标签 新品'}).click();assert.equal(await page.locator('input[name=tag]').inputValue(),'微辣');await page.close();
});
testUI('image limits are enforced before upload; deleting an inflight file ignores its late result',async()=>{
 const page=await fixture('<label class="field">证据<input type="file" name="evidenceFiles" multiple data-max-files="2"></label>');
 const input=page.locator('input[type=file]');
 await input.setInputFiles({name:'bad.txt',mimeType:'text/plain',buffer:Buffer.from('not an image')});
 assert.match(await page.locator('.form-error').textContent(),/5MB/);assert.equal(await page.locator('.upload-row').count(),0);
 const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aA9sAAAAASUVORK5CYII=','base64');
 await input.setInputFiles({name:'proof.png',mimeType:'image/png',buffer:png});
 await page.evaluate(()=>{const item=document.querySelector('input[type=file]');window.uploadDone=TakeoutForms.uploads.get(item).send((file,progress,cancel)=>{progress(42);cancel(()=>{});return new Promise(resolve=>window.completeUpload=resolve);},()=>true);});
 assert.equal(await page.locator('progress').getAttribute('value'),'42');await page.getByRole('button',{name:'删除',exact:true}).click();
 const result=await page.evaluate(async()=>{window.completeUpload({url:'/uploads/proof.png'});return window.uploadDone;});
 assert.deepEqual(result,[]);assert.equal(await page.locator('.upload-row').count(),0);await page.close();
});
testUI('region cascade clears children and rejects a stale city response',async()=>{
 const page=await fixture('<label class="field">搜索位置<input name="locationKeyword"></label><div data-location-results></div>');
 await page.evaluate(()=>{TakeoutForms.configure({districts:parent=>parent==='中国'?Promise.resolve({status:'1',districts:[{districts:[{name:'省甲',adcode:'110000'},{name:'省乙',adcode:'120000'}]}]}):new Promise(resolve=>{window.responses||={};window.responses[parent]=resolve;}),searchPlaces:()=>{},searchStores:()=>[]});});
 await page.locator('summary').click();await page.getByLabel('省 / 自治区 / 直辖市',{exact:true}).selectOption('110000');
 await page.getByLabel('省 / 自治区 / 直辖市',{exact:true}).selectOption('120000');
 await page.evaluate(()=>{responses['120000']({status:'1',districts:[{districts:[{name:'市乙',adcode:'120100'}]}]});responses['110000']({status:'1',districts:[{districts:[{name:'旧市甲',adcode:'110100'}]}]});});
 assert.match(await page.getByLabel('城市',{exact:true}).textContent(),/市乙/);assert.doesNotMatch(await page.getByLabel('城市',{exact:true}).textContent(),/旧市甲/);await page.close();
});
