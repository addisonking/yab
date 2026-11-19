// Executed only in the selected extension's own Chromium service worker.
static NSString* ExtensionWorkerShim = @R"JS((()=>{
 if(globalThis.__yabWKBridge)return;
 const native=chrome, slots=new Map(), waiting=new Map(), ports=new Map(), storageAccess=new Map();let serial=0;
 const event=()=>{const listeners=new Set();return {addListener:f=>listeners.add(f),removeListener:f=>listeners.delete(f),hasListener:f=>listeners.has(f),hasListeners:()=>!!listeners.size,dispatch:(...a)=>{for(const f of listeners)f(...a)}}};
 const call=(op,tab,args)=>new Promise((resolve,reject)=>{const id=String(++serial);const timeout=setTimeout(()=>{waiting.delete(id);reject(Error('WebKit bridge timed out'))},12000);waiting.set(id,{resolve,reject,timeout});__yabExtensionBridge(JSON.stringify({id,op,tab,args}))});
 const callback=(promise,cb)=>{if(typeof cb!=='function')return promise;promise.then(x=>cb(x),e=>{try{Object.defineProperty(native.runtime,'lastError',{configurable:true,value:{message:String(e.message||e)}});cb()}finally{delete native.runtime.lastError}})};
 const virtual=id=>slots.has(id), orig={};
 for(const key of ['sendMessage','connect','get','query'])orig[key]=native.tabs[key].bind(native.tabs);
 native.tabs.sendMessage=(id,message,options,cb)=>{if(typeof options==='function'){cb=options;options={}};return virtual(id)?callback(call('tabs.sendMessage',id,{message,options:options||{}}),cb):orig.sendMessage(id,message,options,cb)};
 native.tabs.get=(id,cb)=>virtual(id)?callback(Promise.resolve(slots.get(id).tab),cb):orig.get(id,cb);
 native.tabs.query=(query,cb)=>callback(orig.query(query).then(rows=>rows.concat([...slots.values()].map(x=>x.tab).filter(t=>Object.entries(query).every(([k,v])=>k==='url'?[v].flat().some(p=>new RegExp('^'+p.replace(/[.+?^${}()|[\]\\]/g,'\\$&').replace(/\*/g,'.*')+'$').test(t.url)):k==='currentWindow'?true:t[k]===v)))),cb);
 const makePort=(id,name,sender)=>{const p={name,sender,onMessage:event(),onDisconnect:event(),postMessage:m=>call('port.message',sender.tab.id,{port:id,message:m,options:{frameId:sender.frameId,documentId:sender.documentId}}),disconnect:()=>{call('port.disconnect',sender.tab.id,{port:id,options:{frameId:sender.frameId,documentId:sender.documentId}});ports.delete(id);p.onDisconnect.dispatch(p)}};ports.set(id,p);return p};
 native.tabs.connect=(id,info={})=>{if(!virtual(id))return orig.connect(id,info);const key='bg-'+(++serial),p=makePort(key,info.name||'',{tab:slots.get(id).tab,frameId:info.frameId||0,documentId:info.documentId});call('tabs.connect',id,{port:key,info});return p};
 if(native.scripting)for(const method of ['executeScript','insertCSS','removeCSS']){const old=native.scripting[method].bind(native.scripting);native.scripting[method]=(details,cb)=>{if(!virtual(details?.target?.tabId))return old(details,cb);const args={...details};if(args.func){args.function=String(args.func);delete args.func}return callback(call('scripting.'+method,details.target.tabId,args),cb)}}
 // CDP evaluation is a trusted extension context. Never let it bypass a
 // storage area's content-script access level. Each operation receives the
 // native profile's live access levels; later worker changes update this map.
 if(native.storage)for(const area of ['local','sync','session','managed']){const old=native.storage[area]?.setAccessLevel?.bind(native.storage[area]);if(old)native.storage[area].setAccessLevel=(options,cb)=>callback(old(options).then(value=>{storageAccess.set(area,options.accessLevel);return value}),cb)}
 if(native.storage?.onChanged)native.storage.onChanged.addListener((changes,area)=>{if(storageAccess.get(area)==='TRUSTED_AND_UNTRUSTED_CONTEXTS')__yabExtensionBridge(JSON.stringify({op:'storage.changed',changes,area}))});
 if(native.declarativeNetRequest)for(const method of ['updateDynamicRules','updateSessionRules','updateEnabledRulesets']){const old=native.declarativeNetRequest[method]?.bind(native.declarativeNetRequest);if(old)native.declarativeNetRequest[method]=(...args)=>{const cb=typeof args.at(-1)==='function'?args.pop():null;return callback(old(...args).then(x=>{__yabExtensionBridge(JSON.stringify({op:'dnr.changed'}));return x}),cb)}}
 globalThis.__yabWKBridge={
  reply(id,value,error){const p=waiting.get(id);if(!p)return;clearTimeout(p.timeout);waiting.delete(id);error?p.reject(Error(error)):p.resolve(value)},
  async invoke(op,args,sender,access){
   if(access)for(const [area,allowed]of Object.entries(access))storageAccess.set(area,allowed?'TRUSTED_AND_UNTRUSTED_CONTEXTS':'TRUSTED_CONTEXTS');
   if(sender)slots.set(sender.tab.id,sender);
   if(op==='runtime.sendMessage')return new Promise((resolve,reject)=>{
    const onMessage=native.runtime.onMessage;
    if(!onMessage.hasListeners()){reject(Error('Receiving end does not exist'));return}
    let answered=false,timeout;
    const settle=(complete,value)=>{if(answered)return;answered=true;clearTimeout(timeout);complete(value)};
    const done=value=>settle(resolve,value??null);
    const results=onMessage.dispatch(args[0],sender,done)?.results||[];
    const promises=results.filter(value=>value&&typeof value.then==='function');
    for(const promise of promises)Promise.resolve(promise).then(done,error=>settle(reject,error));
    if(answered)return;
    // A listener can handle a notification without sending a response.
    if(!results.includes(true)&&!promises.length){done(null);return}
    timeout=setTimeout(()=>settle(reject,Error('Background did not reply')),11000);
   });
   if(op==='runtime.connect'){const p=makePort(args.port,args.name||'',sender);native.runtime.onConnect.dispatch(p);return null}
   if(op==='port.message'){const p=ports.get(args.port);if(!p)throw Error('Port is disconnected');p.onMessage.dispatch(args.message,p);return null}
   if(op==='port.disconnect'){const p=ports.get(args.port);ports.delete(args.port);p?.onDisconnect.dispatch(p);return null}
   if(op==='forget'){slots.delete(args);for(const [id,p]of ports)if(p.sender?.tab?.id===args){ports.delete(id);p.onDisconnect.dispatch(p)}return null}
   if(op.startsWith('storage.')){const [_,area,method]=op.split('.');if(!['local','sync','session','managed'].includes(area)||!['get','set','remove','clear','getBytesInUse'].includes(method))throw Error('Unsupported storage call');if(storageAccess.get(area)!=='TRUSTED_AND_UNTRUSTED_CONTEXTS')throw Error('Storage is unavailable to content scripts in this profile');return await native.storage[area][method](...args)??null}
   if(op.startsWith('i18n.')){const method=op.slice(5);if(!['getAcceptLanguages','detectLanguage'].includes(method))throw Error('Unsupported i18n call');return await native.i18n[method](...args)}
   if(op==='dnr.snapshot'){const d=native.declarativeNetRequest;if(!d)return {enabled:[],dynamic:[],session:[]};return {enabled:await d.getEnabledRulesets(),dynamic:await d.getDynamicRules(),session:await d.getSessionRules()}}
   throw Error('Unsupported WebKit extension operation');
  }
 };
})())JS";
