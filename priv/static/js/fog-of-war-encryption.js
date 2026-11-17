const encoder = new TextEncoder()

function metadata(record) {
  return encoder.encode(JSON.stringify([record.schema, record.build, record.path, record.userId || null]))
}

export async function sealSnapshot(record, key) {
  if (record.htmlEncoding !== 'gzip') return record
  const nonce = crypto.getRandomValues(new Uint8Array(12))
  const encrypted = await crypto.subtle.encrypt(
    {name: 'AES-GCM', iv: nonce, additionalData: metadata(record)}, key, record.htmlGzip
  )
  return {...record, htmlEncoding: 'gzip-aes-gcm', htmlGzip: new Uint8Array(encrypted), nonce}
}

export async function openSnapshot(record, key) {
  if (record?.htmlEncoding !== 'gzip-aes-gcm') return record
  const bytes = await crypto.subtle.decrypt(
    {name: 'AES-GCM', iv: record.nonce, additionalData: metadata(record)}, key, record.htmlGzip
  )
  const {nonce, ...snapshot} = record
  return {...snapshot, htmlEncoding: 'gzip', htmlGzip: new Uint8Array(bytes)}
}
