import {DATABASE, PAGE_PREFIX, describeRecord, stringifyLegacy, validSnapshot} from './fog-of-war-codec'

const requestResult = request => new Promise((resolve,reject) => {
  request.onsuccess = () => resolve(request.result)
  request.onerror = () => reject(request.error)
})
const done = transaction => new Promise((resolve,reject) => {
  transaction.oncomplete = () => resolve()
  transaction.onabort = () => reject(transaction.error || new Error('Storage transaction aborted'))
  transaction.onerror = () => {} // onabort reports the final transaction result.
})

export async function openIndexedDBStore() {
  const db = await new Promise((resolve,reject) => {
    let abandoned = false
    const request = indexedDB.open(DATABASE,1)
    request.onupgradeneeded = () => {
      for (const name of ['pages','metadata','imports']) {
        if (!request.result.objectStoreNames.contains(name)) request.result.createObjectStore(name,{keyPath:name==='imports'?'id':'path'})
      }
    }
    request.onblocked = () => { abandoned=true;reject(new Error('IndexedDB opening blocked by another document')) }
    request.onerror = () => reject(request.error)
    request.onsuccess = () => { if(abandoned)request.result.close();else resolve(request.result) }
  })
  db.onversionchange = () => db.close()
  try {
    const tx = db.transaction('imports','readwrite'), complete=done(tx), store=tx.objectStore('imports')
    let read
    try {
      store.put({id:'availability-probe',value:true})
      read=requestResult(store.get('availability-probe'));store.delete('availability-probe')
    } catch(error) { tx.abort();await complete.catch(()=>{});throw error }
    const [value]=await Promise.all([read,complete])
    if(!value?.value)throw new Error('IndexedDB write/read probe failed')
  } catch(error) { db.close();throw error }
  return {
    kind:'indexedDB',
    async list() { const tx=db.transaction('metadata');const complete=done(tx);const [result]=await Promise.all([requestResult(tx.objectStore('metadata').getAll()),complete]);return result },
    async get(path) { const tx=db.transaction('pages');const complete=done(tx);const [result]=await Promise.all([requestResult(tx.objectStore('pages').get(path)),complete]);return result || null },
    async progress(id) { const tx=db.transaction('imports');const complete=done(tx);const [result]=await Promise.all([requestResult(tx.objectStore('imports').get(id)),complete]);return result },
    async write(records,{replace=()=>true,progress}={}) {
      const tx=db.transaction(['pages','metadata','imports'],'readwrite'),complete=done(tx)
      const pages=tx.objectStore('pages'), metadata=tx.objectStore('metadata'),stored=[],skipped=[]
      let writeError
      try {
        for(const record of records) {
          const request=pages.get(record.path)
          request.onsuccess=()=>{
            try {
              if(!replace(request.result,record)){skipped.push(record.path);return}
              pages.put(record);metadata.put(describeRecord(record));stored.push(record.path)
            }catch(error){writeError=error;tx.abort()}
          }
        }
        if(progress) {
          const state=tx.objectStore('imports'),request=state.get(progress.id)
          request.onsuccess=()=>{
            const completed=[...new Set([...(request.result?.completed || []),...progress.paths])]
            state.put({...progress,completed,complete:completed.length===progress.total,updatedAt:new Date().toISOString()})
          }
        }
      }catch(error){tx.abort();await complete.catch(()=>{});throw error}
      try {await complete}catch(error){throw writeError || error}
      return {stored,skipped}
    },
    async remove(paths) {
      const tx=db.transaction(['pages','metadata'],'readwrite'),complete=done(tx)
      for(const path of paths){tx.objectStore('pages').delete(path);tx.objectStore('metadata').delete(path)}
      await complete
    },
  }
}

export function localRecords() {
  const rows=[]
  for(const key of Object.keys(localStorage).filter(key=>key.startsWith(PAGE_PREFIX))) {
    const raw=localStorage.getItem(key)||''
    let record
    try{record=JSON.parse(raw)}catch(_){}
    const valid=validSnapshot(record)
    rows.push({key,raw,record,path:valid?record.path:'(unreadable)',valid,bytes:2*(key.length+raw.length)})
  }
  return rows
}

export function openLocalStore() {
  const key='fog-of-war:storage-probe:'+crypto.randomUUID()
  localStorage.setItem(key,'1')
  if(localStorage.getItem(key)!=='1')throw new Error('localStorage write/read probe failed')
  localStorage.removeItem(key)
  return {
    kind:'localStorage',
    async list(){return localRecords().map(row=>({...row,snapshot:row.record}))},
    async get(path){return localRecords().filter(row=>row.valid&&row.path===path).sort((a,b)=>Date.parse(b.record.savedAt)-Date.parse(a.record.savedAt))[0]?.record || null},
    async write(records){
      for(const record of records){
        const key=PAGE_PREFIX+record.path
        localStorage.setItem(key,stringifyLegacy(record))
        for(const row of localRecords())if(row.valid&&row.path===record.path&&row.key!==key)localStorage.removeItem(row.key)
      }
      return {stored:records.map(record=>record.path),skipped:[]}
    },
    async remove(paths){for(const row of localRecords())if(row.valid&&paths.includes(row.path))localStorage.removeItem(row.key)},
  }
}

export function openMemoryStore() {
  const records=new Map()
  return {kind:'memory', async list(){return [...records.values()].map(record=>describeRecord(record))},
    async get(path){return records.get(path)||null},async write(values){for(const record of values)records.set(record.path,record);return {stored:values.map(record=>record.path),skipped:[]}},
    async remove(paths){paths.forEach(path=>records.delete(path))}}
}
