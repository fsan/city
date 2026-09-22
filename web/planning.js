// Map tools own interaction only; Zig validates, prices and commits the network.
import {streetName} from './data.js';
export function createPlanning(game, transport) {
  const $=id=>document.getElementById(id), r=(g,id,f)=>game.read(g,id,f);
  let mode=null, fixed=0, ready=false, parcel=-1;
  const errors=['Ready to build.','Keep the road inside the map, between 6 and 500 metres.','Road would overlap a building or park.','Grade is too steep.','Insufficient uncommitted funds.','Network capacity reached. Try a shorter road.','A street here has a reserved work order.','Road overlaps another road or makes a very shallow junction.','Connect the road to the existing street network.'];
  const names=['Unzoned','Residential','Commercial','Industrial','Mixed use','Civic / park reserve'];
  const classes=['lane (£18/m, kerbside parking not allowed)','street (£25/m, kerbside parking banded by movement)','avenue (£40/m, wide and fastest, kerbside parking banded by movement)'];
  function close(){mode=null;fixed=0;ready=false;game.road_cancel();game.zoning_show(0);$('planning-panel').hidden=true;$('road-tool').setAttribute('aria-pressed','false');$('zone-tool').setAttribute('aria-pressed','false');}
  function begin(next){transport.cancel();close();mode=next;$('planning-panel').hidden=false;$('road-options').hidden=next!=='road';$('zone-options').hidden=next!=='zone';$(next==='road'?'road-tool':'zone-tool').setAttribute('aria-pressed','true');if(next==='road'){game.road_class(Number($('road-class').value));game.road_begin(Number($('road-shape').value));}else game.zoning_show(1);status();}
  function status(){
    if(mode==='road'){
      const curved=$('road-shape').value==='1';
      $('planning-status').textContent=fixed===0?`${classes[Number($('road-class').value)]}. Click a start point. Existing streets and junctions snap automatically.`:!ready?(curved&&fixed===1?'Click the bend control point, then choose the end.':'Choose the end point. Green is buildable; red shows a conflict.'):`${r(15,0,2).toFixed(0)} m · £${r(15,0,1).toFixed(2)} · ${errors[r(15,0,0)]}`;
      $('road-build').disabled=!ready||r(15,0,0)!==0;
    }else if(mode==='zone'){
      $('zone-apply').disabled=parcel<0;
      $('planning-status').textContent=parcel<0?'Select a coloured parcel. Choose a zone, then apply to that parcel or its enclosed block.':`${r(16,parcel,6)} ${streetName(r(16,parcel,5))} · ${names[r(16,parcel,2)]} · ${r(16,parcel,4)>=0?`Block ${r(16,parcel,4)+1}`:'Open roadside frontage'} · ${r(16,parcel,3)>=0?'Existing building retained':'Vacant land'}`;
    }
  }
  $('road-tool').onclick=()=>mode==='road'?close():begin('road');
  $('zone-tool').onclick=()=>mode==='zone'?close():begin('zone');
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
      if(mode==='zone'){parcel=game.zoning_pick(event.clientX,event.clientY);if(parcel>=0)$('zone-kind').value=r(16,parcel,2);status();return true;}
      if(ready)return true;
      game.road_screen_point(fixed,event.clientX,event.clientY);fixed++;
      ready=fixed===($('road-shape').value==='1'?3:2);status();return true;
    },
    pointerMove(event){if(mode!=='road'||!fixed||ready)return false;game.road_screen_point(fixed,event.clientX,event.clientY);status();return true;},
    key(key){if(key==='n'){begin('road');return true;}if(key==='z'){begin('zone');return true;}if(key==='escape'&&mode){close();return true;}if(key==='enter'&&mode==='road'){build();return true;}return false;},
    reset:close,
  };
}
