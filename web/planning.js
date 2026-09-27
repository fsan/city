// Map tools own interaction only; Zig validates, prices and commits the network.
import {accessNames, decisionNames, kinds, parkFunding, parkKinds, phaseNames, refusalNames, streetName} from './data.js';
export function createPlanning(game, transport) {
  const $=id=>document.getElementById(id), r=(g,id,f)=>game.read(g,id,f), money=value=>`£${Number(value).toFixed(2)}`, pounds=value=>`£${Math.round(Number(value))}`;
  let mode=null, fixed=0, ready=false, parcel=-1;
  const errors=['Ready to build.','Keep the road inside the map, between 6 and 500 metres.','Road would overlap a building or park.','Grade is too steep.','Insufficient uncommitted funds.','Network capacity reached. Try a shorter road.','A street here has a reserved work order.','Road overlaps another road or makes a very shallow junction.','Connect the road to the existing street network.','The river is in the way. Only the seeded bridges cross it.'];
  const names=['Unzoned','Residential','Commercial','Industrial','Mixed use','Civic / park reserve'];
  const classes=['lane (£18/m, kerbside parking not allowed)','street (£25/m, kerbside parking banded by movement)','avenue (£40/m, wide and fastest, kerbside parking banded by movement)'];
  function close(){mode=null;fixed=0;ready=false;game.road_cancel();game.zoning_show(0);$('planning-panel').hidden=true;$('road-tool').setAttribute('aria-pressed','false');$('zone-tool').setAttribute('aria-pressed','false');$('permit-tool').setAttribute('aria-pressed','false');$('park-tool').setAttribute('aria-pressed','false');}
  function begin(next){transport.cancel();close();mode=next;$('planning-panel').hidden=false;$('road-options').hidden=next!=='road';$('zone-options').hidden=next!=='zone';$('permit-options').hidden=next!=='permit';$('park-options').hidden=next!=='park';$(next==='road'?'road-tool':next==='zone'?'zone-tool':next==='park'?'park-tool':'permit-tool').setAttribute('aria-pressed','true');if(next==='road'){game.road_class(Number($('road-class').value));game.road_begin(Number($('road-shape').value));}else if(next==='zone')game.zoning_show(1);else if(next==='park')parks();else permits();status();}
  // Slice 18/19/20: the development queue, its physical construction stage and
  // the measured sunlight/valuation trade-off. Every open application is one row
  // with its own decision, an approved job reports access, crew, materials and
  // private spend, and a proposal reports the sun it receives and the shadow
  // compensation it would owe its neighbours. Zig still owns every rule; the
  // buttons only report back what the simulation accepted.
  function permits(){
    const retained=Math.max(0,Math.min(m(19),24));let open=0,active=0;const values=[];
    // The queue itself is group 31; the running totals are group 0 fields
    // 70-85, because they belong with the other city metrics.
    const agg=(field)=>r(0,0,field);
    for(let i=0;i<retained;i++){
      const decision=m(14,i), number=m(0,i).toFixed(0), name=kinds[m(5,i)]||'Land use', where=`district ${m(3,i)+1} · parcel ${m(1,i)+1}`;
      if(decision===0){
        open++;
        const estimate=m(22,i)+m(23,i)+m(24,i)+m(25,i)+m(26,i)+m(39,i);
        const shadow=Number(m(38,i))>0?` · shades ${m(40,i).toFixed(0)} lot${m(40,i)===1?'':'s'} for ${money(m(39,i))}`:'';
        values.push([number,name,where,money(m(9,i)),`${accessNames[m(20,i)]||'Unknown access'} · sun ${m(37,i).toFixed(2)}${shadow} · slope ${m(21,i).toFixed(2)} · est. ${money(estimate)}`,`day ${Math.max(1,Math.ceil(m(11,i)/480))}`,
          [{text:'Grant permit',action:()=>{game.development_accept(i);permits();status();}},{text:'Refuse',action:()=>{game.development_refuse(i);permits();status();}}]]);
      }else if(decision===1){
        active++;
        const phase=phaseNames[m(33,i)]||'Under construction';
        values.push([number,name,where,money(m(9,i)),`${phase} · sun ${m(37,i).toFixed(2)}${Number(m(39,i))>0?` · shadow paid ${money(m(39,i))}`:''} · ${Math.round(m(35,i)*100)}% · ${m(30,i).toFixed(2)}/${m(29,i).toFixed(2)} materials · spend ${money(m(28,i))}/${money(m(27,i))}`,`${refusalNames[m(34,i)]||'In progress'}`]);
      }else if(decision===4){
        values.push([number,name,where,money(m(9,i)),`Built · assessed ${money(m(7,i))} · sun ${m(37,i).toFixed(2)} · private spend ${money(m(28,i))}${Number(m(39,i))>0?` · shadow paid ${money(m(39,i))}`:''}`,'Complete']);
      }
    }
    rows('permit-rows',values);
    $('permit-summary').textContent=open===0&&active===0
      ?`No applications or physical jobs. ${agg(77).toFixed(0)} zoned vacant sites remain; private developers only apply where the town is measurably crowded. Mean measured sunlight ${agg(87).toFixed(2)}; ${agg(89).toFixed(0)} of ${r(0,0,14).toFixed(0)} lots are shaded and the assessed roll is ${money(agg(88))}. ${agg(72).toFixed(0)} built so far.`
      :`${open} open, ${active} physical job${active===1?'':'s'} · ${agg(75).toFixed(0)} ever lodged · ${money(agg(76))} levies · ${money(agg(79))} private construction spend · ${agg(80).toFixed(1)} material units delivered · ${agg(77).toFixed(0)} zoned vacant sites remain. Sunlight: mean ${agg(87).toFixed(2)}, ${agg(89).toFixed(0)} shaded lots, assessed ${money(agg(88))}, shadow loss measured ${money(agg(86))} and ${money(agg(85))} paid to neighbours. ${agg(72).toFixed(0)} built, ${agg(73).toFixed(0)} refused, ${agg(74).toFixed(0)} lapsed.`;
  }
  // Numbered item 13: parks and public spaces. A green lot reports its measured
  // condition, the walking catchment it actually serves and the amenity value
  // it lends its neighbours; the running totals are group 0 fields 90-105.
  // Funding pays the maintenance bill as ledger kind 13 and converting a
  // civic-reserve lot pays construction as kind 14; Zig owns both rules.
  function parkSummary(){
    const agg=(field)=>r(0,0,field);
    const coverage=agg(97), funding=parkFunding[Math.round(agg(101))]||'Standard';
    if(document.activeElement!==$('park-funding'))$('park-funding').value=String(Math.round(agg(101)));
    $('park-summary').textContent=`${agg(90).toFixed(0)} public spaces · mean condition ${agg(91).toFixed(0)}% · ${agg(98).toFixed(0)} below standard. Funding ${funding.toLowerCase()}: ${money(agg(96))} paid today of ${money(agg(95))} needed (${(coverage*100).toFixed(0)}% covered), ${money(agg(94))} lifetime maintenance and ${money(agg(103))} construction. ${agg(99).toFixed(0)} homes (${agg(104).toFixed(0)} residents) within walking reach · mean amenity ${agg(100).toFixed(2)} · ${agg(93).toFixed(0)} visits today, ${agg(92).toFixed(0)} ever.`;
    $('park-apply').disabled=parcel<0||r(16,parcel,3)>=0||r(16,parcel,2)!==5;
  }
  function parks(){
    const agg=(field)=>r(0,0,field);
    const count=Math.max(0,agg(90));
    const values=[];
    for(let i=0;i<count;i++){
      // The address the town already gives the lot, so a green space is named
      // by the street it fronts rather than by raw world coordinates. Cells
      // stay short because the planner panel is narrow.
      values.push([
        `${i+1}`,
        kinds[p(1,i)]||'Green space',
        [{text:`${streetName(p(19,i))} ${p(20,i).toFixed(0)} · locate`,action:()=>game.focus(1,p(0,i))}],
        `${p(7,i).toFixed(0)}%`,
        `${p(10,i).toFixed(0)} / ${p(11,i).toFixed(0)}`,
        `${p(12,i).toFixed(0)} m · ${(p(13,i)*100).toFixed(0)}%`,
        `${p(8,i).toFixed(0)} / ${p(9,i).toFixed(0)}`,
        `${p(17,i).toFixed(2)}`,
        `${money(p(15,i))} / ${money(p(14,i))} · ${(p(16,i)*100).toFixed(0)}%`,
      ]);
    }
    rows('park-rows',values);
    parkSummary();
  }
  const p=(field,id)=>game.read(32,id===undefined?0:id,field);
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
      $('planning-status').textContent='Review pending applications and choose Grant or Refuse.';
    }else if(mode==='park'){
      $('park-apply').disabled=parcel<0||r(16,parcel,3)>=0||r(16,parcel,2)!==5;
      const quote=parcel<0?-1:game.parks_quote(parcel,Number($('park-kind').value));
      $('planning-status').textContent=parcel<0?'Select a civic-reserve parcel to convert.':`Parcel ${r(16,parcel,6)} ${streetName(r(16,parcel,5))} · ${r(16,parcel,2)===5?'Civic / park reserve':'not a civic reserve'} · ${r(16,parcel,3)>=0?'Existing building, cannot convert':'Vacant land'}${quote>=0?` · conversion cost ${money(quote)}`:''}`;
    }else if(mode==='zone'){
      $('zone-apply').disabled=parcel<0;
      $('planning-status').textContent=parcel<0?'Select a coloured parcel. Choose a zone, then apply to that parcel or its enclosed block.':`${r(16,parcel,6)} ${streetName(r(16,parcel,5))} · ${names[r(16,parcel,2)]} · ${r(16,parcel,4)>=0?`Block ${r(16,parcel,4)+1}`:'Open roadside frontage'} · ${r(16,parcel,3)>=0?'Existing building retained':'Vacant land'}`;
    }
  }
  $('road-tool').onclick=()=>mode==='road'?close():begin('road');
  $('zone-tool').onclick=()=>mode==='zone'?close():begin('zone');
  $('permit-tool').onclick=()=>mode==='permit'?close():begin('permit');
  $('park-tool').onclick=()=>mode==='park'?close():begin('park');
  $('planning-close').onclick=close;
  $('road-shape').onchange=()=>begin('road');
  $('road-class').onchange=()=>{if(mode!=='road')return;game.road_class(Number($('road-class').value));status();};
  $('road-discard').onclick=()=>begin('road');
  function build(){if(!ready)return;if(game.road_build()){transport.syncNetwork();game.parking_rebuild();fixed=0;ready=false;game.road_class(Number($('road-class').value));game.road_begin(Number($('road-shape').value));$('planning-status').textContent='Road built. New roadside parcels are unzoned. Click to start another road.';$('road-build').disabled=true;}else status();}
  $('road-build').onclick=build;
  $('zone-apply').onclick=()=>{if(game.zoning_apply(parcel,Number($('zone-kind').value),$('zone-scope').value==='block'?1:0))status();};
  $('park-funding').onchange=()=>{if(game.parks_set_funding(Number($('park-funding').value)))parks();}
  $('park-kind').onchange=()=>{parkSummary();status();};
  $('park-apply').onclick=()=>{if(game.parks_create(parcel,Number($('park-kind').value))<0){status();return;}parcel=-1;parks();status();};
  $('park-overlay').onclick=()=>transport.toggleParkCondition();
  return {
    pointerDown(event){
      if(!mode)return false;
      if(mode==='permit')return false;
      if(mode==='zone'){parcel=game.zoning_pick(event.clientX,event.clientY);if(parcel>=0)$('zone-kind').value=r(16,parcel,2);status();return true;}
      if(mode==='park'){parcel=game.zoning_pick(event.clientX,event.clientY);parkSummary();status();return true;}
      if(ready)return true;
      game.road_screen_point(fixed,event.clientX,event.clientY);fixed++;
      ready=fixed===($('road-shape').value==='1'?3:2);status();return true;
    },
    pointerMove(event){if(mode!=='road'||!fixed||ready)return false;game.road_screen_point(fixed,event.clientX,event.clientY);status();return true;},
    key(key){if(key==='n'){begin('road');return true;}if(key==='z'){begin('zone');return true;}if(key==='p'){begin('permit');return true;}if(key==='g'){begin('park');return true;}if(key==='escape'&&mode){close();return true;}if(key==='enter'&&mode==='road'){build();return true;}return false;},
    refresh(){if(mode==='permit')permits();else if(mode==='park')parks();},
    reset:close,
  };
}
