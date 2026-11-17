const encoder = new TextEncoder()

function metadata(record) {
  return encoder.encode(JSON.stringify([record.schema, record.build, record.path, record.userId || null,
    ...(record.accountProtected ? ['account-key'] : [])]))
}

export async function sealSnapshot(record, key) {
  if (record.accountProtected && typeof record.html === 'string') {
    const {html, ...rest} = record
    record = {...rest, htmlEncoding: 'plain-aes-gcm', htmlGzip: encoder.encode(html)}
  }
  if (!['gzip', 'plain-aes-gcm'].includes(record.htmlEncoding)) return record
  const nonce = crypto.getRandomValues(new Uint8Array(12))
  const encrypted = await crypto.subtle.encrypt(
    {name: 'AES-GCM', iv: nonce, additionalData: metadata(record)}, key, record.htmlGzip
  )
  return {...record, htmlEncoding: record.htmlEncoding === 'gzip' ? 'gzip-aes-gcm' : 'plain-aes-gcm', htmlGzip: new Uint8Array(encrypted), nonce}
}

export async function openSnapshot(record, key) {
  if (!['gzip-aes-gcm', 'plain-aes-gcm'].includes(record?.htmlEncoding)) return record
  const bytes = await crypto.subtle.decrypt(
    {name: 'AES-GCM', iv: record.nonce, additionalData: metadata(record)}, key, record.htmlGzip
  )
  const {nonce, ...snapshot} = record
  if (snapshot.htmlEncoding === 'plain-aes-gcm') {
    const {htmlEncoding, htmlGzip, ...rest} = snapshot
    return {...rest, html: new TextDecoder().decode(bytes)}
  }
  return {...snapshot, htmlEncoding: 'gzip', htmlGzip: new Uint8Array(bytes)}
}
