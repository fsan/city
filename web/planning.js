// Map tools own interaction only; Zig validates, prices and commits the network.
import {decisionNames, kinds, refusalNames, streetName} from './data.js';
export function createPlanning(game, transport) {
  const $=id=>document.getElementById(id), r=(g,id,f)=>game.read(g,id,f);
  let mode=null, fixed=0, ready=false, parcel=-1;
  const errors=['Ready to build.','Keep the road inside the map, between 6 and 500 metres.','Road would overlap a building or park.','Grade is too steep.','Insufficient uncommitted funds.','Network capacity reached. Try a shorter road.','A street here has a reserved work order.','Road overlaps another road or makes a very shallow junction.','Connect the road to the existing street network.','The river is in the way. Only the seeded bridges cross it.'];
  const names=['Unzoned','Residential','Commercial','Industrial','Mixed use','Civic / park reserve'];
  const classes=['lane (£18/m, kerbside parking not allowed)','street (£25/m, kerbside parking banded by movement)','avenue (£40/m, wide and fastest, kerbside parking banded by movement)'];
  function close(){mode=null;fixed=0;ready=false;game.road_cancel();game.zoning_show(0);$('planning-panel').hidden=true;$('road-tool').setAttribute('aria-pressed','false');$('zone-tool').setAttribute('aria-pressed','false');$('permit-tool').setAttribute('aria-pressed','false');}
  function begin(next){transport.cancel();close();mode=next;$('planning-panel').hidden=false;$('road-options').hidden=next!=='road';$('zone-options').hidden=next!=='zone';$('permit-options').hidden=next!=='permit';$(next==='road'?'road-tool':next==='zone'?'zone-tool':'permit-tool').setAttribute('aria-pressed','true');if(next==='road'){game.road_class(Number($('road-class').value));game.road_begin(Number($('road-shape').value));}else if(next==='zone')game.zoning_show(1);else permits();status();}
  // Slice 18: the development queue. Every open application is one row with its
  // own decision, and Zig still owns every rule: the buttons only report back
  // what the simulation accepted.
  function permits(){
    const retained=Math.max(0,Math.min(m(19),24));let open=0;const values=[];
    // The queue itself is group 31; the running totals are group 0 fields
    // 70-78, because they belong with the other city metrics.
    const agg=(field)=>r(0,0,field);
    for(let i=0;i<retained;i++){
      const decision=m(14,i);
      if(decision!==0)continue;
      open++;
      const name=kinds[m(5,i)]||'Land use';
      values.push([`${m(0,i).toFixed(0)}`,name,`district ${m(3,i)+1} · parcel ${m(1,i)+1}`,`£${m(9,i).toFixed(2)}`,`day ${Math.max(1,Math.ceil(m(11,i)/480))}`,
        [{text:'Grant permit',action:()=>{game.development_accept(i);permits();status();}},{text:'Refuse',action:()=>{game.development_refuse(i);permits();status();}}]]);
    }
    rows('permit-rows',values);
    $('permit-summary').textContent=open===0
      ?`No applications are open. ${agg(77).toFixed(0)} zoned vacant sites remain; private developers only apply where the town is measurably crowded. ${agg(72).toFixed(0)} built so far.`
      :`${open} open of ${agg(75).toFixed(0)} ever lodged · £${agg(76).toFixed(2)} in levies received · ${agg(77).toFixed(0)} zoned vacant sites remain. ${agg(72).toFixed(0)} built, ${agg(73).toFixed(0)} refused, ${agg(74).toFixed(0)} lapsed, ${agg(71).toFixed(0)} under construction.`;
  }
  const m=(field,id)=>game.read(31,id===undefined?0:id,field);
  function rows(id,values){
    const body=$(id);
    values.forEach((cells,index)=>{
      const row=body.children[index]||body.appendChild(document.createElement('tr'));
      cells.forEach((value,column)=>{
        const cell=row.children[column]||row.appendChild(document.createElement('td'));
        if(typeof value==='object'){
          cell.replaceChildren(...value.map(button=>{
            const element=document.createElement('button');element.textContent=button.text;element.onclick=button.action;return element;
          }));
        }else if(cell.textContent!==String(value))cell.textContent=String(value);
      });
      while(row.children.length>cells.length)row.lastElementChild.remove();
    });
    while(body.children.length>values.length)body.lastElementChild.remove();
  }
  function status(){
    if(mode==='road'){
      const curved=$('road-shape').value==='1';
      $('planning-status').textContent=fixed===0?`${classes[Number($('road-class').value)]}. Click a start point. Existing streets and junctions snap automatically.`:!ready?(curved&&fixed===1?'Click the bend control point, then choose the end.':'Choose the end point. Green is buildable; red shows a conflict.'):`${r(15,0,2).toFixed(0)} m · £${r(15,0,1).toFixed(2)} · ${errors[r(15,0,0)]}`;
      $('road-build').disabled=!ready||r(15,0,0)!==0;
    }else if(mode==='permit'){
      $('planning-status').textContent='Private development: grant or refuse each application. Zig validates the site and books the levy.';
    }else if(mode==='zone'){
      $('zone-apply').disabled=parcel<0;
      $('planning-status').textContent=parcel<0?'Select a coloured parcel. Choose a zone, then apply to that parcel or its enclosed block.':`${r(16,parcel,6)} ${streetName(r(16,parcel,5))} · ${names[r(16,parcel,2)]} · ${r(16,parcel,4)>=0?`Block ${r(16,parcel,4)+1}`:'Open roadside frontage'} · ${r(16,parcel,3)>=0?'Existing building retained':'Vacant land'}`;
    }
  }
  $('road-tool').onclick=()=>mode==='road'?close():begin('road');
  $('zone-tool').onclick=()=>mode==='zone'?close():begin('zone');
  $('permit-tool').onclick=()=>mode==='permit'?close():begin('permit');
  $('planning-close').onclick=close;
  $('road-shape').onchange=()=>begin('road');
  $('road-class').onchange=()=>{if(mode!=='road')return;game.road_class(Number($('road-class').value));status();};
  $('road-discard').onclick=()=>begin('road');
  function build(){if(!ready)return;if(game.road_build()){transport.syncNetwork();game.parking_rebuild();fixed=0;ready=false;game.road_class(Number($('road-class').value));game.road_begin(Number($('road-shape').value));$('planning-status').textContent='Road built. New roadside parcels are unzoned. Click to start another road.';$('road-build').disabled=true;}else status();}
  $('road-build').onclick=build;
  $('zone-apply').onclick=()=>{if(game.zoning_apply(parcel,Number($('zone-kind').value),$('zone-scope').value==='block'?1:0))status();};
  return {
    pointerDown(event){
      if(!mode)return false;
      if(mode==='permit')return false;
      if(mode==='zone'){parcel=game.zoning_pick(event.clientX,event.clientY);if(parcel>=0)$('zone-kind').value=r(16,parcel,2);status();return true;}
      if(ready)return true;
      game.road_screen_point(fixed,event.clientX,event.clientY);fixed++;
      ready=fixed===($('road-shape').value==='1'?3:2);status();return true;
    },
    pointerMove(event){if(mode!=='road'||!fixed||ready)return false;game.road_screen_point(fixed,event.clientX,event.clientY);status();return true;},
    key(key){if(key==='n'){begin('road');return true;}if(key==='z'){begin('zone');return true;}if(key==='p'){begin('permit');return true;}if(key==='escape'&&mode){close();return true;}if(key==='enter'&&mode==='road'){build();return true;}return false;},
    refresh(){if(mode==='permit')permits();},
    reset:close,
  };
}
