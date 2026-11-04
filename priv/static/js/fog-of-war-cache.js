import {PAGE_PREFIX, binaryRecord, validSnapshot, encodeSnapshot, decodeSnapshot} from './fog-of-war-codec'
import {openIndexedDBStore, openLocalStore, openMemoryStore, localRecords} from './fog-of-war-storage'
import {importBundle} from './fog-of-war-import'
const OPEN='fog-of-war:open:',MAINTENANCE='fog-of-war:cache-maintenance'

export function createFogOfWarCache(build) {
  let currentPath=location.pathname,heldPath,releasePath,lockError=null,store,index=new Map(),writes=Promise.resolve(),protection=Promise.resolve(),storageReason=''
  const locks=navigator.locks,supported=Boolean(locks?.request&&locks?.query),listeners=new Set()
  const channel=typeof BroadcastChannel!=='undefined'?new BroadcastChannel('fog-of-war:cache'):null
  const changed=()=>listeners.forEach(fn=>fn())
  const compatible=record=>validMetadata(record)&&record.build===build
  const validMetadata=record=>record?.schema===1&&typeof record.path==='string'&&Number.isFinite(Date.parse(record.savedAt))
  const newer=(a,b)=>Number(a?.build===build)-Number(b?.build===build)||Date.parse(a?.savedAt)-Date.parse(b?.savedAt)
  const reload=async()=>{index=new Map((await store.list()).map(row=>[row.key,row]))}
  const notify=()=>{changed();channel?.postMessage('changed')}
  const legacy=()=>{try{return localRecords()}catch(_){return []}}
  const locked=job=>supported&&!lockError?locks.request(MAINTENANCE,job):job()
  const enqueue=job=>{
    const result=writes.then(async()=>{await ready;return job()})
    writes=result.catch(()=>{});return result
  }
  const migrate=async()=>{
    if(store.kind!=='indexedDB')return
    await locked(async()=>{
      const rows=legacy().filter(row=>row.valid).sort((a,b)=>newer(b.record,a.record))
      const seen=new Set()
      for(const row of rows){
        if(seen.has(row.path))continue
        seen.add(row.path)
        try {
          const record=binaryRecord(row.record)
          // Validate legacy compressed bytes before deleting their only existing copy.
          await decodeSnapshot(record)
          await store.write([{...record,source:record.source||'legacy'}],{replace:(existing,incoming)=>!existing||newer(incoming,existing)>0})
          // Compare again: never remove a value another tab replaced during migration.
          for(const old of rows.filter(item=>item.path===row.path)){
            if(localStorage.getItem(old.key)===old.raw)localStorage.removeItem(old.key)
          }
        }catch(error){storageReason=`Legacy migration incomplete: ${error.name}`}
      }
    })
    await reload()
  }
  const ready=(async()=>{
    try{store=await openIndexedDBStore()}
    catch(error){
      storageReason=`IndexedDB unavailable: ${error.name}`
      try{store=openLocalStore()}catch(localError){store=openMemoryStore();storageReason+=`; localStorage unavailable: ${localError.name}; cache lasts only in this document`}
    }
    await reload();await migrate();changed()
    return store.kind
  })()
  // Observe initialization errors without creating an unhandled rejection in online-only apps.
  ready.catch(error=>{storageReason=`Cache initialization failed: ${error.message}`;changed()})

  const entries=()=>{
    const rows=[...index.values()]
    if(store?.kind==='indexedDB'){
      for(const row of legacy()){
        const existing=rows.find(entry=>entry.path===row.path)
        if(!existing||row.valid&&newer(row.record,existing.snapshot)>0)rows.push({...row,snapshot:row.record,legacy:true})
      }
    }
    return rows.sort((a,b)=>a.path.localeCompare(b.path))
  }
  const find=url=>{
    if(url.origin!==location.origin||url.search)return null
    return entries().filter(row=>row.valid&&row.path===url.pathname&&compatible(row.snapshot)).sort((a,b)=>newer(b.snapshot,a.snapshot))[0]?.snapshot||null
  }
  const getRecord=async path=>{
    await ready
    const row=entries().filter(row=>row.valid&&row.path===path).sort((a,b)=>newer(b.snapshot,a.snapshot))[0]
    if(row?.legacy||store.kind==='localStorage')return row?.record || null
    return store.get(path)
  }
  function protect(path){
    currentPath=path
    if(!supported)return Promise.resolve()
    protection=protection.then(()=>locks.request(MAINTENANCE,async()=>{
      if(heldPath===path)return
      let release,acquired,failed
      const gate=new Promise((resolve,reject)=>{acquired=resolve;failed=reject})
      const lifetime=new Promise(resolve=>{release=resolve})
      locks.request(OPEN+path,{mode:'shared'},()=>{acquired();return lifetime}).catch(failed)
      await gate;releasePath?.();releasePath=release;heldPath=path
    })).catch(error=>{lockError=error})
    return protection
  }
  const openPaths=async()=>{
    if(!supported||lockError)return new Set([currentPath])
    const {held}=await locks.query();return new Set(held.filter(lock=>lock.name.startsWith(OPEN)).map(lock=>lock.name.slice(OPEN.length)))
  }
  const removeLegacy=paths=>{
    for(const row of legacy())if(row.valid&&paths.includes(row.path)&&localStorage.getItem(row.key)===row.raw)localStorage.removeItem(row.key)
  }
  channel?.addEventListener('message',()=>{enqueue(async()=>{await reload();changed()}).catch(()=>{})})
  window.addEventListener('storage',event=>{
    if(event.key===null||event.key.startsWith(PAGE_PREFIX))enqueue(async()=>{await reload();await migrate();changed()}).catch(()=>{})
  })
  const cache={
    ready,protect,find,getRecord,
    async flush(){await ready;await writes},
    save(snapshot,{protectRoute=true}={}){
      return enqueue(async()=>{
        if(protectRoute)await protect(snapshot.path)
        const record=await encodeSnapshot({...snapshot,source:snapshot.source||'live'})
        if(!validSnapshot(record))throw new Error('Invalid Fog of War snapshot')
        await locked(async()=>{await store.write([record]);if(store.kind==='indexedDB')removeLegacy([record.path])})
        await reload();notify();return record
      })
    },
    async decode(snapshot){return decodeSnapshot(typeof snapshot?.html==='string'||snapshot?.htmlGzip?snapshot:await getRecord(snapshot.path))},
    async load(url){await ready;const metadata=find(url);if(!metadata)return null;const record=await getRecord(url.pathname);return compatible(record)?decodeSnapshot(record):null},
    async inspect(){
      await ready;await protection
      const open=await openPaths(),rows=entries().map(row=>({...row,open:open.has(row.path)||row.path===currentPath}))
      return {rows,bytes:rows.reduce((sum,row)=>sum+row.bytes,0),backend:store.kind,storageReason,
        canClear:supported&&!lockError,reason:lockError?.message||'Safe clearing requires the browser Web Locks API.'}
    },
    remove(path){return enqueue(async()=>{await locked(async()=>{await store.remove([path]);removeLegacy([path])});await reload();notify()})},
    clearUnused(){
      return enqueue(async()=>{
        await protection
        if(!supported||lockError)throw new Error('Safe clearing is unavailable in this browser.')
        const result=await locks.request(MAINTENANCE,async()=>{
          const open=await openPaths();open.add(currentPath)
          const rows=entries(),remove=rows.filter(row=>row.valid&&!open.has(row.path))
          const paths=[...new Set(remove.map(row=>row.path))]
          await store.remove(paths);removeLegacy(paths)
          return {removed:paths.length,bytes:remove.reduce((sum,row)=>sum+row.bytes,0),protectedCount:new Set(rows.filter(row=>row.valid&&open.has(row.path)).map(row=>row.path)).size,unreadable:rows.filter(row=>!row.valid).length}
        })
        await reload();notify();return result
      })
    },
    importBundle(input,opts){
      return importBundle({build,ready,kind:()=>store.kind,find:path=>find(new URL(path,location.origin)),progress:id=>store.progress(id),
        commit:(records,progress)=>enqueue(async()=>{
          const result=await locked(()=>store.write(records,{progress,replace:(existing,incoming)=>!compatible(existing)||existing.source==='bundle'&&Date.parse(existing.savedAt)<Date.parse(incoming.savedAt)}))
          await reload();notify();return result
        })},input,opts)
    },
    subscribe(fn){listeners.add(fn);return ()=>listeners.delete(fn)},
  }
  return cache
}
