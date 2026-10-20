const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const context=vm.createContext({});
vm.runInContext(fs.readFileSync('server/takeout-gateway/src/main/resources/static/location.js','utf8'),context);
const {devicePosition,coordinates,place}=context.TakeoutLocation;
test('HTTP never requests precise device location',async()=>{
  let called=false;
  await assert.rejects(devicePosition({isSecureContext:false,navigator:{geolocation:{getCurrentPosition(){called=true;}}}}),/HTTPS/);
  assert.equal(called,false);
});
test('secure device location validates coordinates and requests fresh position',async()=>{
  const result=await devicePosition({isSecureContext:true,navigator:{geolocation:{getCurrentPosition(ok,fail,options){assert.equal(options.timeout,12000);assert.equal(options.maximumAge,0);ok({coords:{latitude:30.5,longitude:114.3,accuracy:25}});}}}});
  assert.equal(result.latitude,30.5);assert.equal(result.longitude,114.3);
  assert.equal(coordinates('',''),null);assert.equal(coordinates('NaN',30),null);assert.equal(coordinates(0,0),null);assert.equal(coordinates(181,30),null);assert.equal(coordinates('114.3','30.5').latitude,30.5);
});
test('permission denial, unavailable position and timeout each have useful feedback',async()=>{
  for(const [code,message] of [[1,/权限/],[2,/定位服务/],[3,/超时/]]){
    await assert.rejects(devicePosition({isSecureContext:true,navigator:{geolocation:{getCurrentPosition(ok,fail){fail({code});}}}}),message);
  }
});
test('manual locations use actual POI coordinates and normalize municipality names',()=>{
  const beijing=place({pname:'北京市',cityname:'北京市',adname:'海淀区',address:'中关村大街15号',name:'中关村广场',location:'116.312,39.982'});
  assert.equal(beijing.address,'北京市海淀区中关村大街15号中关村广场');
  assert.equal(beijing.longitude,116.312);assert.equal(beijing.latitude,39.982);
  const wuhan=place({pname:'湖北省',cityname:'武汉市',adname:'洪山区',address:[],name:'光谷广场',location:' 114.405 , 30.506 '});
  assert.equal(wuhan.address,'湖北省武汉市洪山区光谷广场');assert.equal(wuhan.longitude,114.405);
});
test('manual selection rejects missing, out-of-range and malformed POI coordinates',()=>{
  for(const location of [undefined,'','0,0','181,30','114,91','114,30,20','NaN,30']) assert.equal(place({name:'地点',location}),null);
  assert.equal(place({location:'114,30'}),null);assert.equal(place(null),null);
});
