const canvas=document.querySelector('#scene'),ctx=canvas.getContext('2d'),status=document.querySelector('#status'),area=document.querySelector('#area');
let records=[],network=null,geometry=[],paths=[],labels=[],yaw=.5,pitch=.65,zoom=1,center={x:0,y:0,z:0},extent=10,generation=0;
const limit=80*1024*1024;
const finite=p=>p&&['x','y','z'].every(k=>Number.isFinite(p[k])&&Math.abs(p[k])<100000);
const transform=(p,a)=>a?{x:Math.cos(a.yaw)*p.x-Math.sin(a.yaw)*p.z+a.translation.x,y:p.y+a.translation.y,z:Math.sin(a.yaw)*p.x+Math.cos(a.yaw)*p.z+a.translation.z}:p;
function decode(s){const str=atob(s),bytes=new Uint8Array(str.length);for(let i=0;i<str.length;i++)bytes[i]=str.charCodeAt(i);return bytes;}
async function digest(bytes){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');}
const text=new TextDecoder();
document.querySelector('#file').onchange=async e=>{
 const mine=++generation;geometry=[];paths=[];labels=[];draw();
 try {
  const file=e.target.files[0];if(!file)return;if(file.size>limit)throw Error('Maximum file size is 80 MB.');
  status.textContent='Checking file and checksums…';const parcel=JSON.parse(await file.text());
  if(parcel.version!==1||!Array.isArray(parcel.scans)||parcel.scans.length<1||parcel.scans.length>32)throw Error('Unsupported map package.');
  let total=0;const parsed=[];
  for(const scan of parcel.scans){
   const files={};if(!scan.files||!scan.hashes)throw Error('Incomplete package.');
   for(const [name,value]of Object.entries(scan.files)){
    if(!['scan.json','hallway.json','world.arworldmap','mesh.json','room-metadata.json'].includes(name))throw Error('Unknown file entry.');
    const bytes=decode(value);total+=bytes.length;if(total>limit||await digest(bytes)!==scan.hashes[name])throw Error('Size or checksum failed.');
    if(name.endsWith('.json'))files[name]=JSON.parse(text.decode(bytes));
   }
   const draft=files['scan.json'],meshes=files['mesh.json'],route=files['hallway.json'];
   if(!draft||draft.id!==scan.id||!Array.isArray(meshes)||!Array.isArray(draft.landmarks)||draft.landmarks.length>500)throw Error('Invalid recording.');
   let vertices=0,indices=0;
   for(const mesh of meshes){vertices+=mesh.vertices.length;indices+=mesh.triangles.length;if(vertices>500000||indices>3000000||!mesh.vertices.every(finite)||mesh.triangles.length%3||!mesh.triangles.every(i=>Number.isInteger(i)&&i>=0&&i<mesh.vertices.length))throw Error('Invalid or oversized mesh.');}
   if(route&&(!Array.isArray(route.path)||route.path.length>20000||!route.path.every(finite)))throw Error('Invalid route.');
   if(!draft.landmarks.every(l=>finite(l.position)&&typeof l.label==='string'))throw Error('Invalid landmark.');
   parsed.push({id:scan.id,draft,meshes,route}); await new Promise(requestAnimationFrame);
  }
  if(mine!==generation)return;
  records=parsed;network=parcel.network;area.replaceChildren();
  records.forEach((r,i)=>area.add(new Option(r.draft.name+' · '+(r.route?.room?.label??'Area '+(i+1)),String(i))));
  if(network){if(!Array.isArray(network.segments)||network.segments.length>32||new Set(network.segments.map(s=>s.scanID)).size!==network.segments.length||!network.segments.every(s=>records.some(r=>r.id===s.scanID)&&Number.isFinite(s.alignment?.yaw)&&finite(s.alignment?.translation)))throw Error('Invalid building alignment.');area.add(new Option('Connected building (confirmed alignment)','network'));}
  await load();
 } catch(error){records=[];network=null;geometry=[];paths=[];labels=[];draw();status.textContent=error.message;}
};
async function load(){
 const mine=++generation;geometry=[];paths=[];labels=[];status.textContent='Loading measured surfaces…';
 const selection=area.value==='network'?network.segments.map(s=>({record:records.find(r=>r.id===s.scanID),alignment:s.alignment})):[{record:records[Number(area.value)]}];
 const totalTriangles=selection.reduce((n,s)=>n+s.record.meshes.reduce((m,v)=>m+v.triangles.length/3,0),0);
 const stride=Math.max(1,Math.ceil(totalTriangles/30000));
 let count=0;
 for(const {record,alignment}of selection){if(!record)continue;
  for(const mesh of record.meshes){const vertices=mesh.vertices.map(p=>transform(p,alignment));
   // Progressive, bounded triangle display. Unshown surfaces are not filled or invented.

   for(let i=0;i<mesh.triangles.length && count<40000;i+=3*stride){geometry.push([vertices[mesh.triangles[i]],vertices[mesh.triangles[i+1]],vertices[mesh.triangles[i+2]]]);count++;}
   status.textContent=`Loading measured surfaces: ${count.toLocaleString()} triangles…`;
   await new Promise(requestAnimationFrame);if(mine!==generation)return;
  }
  if(record.route)paths.push(record.route.path.map(p=>transform(p,alignment)));
  labels.push(...record.draft.landmarks.map(l=>({text:l.label,p:transform(l.position,alignment)})));
 }
 const all=geometry.flat();if(all.length){const min={x:Infinity,y:Infinity,z:Infinity},max={x:-Infinity,y:-Infinity,z:-Infinity};for(const p of all)for(const k of ['x','y','z']){min[k]=Math.min(min[k],p[k]);max[k]=Math.max(max[k],p[k]);}center={x:(min.x+max.x)/2,y:(min.y+max.y)/2,z:(min.z+max.z)/2};extent=Math.max(1,max.x-min.x,max.y-min.y,max.z-min.z);}
 zoom=1;draw();status.textContent=`${count.toLocaleString()} displayed measured triangles. Large meshes use a reduced preview. Recorded paths require local review before guidance.`;
 document.querySelector('#labels').textContent=labels.map(l=>l.text).join(' · ');
}
function project(p){let x=p.x-center.x,y=p.y-center.y,z=p.z-center.z;const a=Math.cos(yaw)*x-Math.sin(yaw)*z,b=Math.sin(yaw)*x+Math.cos(yaw)*z;const scale=Math.min(canvas.width,canvas.height)*.8/extent*zoom;return{x:canvas.width/2+a*scale,y:canvas.height/2+(-y*Math.cos(pitch)+b*Math.sin(pitch))*scale,depth:b*Math.cos(pitch)+y*Math.sin(pitch)};}
function draw(){canvas.width=canvas.clientWidth*devicePixelRatio;canvas.height=canvas.clientHeight*devicePixelRatio;ctx.clearRect(0,0,canvas.width,canvas.height);
 const triangles=geometry.map(t=>t.map(project)).sort((a,b)=>(b[0].depth+b[1].depth+b[2].depth)-(a[0].depth+a[1].depth+a[2].depth));
 ctx.fillStyle='#79456b24';ctx.strokeStyle='#79456b55';ctx.lineWidth=.6*devicePixelRatio;
 for(const t of triangles){ctx.beginPath();ctx.moveTo(t[0].x,t[0].y);ctx.lineTo(t[1].x,t[1].y);ctx.lineTo(t[2].x,t[2].y);ctx.closePath();ctx.fill();ctx.stroke();}
 ctx.strokeStyle='#cc5f11';ctx.lineWidth=3*devicePixelRatio;for(const path of paths){ctx.beginPath();path.map(project).forEach((p,i)=>i?ctx.lineTo(p.x,p.y):ctx.moveTo(p.x,p.y));ctx.stroke();}
 ctx.fillStyle='#41263e';ctx.font=`${14*devicePixelRatio}px system-ui`;for(const label of labels){const p=project(label.p);ctx.fillText(label.text,p.x,p.y);}
}
area.onchange=load;document.querySelector('#reset').onclick=()=>{yaw=.5;pitch=.65;zoom=1;draw();};
const touches=new Map();let pinch=0;
canvas.onpointerdown=e=>{canvas.setPointerCapture(e.pointerId);touches.set(e.pointerId,[e.clientX,e.clientY]);};
canvas.onpointermove=e=>{const old=touches.get(e.pointerId);if(!old)return;touches.set(e.pointerId,[e.clientX,e.clientY]);if(touches.size===2){const [a,b]=[...touches.values()],d=Math.hypot(a[0]-b[0],a[1]-b[1]);if(pinch)zoom=Math.max(.2,Math.min(8,zoom*d/pinch));pinch=d;}else{yaw+=(e.clientX-old[0])*.008;pitch=Math.max(-1.5,Math.min(1.5,pitch+(e.clientY-old[1])*.008));}draw();};
canvas.onpointerup=canvas.onpointercancel=e=>{touches.delete(e.pointerId);pinch=0;};canvas.onwheel=e=>{e.preventDefault();zoom=Math.max(.2,Math.min(8,zoom*Math.exp(-e.deltaY*.001)));draw();};window.onresize=draw;draw();
