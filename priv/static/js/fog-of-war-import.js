const hash = async bytes => [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(byte=>byte.toString(16).padStart(2,'0')).join('')
const abortIfNeeded = signal => { if(signal?.aborted)throw new DOMException('Bundle import interrupted','AbortError') }

export async function importBundle(runtime,input,{baseURL,readAsset,batchSize=16,byteBudget=1024*1024,onProgress,signal}={}) {
  await runtime.ready
  if(runtime.kind()!=='indexedDB')throw new Error('Bundle importing requires IndexedDB; the fallback cache remains available for ordinary captures')
  if(!Number.isInteger(batchSize)||batchSize<1||!Number.isInteger(byteBudget)||byteBudget<1)throw new Error('Import batch limits must be positive integers')
  let index=input
  if(typeof input==='string'||input instanceof URL){
    const url=new URL(input,location.href)
    const response=await fetch(url,{credentials:'omit',signal})
    if(!response.ok)throw new Error(`Bundle index: HTTP ${response.status}`)
    index=await response.json();baseURL=new URL('.',url).href
  }
  if(index?.schema!==1||index.format!=='fog-of-war-public-cache'||index.scope!=='public'||index.origin!==location.origin||!index.pages||typeof index.pages!=='object'||Array.isArray(index.pages))throw new Error('Bundle index does not match this origin or supported format')
  if(typeof DecompressionStream==='undefined')throw new Error('This browser cannot decompress bundled gzip records')
  if(!readAsset&&!baseURL)throw new Error('A bundle baseURL or host readAsset callback is required')
  const descriptors=Object.entries(index.pages)
  for(const [path,record] of descriptors){
    const url=new URL(path,location.origin)
    if(url.origin!==location.origin||url.pathname!==path||url.search||url.hash||record.path!==path||record.schema!==1||record.build!==runtime.build||!Number.isFinite(Date.parse(record.savedAt))||
      record.encoding!=='gzip'||!Number.isInteger(record.compressedBytes)||record.compressedBytes<1||record.compressedBytes>2100000||!Number.isInteger(record.htmlBytes)||record.htmlBytes<0||
      !/^[a-f0-9]{64}$/.test(record.sha256)||typeof record.file!=='string'||record.file.startsWith('/')||/[\\?#%]/.test(record.file)||record.file.split('/').some(part=>part==='..'||part==='.'||!part))throw new Error(`Invalid bundle record: ${path}`)
  }
  const id=await hash(new TextEncoder().encode(JSON.stringify(index)))
  let state=await runtime.progress(id),completed=new Set(state?.completed || []),records=[],paths=[],bytes=0,stored=0,skipped=0
  const report=()=>({id,total:descriptors.length,completed:completed.size,stored,skipped,complete:completed.size===descriptors.length})
  const flush=async()=>{
    if(!paths.length)return
    abortIfNeeded(signal)
    const result=await runtime.commit(records,{id,paths,total:descriptors.length})
    stored+=result.stored.length;skipped+=paths.length-result.stored.length
    paths.forEach(path=>completed.add(path));records=[];paths=[];bytes=0
    onProgress?.(report())
    // Yield between committed batches so normal page captures can proceed.
    await new Promise(resolve=>setTimeout(resolve,0))
  }
  for(const [path,descriptor] of descriptors){
    abortIfNeeded(signal)
    const existing=runtime.find(path)
    if(completed.has(path)&&existing)continue
    if(bytes&&bytes+descriptor.compressedBytes>byteBudget)await flush()
    abortIfNeeded(signal)
    if(!existing||existing.source==='bundle'&&Date.parse(existing.savedAt)<Date.parse(descriptor.savedAt)){
      let payload
      if(readAsset){payload=await readAsset(descriptor.file,{signal});payload=payload instanceof Uint8Array?payload:new Uint8Array(payload)}
      else {
        const url=new URL(descriptor.file,baseURL)
        if(url.origin!==new URL(baseURL).origin)throw new Error('Bundle asset escaped its base origin')
        const response=await fetch(url,{credentials:'omit',signal})
        if(!response.ok)throw new Error(`Bundle page ${path}: HTTP ${response.status}`)
        const reader=response.body.getReader(),chunks=[];let length=0
        try {while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>descriptor.compressedBytes)throw new Error(`Bundle page too large: ${path}`);chunks.push(value)}}
        catch(error){await reader.cancel();throw error}
        payload=new Uint8Array(length);let offset=0;for(const chunk of chunks){payload.set(chunk,offset);offset+=chunk.length}
      }
      abortIfNeeded(signal)
      if(payload.byteLength!==descriptor.compressedBytes||await hash(payload)!==descriptor.sha256)throw new Error(`Bundle checksum mismatch: ${path}`)
      const {file,encoding,compressedBytes,...metadata}=descriptor
      records.push({...metadata,source:'bundle',htmlEncoding:'gzip',htmlGzip:payload});bytes+=payload.byteLength
    }
    paths.push(path)
    if(paths.length>=batchSize||bytes>=byteBudget)await flush()
  }
  await flush()
  return report()
}
