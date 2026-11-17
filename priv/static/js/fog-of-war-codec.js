export const PAGE_PREFIX = 'fog-of-war:page:'
export const DATABASE = 'fog-of-war'

export function validSnapshot(record) {
  return Boolean(record && record.schema === 1 && typeof record.path === 'string' && record.path.startsWith('/') &&
    !record.path.startsWith('//') && !/[?#\\\0]/.test(record.path) && Number.isFinite(Date.parse(record.savedAt)) &&
    (typeof record.html === 'string' || (['gzip', 'gzip-aes-gcm', 'plain-aes-gcm'].includes(record.htmlEncoding) && record.htmlGzip instanceof Uint8Array) ||
      (record.htmlEncoding === 'gzip-base64' && typeof record.htmlGzip === 'string')))
}

export function binaryRecord(record) {
  if (record.htmlEncoding !== 'gzip-base64') return record
  const htmlGzip = Uint8Array.from(atob(record.htmlGzip), char => char.charCodeAt(0))
  return {...record, htmlEncoding:'gzip', htmlGzip}
}

export async function encodeSnapshot(snapshot) {
  const input = new TextEncoder().encode(snapshot.html)
  const plain = {...snapshot, htmlBytes:input.length}
  if (typeof CompressionStream === 'undefined' || typeof DecompressionStream === 'undefined') return plain
  const bytes = new Uint8Array(await new Response(new Blob([input]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer())
  if (bytes.length >= input.length) return plain
  const {html, ...metadata} = plain
  return {...metadata, htmlEncoding:'gzip', htmlGzip:bytes}
}

export async function decodeSnapshot(snapshot) {
  if (typeof snapshot.html === 'string') return snapshot
  const record = binaryRecord(snapshot)
  const html = await new Response(new Blob([record.htmlGzip]).stream().pipeThrough(new DecompressionStream('gzip'))).text()
  const {htmlEncoding, htmlGzip, ...metadata} = record
  return {...metadata, html}
}

export function stringifyLegacy(record) {
  if (record.htmlEncoding !== 'gzip') return JSON.stringify(record)
  let binary = ''
  for (const byte of record.htmlGzip) binary += String.fromCharCode(byte)
  return JSON.stringify({...record, htmlEncoding:'gzip-base64', htmlGzip:btoa(binary)})
}

export function recordKey(path, userId) {
  return userId ? JSON.stringify([userId, path]) : path
}

export function describeRecord(record, key = PAGE_PREFIX + recordKey(record.path, record.userId)) {
  const {html, htmlGzip, ...snapshot} = record
  const metadataBytes = new TextEncoder().encode(JSON.stringify(snapshot)).length
  const payloadBytes = htmlGzip instanceof Uint8Array ? htmlGzip.byteLength : new TextEncoder().encode(html || htmlGzip || '').length
  return {key, path:record.path, snapshot, valid:validSnapshot(record), bytes:metadataBytes+payloadBytes,
    raw:`${Date.now()}:${Math.random()}`}
}


export function isExpired(snapshot, now = Date.now()) {
  return snapshot?.expiresAt != null && snapshot.expiresAt <= now
}
