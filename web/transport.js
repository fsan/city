// Game windows and map gestures; all traffic, fares and passengers live in Zig.
export function mountTransport() {
  document.getElementById('game').insertAdjacentHTML('beforeend', `
    <svg id="route-map" aria-hidden="true"></svg>
    <div id="route-tools" hidden><strong>BUS ROUTE DRAFT</strong><span>Drag a stop or a route segment. Click a street to add a stop.</span><button id="route-save-map">Apply route</button><button id="route-cancel-map">Cancel · Esc</button></div>
    <section class="game-window wide" id="transport-window" role="dialog" aria-labelledby="transport-title" tabindex="-1" hidden>
      <header class="window-title"><h2 id="transport-title">Transport authority</h2><span class="window-number">06 / MOBILITY</span><button data-close="transport" aria-label="Close transport">×</button></header>
      <div class="window-body">
        <div id="transport-summary" class="note"></div>
        <h3>Fares & support</h3>
        <div class="transport-controls"><label>Fare cap £ <input id="fare-cap" type="number" min="0" max="10" step="0.1" value="2"></label><label>Subsidy per boarding £ <input id="bus-subsidy" type="number" min="0" max="10" step="0.1" value="1"></label><button id="transport-policy">Apply policy</button></div>
        <p class="note">Operators charge up to £3 within the cap. Subsidies come from uncommitted city funds. Each line starts with £3,000 private capital; buses cost £0.18 per simulation second each. Service stops when cash runs out. Capacity: 24 seats; two buses per line.</p>
        <h3>Bus lines</h3><div class="transport-controls"><select id="bus-line" aria-label="Bus line"></select><button id="line-new">New line</button><button id="line-remove">Remove line</button></div>
        <div id="line-stats" class="note"></div>
        <div class="transport-controls"><button id="line-edit">Edit route on map</button><button id="line-clear">Clear map selection</button></div>
        <div id="route-form" hidden><h3>Ordered street stops · circular service</h3><ol id="stop-list"></ol><label>Street address <select id="stop-address"></select></label><div class="transport-controls"><button id="stop-add">Add address</button><button id="route-save">Apply route</button><button id="route-cancel">Discard changes</button></div><p class="note">Two to sixteen unique stops. Closing the window keeps map editing active. Drag a gold stop to relocate it; drag a connecting route segment to insert a stop. Changes unload riders at the next junction before buses join the revised service.</p></div>
        <h3>Street allocation</h3><label>Street segment <select id="traffic-road"></select></label>
        <div id="traffic-road-stats" class="note"></div><div class="transport-controls"><select id="traffic-lane" aria-label="Street lane allocation"><option value="0">Mixed traffic</option><option value="1">Dedicated bus lanes</option><option value="2">Protected cycle lanes</option></select><button id="lane-apply">Apply lanes</button><button id="road-locate">Locate street</button></div>
        <p class="note">Bus lanes bypass general traffic queues. Cycle lanes improve cycling speed. Both allocations reduce car speed by 20%. Works, slopes and worn surfaces also slow traffic. G toggles the traffic map; click a street there to inspect it.</p>
        <h3>Current queues</h3><div id="traffic-hotspots"></div><p id="transport-message" role="status"></p>
      </div>
    </section>`);
  document.querySelector('.toolbar').insertAdjacentHTML('beforeend', '<button data-toggle="transport" title="Transport (T)">Transport <kbd>T</kbd></button><button id="traffic-overlay" aria-pressed="false" title="Traffic map (G)">Traffic <kbd>G</kbd></button>');
}
export function createTransport(game, ui) {
  const $ = id => document.getElementById(id);
  const r = (group, id, field) => game.read(group, id, field);
  const money = n => `£${n.toFixed(2)}`;
  const nodes = Array.from({length:r(9,0,4)}, (_,id)=>({id,x:r(11,id,0),z:r(11,id,1)}));
  const streets = ['River','Foundry','Station','Market','Civic','Orchard','Mill','Garden','School','Exchange','Library','Church','Depot','South','Park','Ridge','Boundary'];
  const address = id => {const n=nodes[id]; return `${Math.round(n.x/14)*20+1} ${streets[Math.round(n.z/14)]} Street · Avenue ${Math.round(n.x/14)+1}`;};
  const roads = Array.from({length:r(0,0,15)},(_,id)=>({id,a:r(5,id,0),b:r(5,id,1)}));
  let selected=-1, draft=null, gesture=null, overlay=0;
  const message = text => $('transport-message').textContent=text;
  const option = (value,text) => {const o=document.createElement('option');o.value=value;o.textContent=text;return o;};
  nodes.forEach(n=>$('stop-address').append(option(n.id,address(n.id))));
  roads.forEach(road=>$('traffic-road').append(option(road.id,`#${road.id+1} · ${address(road.a)} → ${address(road.b)}`)));
  function syncLines() {
    const ids=Array.from({length:8},(_,i)=>i).filter(i=>r(10,i,0)||i===selected);
    $('bus-line').replaceChildren(...ids.map(id=>option(id,`Line ${id+1}${r(10,id,0)?'':' · draft / withdrawn'}`)));
    if (!ids.includes(selected)) selected=ids[0]??-1;
    $('bus-line').value=selected;
    game.transport_select(selected);
    $('line-edit').disabled=selected<0; $('line-remove').disabled=selected<0||!r(10,selected,0);
  }
  function syncDraft() {
    if (!draft) {game.transport_edit_end();$('route-tools').hidden=true;$('route-form').hidden=true;return;}
    game.transport_draft(draft.length);draft.forEach((n,i)=>game.transport_stop(i,n));
    $('route-tools').hidden=false;$('route-form').hidden=false;
    $('stop-list').replaceChildren(...draft.map((n,i)=>{
      const li=document.createElement('li');const label=document.createElement('span');label.textContent=address(n);li.append(label);
      for (const [text,action] of [['↑',()=>{if(i){[draft[i-1],draft[i]]=[draft[i],draft[i-1]];syncDraft();}}],['×',()=>{draft.splice(i,1);syncDraft();}]]) {const b=document.createElement('button');b.textContent=text;b.setAttribute('aria-label',`${text==='↑'?'Move earlier':'Remove stop'} ${i+1}`);b.onclick=action;li.append(b);}return li;
    }));
  }
  function cancel(){if(!draft)return false;draft=null;gesture=null;syncDraft();message('Route changes discarded.');return true;}
  function save(){if(!draft)return;syncDraft();if(!game.transport_apply(selected)){message('Choose two to sixteen unique street addresses.');ui.open('transport');return;}draft=null;syncDraft();syncLines();message(`Line ${selected+1} route applied. Existing riders unload safely before the new service starts.`);}
  function edit(){if(selected<0)return;draft=Array.from({length:r(10,selected,1)},(_,i)=>r(10,selected,16+i));syncDraft();message('Route draft active. Move this window aside or close it to edit on the map.');}
  $('bus-line').onchange=()=>{cancel();selected=Number($('bus-line').value);game.transport_select(selected);update();};
  $('line-new').onclick=()=>{const id=Array.from({length:8},(_,i)=>i).find(i=>!r(10,i,0));if(id===undefined){message('All eight line slots are in use.');return;}selected=id;draft=[];syncLines();syncDraft();message('Choose street addresses or click streets on the map, then apply the route.');};
  $('line-edit').onclick=edit;
  $('line-remove').onclick=()=>{cancel();game.transport_remove(selected);syncLines();message('Line withdrawn. On-board riders leave at the next junction and continue on foot.');};
  $('line-clear').onclick=()=>{cancel();game.transport_select(-1);$('route-map').replaceChildren();};
  $('stop-add').onclick=()=>{const n=Number($('stop-address').value);if(!draft)return;if(draft.length===16||draft.includes(n)){message('Stops must be unique, with a maximum of sixteen.');return;}draft.push(n);syncDraft();};
  $('route-save').onclick=$('route-save-map').onclick=save;
  $('route-cancel').onclick=$('route-cancel-map').onclick=cancel;
  $('transport-policy').onclick=()=>{const cap=Number($('fare-cap').value),sub=Number($('bus-subsidy').value);message(game.transport_policy(cap,sub)?'Fare cap and boarding subsidy applied.':'Enter amounts from £0 to £10.');};
  const chooseRoad=id=>{$('traffic-road').value=id;$('traffic-lane').value=r(5,id,13);update();};
  $('traffic-road').onchange=()=>chooseRoad(Number($('traffic-road').value));
  $('lane-apply').onclick=()=>{game.transport_lane(Number($('traffic-road').value),Number($('traffic-lane').value));message('Street allocation applied in both directions.');};
  $('road-locate').onclick=()=>game.focus(5,Number($('traffic-road').value));
  function setOverlay(mode){overlay=mode;game.set_overlay(mode);$('traffic-overlay').setAttribute('aria-pressed',mode===2);$('overlay').setAttribute('aria-pressed',mode===1);$('overlay-key').hidden=!mode;$('overlay-key').querySelector('strong').textContent=mode===2?'TRAFFIC · QUEUE PRESSURE':'STREET CONDITION';$('overlay-key').querySelector('small').innerHTML=mode===2?'Queued <span>Flowing</span>':'Worn <span>Maintained</span>';}
  $('traffic-overlay').onclick=()=>setOverlay(overlay===2?0:2);
  function points(){return nodes.map(n=>({x:r(11,n.id,3),y:r(11,n.id,4)}));}
  function path(stops){const pieces=[];for(let i=0;i<stops.length;i++){let n=stops[i],to=stops[(i+1)%stops.length];for(let k=0;n!==to&&k<nodes.length;k++){const next=game.route_next(n,to);pieces.push({a:n,b:next,index:i});n=next;}}return pieces;}
  function distance(p,a,b){const dx=b.x-a.x,dy=b.y-a.y;const t=Math.max(0,Math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/(dx*dx+dy*dy||1)));return Math.hypot(p.x-a.x-t*dx,p.y-a.y-t*dy);}
  function nearest(p,pts){return nodes.reduce((best,n)=>Math.hypot(pts[n.id].x-p.x,pts[n.id].y-p.y)<Math.hypot(pts[best].x-p.x,pts[best].y-p.y)?n.id:best,0);}
  function pointerDown(event){
    const p={x:event.clientX,y:event.clientY},pts=points();
    if(draft){let index=draft.findIndex(n=>Math.hypot(pts[n].x-p.x,pts[n].y-p.y)<15);if(index<0){const segment=path(draft).find(e=>distance(p,pts[e.a],pts[e.b])<8);if(draft.length>=16)return true;index=segment?segment.index+1:draft.length;draft.splice(index,0,nearest(p,pts));}gesture={index,original:[...draft]};return true;}
    if(overlay===2){let best=null,min=10;for(const road of roads){const d=distance(p,pts[road.a],pts[road.b]);if(d<min){min=d;best=road.id;}}if(best!==null){chooseRoad(best);ui.open('transport');return true;}}
    return false;
  }
  function pointerMove(event){if(!gesture||!draft)return false;draft[gesture.index]=nearest({x:event.clientX,y:event.clientY},points());game.transport_draft(draft.length);draft.forEach((n,i)=>game.transport_stop(i,n));return true;}
  function pointerUp(){if(!gesture)return false;gesture=null;syncDraft();return true;}
  function paint(){
    const stops=draft??(selected>=0&&r(10,selected,0)?Array.from({length:r(10,selected,1)},(_,i)=>r(10,selected,16+i)):[]);
    const svg=$('route-map');if(!draft){svg.replaceChildren();return;}const pts=points();
    svg.innerHTML=path(stops).map(e=>`<line x1="${pts[e.a].x}" y1="${pts[e.a].y}" x2="${pts[e.b].x}" y2="${pts[e.b].y}"/>`).join('')+stops.map((n,i)=>`<circle cx="${pts[n].x}" cy="${pts[n].y}" r="10"/><text x="${pts[n].x}" y="${pts[n].y+4}">${i+1}</text>`).join('');
  }
  function update(){
    $('transport-summary').textContent=`Trips in progress: ${r(9,0,5)} walk · ${r(9,0,6)} cycle · ${r(9,0,7)} car · ${r(9,0,8)} bus. Waiting at stops: ${r(9,0,9)}. City subsidies paid: ${money(r(9,0,2))}.`;
    $('line-stats').textContent=selected<0?'No bus lines. Create a line to begin service.':`Line ${selected+1}: ${r(10,selected,1)} stops · ${r(10,selected,7)} aboard · ${r(10,selected,2)} boardings · income ${money(r(10,selected,3))} · costs ${money(r(10,selected,4))} · operator cash ${money(r(10,selected,5))}${r(10,selected,5)<=0?' · SERVICE SUSPENDED':''}`;
    const road=Number($('traffic-road').value);$('traffic-road-stats').textContent=`${r(5,road,10)} vehicles on segment · ${r(5,road,11)} queued · ${(r(5,road,12)*100).toFixed(0)}% queue pressure · ${(r(5,road,3)*100).toFixed(0)}% grade`;
    const top=roads.filter(road=>r(5,road.id,11)>0).sort((a,b)=>r(5,b.id,11)-r(5,a.id,11)).slice(0,5);
    $('traffic-hotspots').replaceChildren(...top.map(road=>{const b=document.createElement('button');b.textContent=`Street #${road.id+1} · ${r(5,road.id,11)} queued`;b.onclick=()=>{chooseRoad(road.id);game.focus(5,road.id);};return b;}));
  }
  syncLines();game.transport_select(-1);update();
  return {update,paint,pointerDown,pointerMove,pointerUp,cancel,toggleTraffic:() =>setOverlay(overlay===2?0:2),toggleCondition:()=>setOverlay(overlay===1?0:1),reset(){draft=null;gesture=null;selected=-1;syncDraft();syncLines();game.transport_select(-1);setOverlay(0);$('fare-cap').value=r(9,0,0);$('bus-subsidy').value=r(9,0,1);update();}};
}
