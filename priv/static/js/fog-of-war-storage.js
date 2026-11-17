import {sealSnapshot, openSnapshot} from './fog-of-war-encryption'
import {DATABASE, PAGE_PREFIX, describeRecord, recordKey, stringifyLegacy, validSnapshot} from './fog-of-war-codec'

const requestResult = request => new Promise((resolve,reject) => {
  request.onsuccess = () => resolve(request.result)
  request.onerror = () => reject(request.error)
})
const done = transaction => new Promise((resolve,reject) => {
  transaction.oncomplete = () => resolve()
  transaction.onabort = () => reject(transaction.error || new Error('Storage transaction aborted'))
  transaction.onerror = () => {} // onabort reports the final transaction result.
})

export async function openIndexedDBStore({protectedAccounts = false} = {}) {
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
  let keyPromise
  const key = () => keyPromise ||= (async () => {
    const read = async () => {
      const tx = db.transaction('imports'), complete = done(tx)
      const [entry] = await Promise.all([
        requestResult(tx.objectStore('imports').get('snapshot-encryption-key')), complete
      ])
      return entry?.key
    }
    const existing = await read()
    if (existing) return existing
    const candidate = await crypto.subtle.generateKey({name: 'AES-GCM', length: 256}, false, ['encrypt', 'decrypt'])
    const tx = db.transaction('imports', 'readwrite'), complete = done(tx)
    const keys = tx.objectStore('imports')
    const request = keys.get('snapshot-encryption-key')
    request.onsuccess = () => {
      if (!request.result) keys.add({id: 'snapshot-encryption-key', key: candidate})
    }
    await complete
    return read()
  })().catch(error => {
    keyPromise = null
    throw error
  })

  const readSetting = async id => {
    const tx = db.transaction('imports'), complete = done(tx)
    const [value] = await Promise.all([requestResult(tx.objectStore('imports').get(id)), complete])
    return value
  }
  const account = () => readSetting('active-account')
  const setAccount = async (value, expected) => {
    const tx = db.transaction(['imports', 'pages', 'metadata'], 'readwrite'), complete = done(tx)
    const settings = tx.objectStore('imports')
    const current = settings.get('active-account')
    let applied = false
    current.onsuccess = () => {
      if (expected !== undefined && (current.result?.revision || null) !== expected) return
      settings.put({id: 'active-account', ...value, revision: crypto.randomUUID()})
      applied = true
      if (!value.key) return
      const cursor = tx.objectStore('metadata').openCursor()
      cursor.onsuccess = () => {
        const row = cursor.result
        if (!row) return
        if (row.value.snapshot?.userId && !row.value.snapshot.accountProtected) {
          tx.objectStore('pages').delete(row.primaryKey)
          row.delete()
        }
        row.continue()
      }
    }
    await complete
    return applied
  }

  return {
    kind:'indexedDB',
    account, setAccount,
    enableAccountProtection() { protectedAccounts = true },
    async deviceId() {
      const tx = db.transaction('imports', 'readwrite'), complete = done(tx)
      const settings = tx.objectStore('imports')
      const request = settings.get('account-device-id')
      let value
      request.onsuccess = () => {
        value = request.result?.value || crypto.randomUUID()
        if (!request.result) settings.add({id: 'account-device-id', value})
      }
      await complete
      return value
    },
    async list() { const tx=db.transaction('metadata');const complete=done(tx);const [result]=await Promise.all([requestResult(tx.objectStore('metadata').getAll()),complete]);return result.map(row => ({...row, path: row.snapshot.path})) },
    async get(path) { const tx=db.transaction('pages');const complete=done(tx);const [result]=await Promise.all([requestResult(tx.objectStore('pages').get(path)),complete]);if (!result) return null
      const record = {...result, path: result.route || result.path}
      if (record.userId && (protectedAccounts || record.accountProtected)) {
        if (!protectedAccounts || !record.accountProtected) return null
        const active = await account()
        if (!active?.key || active.userId !== record.userId) return null
        const decoded = await openSnapshot(record, active.key)
        return active.revision === (await account())?.revision
          ? {...decoded, accountRevision: active.revision} : null
      }
      return record.htmlEncoding === 'gzip-aes-gcm' ? openSnapshot(record, await key()) : record },
    async progress(id) { const tx=db.transaction('imports');const complete=done(tx);const [result]=await Promise.all([requestResult(tx.objectStore('imports').get(id)),complete]);return result },
    async write(records,{replace=()=>true,progress}={}) {
      const active = protectedAccounts && records.some(record => record.userId) ? await account() : null
      records = (await Promise.all(records.map(async record => {
        if (protectedAccounts && record.userId) {
          if (!active?.key || active.userId !== record.userId) return null
          return sealSnapshot({...record, accountProtected: true}, active.key)
        }
        return record.htmlEncoding === 'gzip' ? sealSnapshot(record, await key()) : record
      }))).filter(Boolean)
      const tx=db.transaction(['pages','metadata','imports'],'readwrite'),complete=done(tx)
      const pages=tx.objectStore('pages'), metadata=tx.objectStore('metadata'),stored=[],skipped=[]
      let writeError
      try {
        for(const record of records) {
          const key=recordKey(record.path, record.userId)
          const request=pages.get(key)
          const slot = record.accountProtected ? tx.objectStore('imports').get('active-account') : null
          const write = () => {
            if (slot && slot.result?.revision !== active.revision) return
            try {
              if(!replace(request.result,record)){skipped.push(record.path);return}
              pages.put({...record,path:key,route:record.path});metadata.put({...describeRecord(record),path:key});stored.push(record.path)
            }catch(error){writeError=error;tx.abort()}
          }
          if (slot) slot.onsuccess = write
          else request.onsuccess = write
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
    async get(path){return localRecords().filter(row=>row.valid&&recordKey(row.path,row.record.userId)===path).sort((a,b)=>Date.parse(b.record.savedAt)-Date.parse(a.record.savedAt))[0]?.record || null},
    async write(records){
      for(const record of records){
        const key=PAGE_PREFIX+recordKey(record.path,record.userId)
        localStorage.setItem(key,stringifyLegacy(record))
        for(const row of localRecords())if(row.valid&&recordKey(row.path,row.record.userId)===recordKey(record.path,record.userId)&&row.key!==key)localStorage.removeItem(row.key)
      }
      return {stored:records.map(record=>record.path),skipped:[]}
    },
    async remove(paths){for(const row of localRecords())if(row.valid&&paths.includes(recordKey(row.path,row.record.userId)))localStorage.removeItem(row.key)},
  }
}

export function openMemoryStore() {
  const records=new Map()
  return {kind:'memory', async list(){return [...records.values()].map(record=>describeRecord(record))},
    async get(path){return records.get(path)||null},async write(values){for(const record of values)records.set(recordKey(record.path,record.userId),record);return {stored:values.map(record=>record.path),skipped:[]}},
    async remove(paths){paths.forEach(path=>records.delete(path))}}
}
