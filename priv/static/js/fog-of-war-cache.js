import {PAGE_PREFIX, isExpired, recordKey, binaryRecord, validSnapshot, encodeSnapshot, decodeSnapshot} from './fog-of-war-codec'
import {openIndexedDBStore, openLocalStore, openMemoryStore, localRecords} from './fog-of-war-storage'
import {importBundle} from './fog-of-war-import'
const OPEN='fog-of-war:open:',MAINTENANCE='fog-of-war:cache-maintenance'

export function createFogOfWarCache(build) {
  let currentPath=location.pathname,heldPath,releasePath,lockError=null,store,index=new Map(),writes=Promise.resolve(),protection=Promise.resolve(),storageReason=''
  let userId = null, identityVersion = 0
  const locks=navigator.locks,supported=Boolean(locks?.request&&locks?.query),listeners=new Set()
  const channel=typeof BroadcastChannel!=='undefined'?new BroadcastChannel('fog-of-war:cache'):null
  const changed=()=>listeners.forEach(fn=>fn())
  const compatible=record=>validMetadata(record)&&record.build===build&&!isExpired(record)
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
        if(seen.has(recordKey(row.path,row.record.userId)))continue
        seen.add(recordKey(row.path,row.record.userId))
        try {
          const record=binaryRecord(row.record)
          // Validate legacy compressed bytes before deleting their only existing copy.
          await decodeSnapshot(record)
          await store.write([{...record,source:record.source||'legacy'}],{replace:(existing,incoming)=>!existing||newer(incoming,existing)>0})
          // Compare again: never remove a value another tab replaced during migration.
          for(const old of rows.filter(item=>recordKey(item.path,item.record.userId)===recordKey(row.path,row.record.userId))){
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
        const existing=rows.find(entry=>recordKey(entry.path,entry.snapshot?.userId)===recordKey(row.path,row.record?.userId))
        if(!existing||row.valid&&newer(row.record,existing.snapshot)>0)rows.push({...row,snapshot:row.record,legacy:true})
      }
    }
    return rows.sort((a,b)=>a.path.localeCompare(b.path))
  }
  const visible = row => !row.snapshot?.userId || row.snapshot.userId === userId
  const select = (path, identity) => entries()
    .filter(row => row.valid && row.path === path && compatible(row.snapshot) &&
      (!row.snapshot.userId || row.snapshot.userId === identity))
    .sort((a,b) => Number(Boolean(b.snapshot.userId)) - Number(Boolean(a.snapshot.userId)) ||
      newer(b.snapshot,a.snapshot))[0]
  const find = (url, identity = userId) => {
    if (url.origin !== location.origin || url.search) return null
    return select(url.pathname, identity)?.snapshot || null
  }
  const getRecord = async (path, identity = userId, exact = false) => {
    await ready
    const row = exact
      ? entries().find(row => row.valid && row.path === path && (row.snapshot.userId || null) === identity)
      : select(path, identity)
    if (!row) return null
    if (row.legacy || store.kind === 'localStorage') return row.record || null
    return store.get(recordKey(path, row.snapshot.userId))
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
    for(const row of legacy())if(row.valid&&paths.includes(recordKey(row.path,row.record.userId))&&localStorage.getItem(row.key)===row.raw)localStorage.removeItem(row.key)
  }
  channel?.addEventListener('message',()=>{enqueue(async()=>{await reload();changed()}).catch(()=>{})})
  window.addEventListener('storage',event=>{
    if(event.key===null||event.key.startsWith(PAGE_PREFIX))enqueue(async()=>{await reload();await migrate();changed()}).catch(()=>{})
  })
  const cache={
    ready,protect,find,getRecord,
    setIdentity(identity) {
      if (userId === identity) return
      userId = identity
      identityVersion++
      changed()
    },
    identityVersion: () => identityVersion,
    async flush(){await ready;await writes},
    save(snapshot,{protectRoute=true}={}){
      return enqueue(async()=>{
        if(protectRoute)await protect(snapshot.path)
        const record=await encodeSnapshot({...snapshot,source:snapshot.source||'live'})
        if(!validSnapshot(record))throw new Error('Invalid Fog of War snapshot')
        await locked(async()=>{await store.write([record]);if(store.kind==='indexedDB')removeLegacy([recordKey(record.path,record.userId)])})
        await reload();notify();return record
      })
    },
    async decode(snapshot) {
      const version = identityVersion
      if (isExpired(snapshot) || !visible({snapshot})) return null
      const record = await getRecord(snapshot.path, snapshot.userId || null, true)
      const decoded = record && !isExpired(record) ? await decodeSnapshot(record) : null
      return version === identityVersion ? decoded : null
    },
    async load(url) {
      const version = identityVersion
      await ready
      if (!find(url)) return null
      const record = await getRecord(url.pathname)
      const decoded = compatible(record) && await decodeSnapshot(record)
      return version === identityVersion && !isExpired(decoded) ? decoded || null : null
    },
    async inspect(){
      await ready;await protection
      const open=await openPaths(),rows=entries().filter(row=>visible(row)&&!isExpired(row.snapshot)).map(row=>({...row,open:open.has(row.path)||row.path===currentPath}))
      return {rows,bytes:rows.reduce((sum,row)=>sum+row.bytes,0),backend:store.kind,storageReason,
        canClear:supported&&!lockError,reason:lockError?.message||'Safe clearing requires the browser Web Locks API.'}
    },
    remove(path){return enqueue(async()=>{await locked(async()=>{const key=recordKey(path,userId);await store.remove([key]);removeLegacy([key])});await reload();notify()})},
    pruneExpired() {
      return enqueue(async () => {
        // Lookup checks expiry even when safe cross-tab deletion is unavailable.
        if (!supported || lockError || !entries().some(row => isExpired(row.snapshot))) return
        const removed = await locked(async () => {
          await reload()
          const keys = [...index.values()].filter(row => row.valid && isExpired(row.snapshot))
            .map(row => recordKey(row.path, row.snapshot.userId))
          if (!keys.length) return false
          await store.remove(keys)
          removeLegacy(keys)
          return true
        })
        if (removed) { await reload(); notify() }
      })
    },
    clearUnused(){
      return enqueue(async()=>{
        await protection
        if(!supported||lockError)throw new Error('Safe clearing is unavailable in this browser.')
        const result=await locks.request(MAINTENANCE,async()=>{
          const open=await openPaths();open.add(currentPath)
          const rows=entries().filter(visible),remove=rows.filter(row=>row.valid&&!open.has(row.path))
          const paths=[...new Set(remove.map(row=>recordKey(row.path,row.snapshot.userId)))]
          await store.remove(paths);removeLegacy(paths)
          return {removed:paths.length,bytes:remove.reduce((sum,row)=>sum+row.bytes,0),protectedCount:new Set(rows.filter(row=>row.valid&&open.has(row.path)).map(row=>row.path)).size,unreadable:rows.filter(row=>!row.valid).length}
        })
        await reload();notify();return result
      })
    },
    importBundle(input,opts){
      return importBundle({build,ready,kind:()=>store.kind,find:path=>find(new URL(path,location.origin),null),progress:id=>store.progress(id),
        commit:(records,progress)=>enqueue(async()=>{
          const result=await locked(()=>store.write(records,{progress,replace:(existing,incoming)=>!compatible(existing)||existing.source==='bundle'&&Date.parse(existing.savedAt)<Date.parse(incoming.savedAt)}))
          await reload();notify();return result
        })},input,opts)
    },
    subscribe(fn){listeners.add(fn);return ()=>listeners.delete(fn)},
  }
  return cache
}
