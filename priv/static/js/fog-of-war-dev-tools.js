import {installDevToolsLayout} from './fog-of-war-dev-tools-layout'
const bytes = value => value < 1024 ? `${value} B` : value < 1024 ** 2 ? `${(value / 1024).toFixed(1)} KiB` : `${(value / 1024 ** 2).toFixed(2)} MiB`
const labels = {attempt:'Attempt',live:'Live',cached:'Cached',denied:'Denied',superseded:'Superseded'}

export function createDevToolsHook(coordinator) {
  return {
    mounted() { this.tools = mountDevTools(this.el, coordinator) },
    destroyed() { this.tools?.destroy() },
  }
}

function mountDevTools(el, coordinator) {
  const root = el.attachShadow({mode:'open'})
  root.append(el.querySelector('template').content.cloneNode(true))
  const get = selector => root.querySelector(selector)
  const tools = get('.tools'), layout = installDevToolsLayout(el,root)
  const transparencyKey = 'fog-of-war:dev-tools-transparency'
  let semiTransparent = el.dataset.semiTransparent === 'true'
  try {
    const saved = sessionStorage.getItem(transparencyKey)
    if (saved !== null) semiTransparent = saved === 'true'
  } catch (_) {}
  const applyTransparency = () => {
    tools.dataset.semiTransparent = String(semiTransparent)
    get('[data-action="transparency"]').setAttribute('aria-pressed',String(semiTransparent))
  }
  applyTransparency()
  let retained=false, expanded=false, tab='cache', selected=null, rows=[]
  let refreshVersion=0, detailVersion=0, listSignature=null
  let sorting={key:'time',direction:-1}
  const notice = (text,kind='') => {
    const node=get('[data-cache-message]');node.textContent=text;node.title=text;node.dataset.kind=kind
  }
  const items = () => [
    ...(get('[data-filter="cache"]').checked ? rows.map(row=>({...row,id:row.key,kind:'cache',outcome:'saved',time:Date.parse(row.snapshot?.savedAt)||0,version:row.snapshot?.schema||0})) : []),
    ...(get('[data-filter="nav"]').checked ? coordinator.navigationEvents().map(row=>({...row,kind:'nav',bytes:0,version:0,open:false})) : []),
  ]
  const select = async id => {
    selected=id
    const version=++detailVersion
    root.querySelectorAll('tbody tr').forEach(row=>row.dataset.selected=String(row.dataset.key===id))
    const entry=items().find(row=>row.id===id)
    if (!entry) { get('[data-detail]').textContent='Select a saved page or navigation event.';return }
    if (entry.kind==='nav') {
      get('[data-detail]').textContent=JSON.stringify({type:'navigation',...entry,at:new Date(entry.time).toISOString()},null,2)
      return
    }
    const {html,htmlGzip,...metadata}=entry.snapshot||{}
    const header=JSON.stringify({key:entry.key,storageBytes:entry.bytes,openInTab:entry.open,...metadata},null,2)+'\n\n'
    get('[data-detail]').textContent=header+(html||'Decoding saved HTML…')
    if (!html) {
      try {
        const snapshot=await coordinator.cache.decode(entry.snapshot)
        if (version===detailVersion) get('[data-detail]').textContent=header+snapshot.html
      } catch (_) { if (version===detailVersion) get('[data-detail]').textContent=header+'Saved HTML is unreadable.' }
    }
  }
  const renderRows = () => {
    const records=items()
    const value = row => sorting.key==='kind' ? `${row.kind}:${row.outcome}` : row[sorting.key]
    records.sort((a,b)=>{
      const x=value(a),y=value(b)
      const diff=typeof x==='string' ? x.localeCompare(y) : Number(x)-Number(y)
      return diff*sorting.direction || a.id.localeCompare(b.id)
    })
    const signature=JSON.stringify([sorting,records.map(row=>[row.id,row.raw,row.time,row.outcome,row.open])])
    if (signature===listSignature) return
    listSignature=signature
    root.querySelectorAll('[data-sort]').forEach(button=>{
      const active=button.dataset.sort===sorting.key
      const label={path:'Path',kind:'Event',bytes:'Stored',time:'When',version:'Vsn',open:'Open'}[button.dataset.sort]
      button.textContent=label+(active?(sorting.direction===1?' ↑':' ↓'):'')
      button.parentElement.setAttribute('aria-sort',active?(sorting.direction===1?'ascending':'descending'):'none')
    })
    const fragment=document.createDocumentFragment()
    for(const entry of records) {
      const row=document.createElement('tr')
      row.dataset.key=entry.id;row.dataset.kind=entry.kind;row.dataset.outcome=entry.outcome;row.dataset.time=entry.time
      row.tabIndex=0;row.setAttribute('aria-label',`Inspect ${entry.kind==='cache'?'saved page':labels[entry.outcome]+' navigation'} ${entry.path}`)
      const values=[entry.path,entry.kind==='cache'?'Saved':labels[entry.outcome],entry.kind==='cache'?bytes(entry.bytes):'—',
        entry.time?new Date(entry.time).toLocaleTimeString():'Invalid',entry.kind==='cache'?String(entry.version):'—',entry.open?'●':'']
      values.forEach(value=>{const cell=document.createElement('td');cell.textContent=value;cell.title=value;row.append(cell)})
      row.lastElementChild.title=entry.open?'Protected: this route is open in a Fog of War tab':''
      fragment.append(row)
    }
    get('[data-rows]').replaceChildren(fragment)
    get('[data-empty]').hidden=records.length>0
    select(selected)
  }
  const refreshCache = async () => {
    const version=++refreshVersion
    try {
      const result=await coordinator.cache.inspect()
      if(version!==refreshVersion)return
      rows=result.rows
      get('[data-count]').textContent=String(rows.length)
      get('[data-total]').textContent=`${rows.length} · ${bytes(result.bytes)} · ${result.backend}`
      get('[data-total]').title=result.backend==='localStorage'?'localStorage fallback · estimated UTF-16 keys and values':`${result.backend} · encoded payload and metadata bytes, excluding database overhead. ${result.storageReason || ''}`
      const clear=get('[data-action="clear"]')
      clear.disabled=!result.canClear||!rows.some(row=>row.valid&&!row.open)
      clear.title=result.canClear?'Clear saved pages except routes open in Fog of War tabs':result.reason
      renderRows()
    } catch(error) { notice(`Cache unavailable: ${error.message}`,'error');get('[data-action="clear"]').disabled=true }
  }
  const showTab = name => {
    tab=name
    root.querySelectorAll('[role="tab"]').forEach(button=>{
      const active=button.dataset.tab===name
      button.setAttribute('aria-selected',String(active));button.tabIndex=active?0:-1
    })
    get('#help-pane').hidden=name!=='help';get('#cache-pane').hidden=name!=='cache'
    if(name==='cache')refreshCache()
  }
  const setExpanded = value => {
    expanded=value;get('.launcher').hidden=value;get('.launcher').setAttribute('aria-expanded',String(value));get('.panel').hidden=!value
    layout.expand(value)
    if(value){refreshCache();get(`[data-tab="${tab}"]`).focus()}else get('.launcher').focus()
  }
  const click = async event => {
    const target=event.target.closest('[data-action],[data-tab],[data-key],[data-sort]')
    if(!target)return
    if(target.dataset.tab){showTab(target.dataset.tab);return}
    if(target.dataset.key){select(target.dataset.key);return}
    if(target.dataset.sort){
      const key=target.dataset.sort
      sorting={key,direction:sorting.key===key?-sorting.direction:['time','bytes'].includes(key)?-1:1}
      renderRows();return
    }
    switch(target.dataset.action){
      case 'expand':setExpanded(true);break
      case 'collapse':setExpanded(false);break
      case 'connection':coordinator.toggleConnection();break
      case 'transparency':
        semiTransparent = !semiTransparent;applyTransparency()
        try { sessionStorage.setItem(transparencyKey,String(semiTransparent)) } catch (_) {}
        break
      case 'refresh':notice('');await refreshCache();break
      case 'clear-nav':coordinator.clearNavigations();break
      case 'clear':
        target.disabled=true;target.setAttribute('aria-busy','true')
        try{
          const result=await coordinator.cache.clearUnused()
          notice(`Cleared ${result.removed} · ${bytes(result.bytes)}; kept ${result.protectedCount} open`+(result.unreadable?`, ${result.unreadable} unreadable`:''),'success')
        }catch(error){notice(error.message,'error')}
        finally{target.removeAttribute('aria-busy');await refreshCache()}
        break
    }
  }
  const change = event => {if(event.target.matches('[data-filter]'))renderRows()}
  const keydown = event => {
    if(event.defaultPrevented)return
    if(event.key==='Escape'&&expanded){event.preventDefault();setExpanded(false)}
    const button=event.target.closest('[role="tab"]')
    if(button&&['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){
      event.preventDefault()
      const name=event.key==='Home'?'cache':event.key==='End'?'help':tab==='cache'?'help':'cache'
      showTab(name);get(`[data-tab="${name}"]`).focus()
    }
    const row=event.target.closest('[data-key]')
    if(row&&['Enter',' '].includes(event.key)){event.preventDefault();select(row.dataset.key)}
  }
  root.addEventListener('click',click);root.addEventListener('change',change);root.addEventListener('keydown',keydown)
  const unsubscribeStatus=coordinator.subscribe(status=>{
    tools.dataset.connection=status.connection
    tools.dataset.socket=status.socketConnected?'connected':'closed'
    get('[data-state]').textContent=status.socketConnected?'Live':'Disconnected'
    get('[data-state]').title=status.text
    const connection=get('[data-action="connection"]')
    connection.dataset.paused=String(status.connection==='paused')
    connection.setAttribute('aria-label',status.connection==='paused'?'Reconnect':'Disconnect socket')
    get('[data-action="connection"]').title=status.connection==='paused'?'Reconnect; cached browsing reloads the current route.':'Disconnect socket'
    get('[data-message]').textContent=status.message||(status.snapshotMode?'Read-only cached HTML · reconnect loads the current route.':'Navigation events stay in memory in this document.')
    get('[data-message]').title=get('[data-message]').textContent
  })
  const unsubscribeCache=coordinator.cache.subscribe(refreshCache)
  const unsubscribeNavigations=coordinator.subscribeNavigations(renderRows)
  const timer=window.setInterval(()=>{if(expanded&&tab==='cache')refreshCache()},2000)
  const controller={el,retain(){retained=true},destroy(){
    if(retained)return
    unsubscribeStatus();unsubscribeCache();unsubscribeNavigations();unregister();layout.destroy();clearInterval(timer)
    root.removeEventListener('click',click);root.removeEventListener('change',change);root.removeEventListener('keydown',keydown)
  }}
  const unregister=coordinator.registerDevTools(controller)
  refreshCache()
  return controller
}
