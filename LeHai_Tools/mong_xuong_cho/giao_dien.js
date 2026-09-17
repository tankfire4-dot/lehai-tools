'use strict';
// Sơ đồ kỹ thuật được tính từ thông số; không dùng ảnh phác làm chuẩn kích thước.
const $=id=>document.getElementById(id);
const state={edge:1,side:'none',source:0,done:false,live:false,model:{width:250,height:150,thickness:17.5,receiver:true,available:[true,false,false,false],boards:['1. Tấm đứng','2. Tấm ngang']}};
const names=['Trên','Phải','Dưới','Trái'];
const numeric=['count','head','height','neck','bevel','inset','fit','slackT','slackL','cutter'];
const fmt=n=>Number.isFinite(n)?Number(n.toFixed(3)).toLocaleString('vi-VN'):'—';
function bridge(name,value){if(window.sketchup&&typeof window.sketchup[name]==='function')window.sketchup[name](value);}
function params(){const p={edge:state.edge,side:state.side,source:state.source};numeric.forEach(k=>p[k]=$(k).value.trim()===''?NaN:Number($(k).value));return p;}
function calculate(p,m){
 const width=p.edge%2?m.width:m.height,fit=p.side==='none'?m.thickness:p.fit;
 const offset=p.side==='B'?m.thickness-fit:0,markT=fit+p.slackT,markL=p.head+p.slackL+p.cutter;
 const effective=m.receiver?Math.max(p.head,markL):p.head;
 const maximum=Math.max(1,Math.floor((width-2*p.inset)/(effective+1)+1e-9)+1);
 const centers=Number.isInteger(p.count)&&p.count>0&&p.count<=200?Array.from({length:p.count},(_,i)=>p.count===1?width/2:p.inset+i*(width-2*p.inset)/(p.count-1)):[];
 let error='';
 const used=['count','head','height','neck','bevel',...(p.count===1?[]:['inset']),...(p.side==='none'?[]:['fit']),...(m.receiver?['slackT','slackL','cutter']:[])];
 if(used.some(k=>!Number.isFinite(p[k])))error='Nhập đủ thông số bằng số.';
 else if(!Number.isInteger(p.count)||p.count<1||p.count>200)error='Số mộng phải là số nguyên từ 1 đến 200.';
 else if(p.neck<=0||p.head<=p.neck||p.bevel<0||p.bevel>=p.head/2||p.height<=p.neck+p.bevel)error='Rộng đầu phải lớn hơn cổ; chiều cao phải lớn hơn đường kính cổ + vát.';
 else if(p.count===1&&width-p.head<2)error='Cạnh quá ngắn để chừa 1 mm ở mỗi đầu.';
 else if(p.count>1&&(p.inset-p.head/2<1||p.inset>=width/2))error='Lùi tâm cần chừa mép ít nhất 1 mm và nhỏ hơn nửa chiều dài cạnh.';
 else if(fit<1||fit>m.thickness)error=`Dày tính dấu cần từ 1 đến ${fmt(m.thickness)} mm.`;
 else if(m.receiver&&(p.slackT<0||p.slackL<0||p.cutter<=0||markT-2*p.cutter<1))error='Dấu quá hẹp cho dao này: cần rộng ít nhất 2 × đường kính dao + 1 mm.';
 else if(p.count>1&&p.count>maximum)error=`Không đủ chỗ: tối đa ${maximum} mộng${m.receiver?' và dấu âm':''} với thông số này.`;
 else if(m.receiver&&!m.available[p.edge-1])error=`Cạnh ${p.edge} chưa tiếp giáp mặt tấm nhận. Chọn cạnh được tô trên model hoặc chọn lại cặp tấm.`;
 return {width,fit,offset,markT,markL,maximum,centers,error};
}
window.calculate=calculate;
// ---- Nền vẽ chung ----
function canvas(id){const el=$(id),r=el.getBoundingClientRect(),d=window.devicePixelRatio||1;el.width=Math.round(r.width*d);el.height=Math.round(r.height*d);const c=el.getContext('2d');c.scale(d,d);c.lineWidth=1.3;c.font='12px "DM Sans","Segoe UI",sans-serif';c.textBaseline='alphabetic';return [c,r.width,r.height];}
function line(c,a,b,color='#8f8174',width=1){c.strokeStyle=color;c.lineWidth=width;c.beginPath();c.moveTo(...a);c.lineTo(...b);c.stroke();}
function text(c,s,x,y,color='#6a5a50',align='center',baseline='alphabetic'){c.fillStyle=color;c.textAlign=align;c.textBaseline=baseline;c.fillText(s,x,y);c.textBaseline='alphabetic';}
function poly(c,pts,fill='#f5f0e8',stroke='#655447',width=1.4){c.beginPath();pts.forEach((p,i)=>i?c.lineTo(...p):c.moveTo(...p));c.closePath();if(fill){c.fillStyle=fill;c.fill();}if(stroke){c.strokeStyle=stroke;c.lineWidth=width;c.stroke();}}
function roundRect(c,x,y,w,h,r){c.beginPath();c.moveTo(x+r,y);c.arcTo(x+w,y,x+w,y+h,r);c.arcTo(x+w,y+h,x,y+h,r);c.arcTo(x,y+h,x,y,r);c.arcTo(x,y,x+w,y,r);c.closePath();}
function hatch(c,x,y,w,h,col='#d9d0c4'){c.save();c.beginPath();c.rect(x,y,w,h);c.clip();c.strokeStyle=col;c.lineWidth=1;for(let i=-h;i<w;i+=7){c.beginPath();c.moveTo(x+i,y+h);c.lineTo(x+i+h,y);c.stroke();}c.restore();}
function arrowhead(c,x,y,ang,col){c.save();c.translate(x,y);c.rotate(ang);c.fillStyle=col;c.beginPath();c.moveTo(0,0);c.lineTo(-8,3.5);c.lineTo(-8,-3.5);c.closePath();c.fill();c.restore();}
function numBox(c,x,y,label){c.save();c.font='600 11px "DM Sans","Segoe UI",sans-serif';const tw=c.measureText(label).width,bw=tw+9,bh=16;roundRect(c,x-bw/2,y-bh/2,bw,bh,4);c.fillStyle='#fff';c.fill();c.strokeStyle='#c8bdb0';c.lineWidth=1;c.stroke();c.fillStyle='#92400e';c.textAlign='center';c.textBaseline='middle';c.fillText(label,x,y);c.restore();}
function dimension(c,a,b,label){const col='#b45309';line(c,a,b,col,1.2);const angA=Math.atan2(a[1]-b[1],a[0]-b[0]),angB=Math.atan2(b[1]-a[1],b[0]-a[0]);arrowhead(c,a[0],a[1],angA,col);arrowhead(c,b[0],b[1],angB,col);numBox(c,(a[0]+b[0])/2,(a[1]+b[1])/2,label);}
// Biên 2D một mặt tấm: thân chữ nhật + các răng mộng lồi trên cạnh trên (z tính từ đáy).
function outline(p,width,height,centers){let a=[[0,0],[0,height]];const r=p.neck/2;for(const center of centers){const left=center-p.head/2,right=center+p.head/2;a.push([left,height]);for(let i=1;i<=12;i++){let t=-Math.PI/2+Math.PI*i/12;a.push([left+r*Math.cos(t),height+r+r*Math.sin(t)]);}a.push([left,height+p.height-p.bevel],[left+p.bevel,height+p.height],[right-p.bevel,height+p.height],[right,height+p.height-p.bevel],[right,height+p.neck]);for(let i=1;i<=12;i++){let t=Math.PI/2-Math.PI*i/12;a.push([right-r*Math.cos(t),height+r+r*Math.sin(t)]);}}return a.concat([[width,height],[width,0]]);}
// ---- Mục 1: mặt đứng tấm mộng, nhìn trực diện cạnh đã chọn ----
function drawBoard(p,q){
 const [c,w,h]=canvas('board'),m=state.model;
 const valid=q.centers.length>0&&!q.error&&Number.isFinite(p.head);
 // Vẽ ĐÚNG TỈ LỆ: chiều cao thân = cạnh vuông góc thật của tấm (đọc từ model),
 // để đường kích thước cao không nói dối. Răng mộng lồi thêm trên cạnh đã chọn.
 const W=q.width,boardH=(p.edge%2?m.height:m.width)||40,toothMM=valid?p.height:0,totalMM=boardH+toothMM;
 // Lề chừa 4 nút cạnh (1·Trên/2·Phải/3·Dưới/4·Trái) + đường kích thước hai bên.
 const mL=92,mR=64,mTop=74,mBot=70;
 const s=Math.min((w-mL-mR)/W,(h-mTop-mBot)/totalMM);
 const bw=W*s,x0=mL+((w-mL-mR)-bw)/2,yBot=h-mBot;
 const P=(u,z)=>[x0+u*s,yBot-z*s];
 const path=valid?outline(p,W,boardH,q.centers).map(([u,z])=>P(u,z)):[[0,0],[0,boardH],[W,boardH],[W,0]].map(([u,z])=>P(u,z));
 poly(c,path,'#f4efe7','#6b4226',1.6);
 // Kích thước TẤM VÁN (đọc từ model): cao bên trái · rộng cạnh dưới · dày ghi chú.
 dimension(c,[x0-26,yBot],[x0-26,P(0,boardH)[1]],fmt(boardH));
 dimension(c,[x0,yBot+16],[x0+bw,yBot+16],fmt(W));
 if(!valid){text(c,'Giảm số mộng / lùi tâm để hiện răng',x0+bw/2,P(0,boardH*0.7)[1],'#a08060','center','middle');return;}
 const c0=q.centers[0],cl=q.centers[q.centers.length-1],cm=q.centers[Math.floor((q.centers.length-1)/2)];
 const yTeeth=P(0,boardH+toothMM)[1];
 // Rộng đầu mộng (head) trên một răng giữa.
 dimension(c,[P(cm-p.head/2,0)[0],yTeeth-11],[P(cm+p.head/2,0)[0],yTeeth-11],fmt(p.head));
 // Lùi tâm (inset): từ đầu cạnh tới tâm mộng ngoài cùng.
 if(p.count>1)dimension(c,[P(0,0)[0],yTeeth-32],[P(c0,0)[0],yTeeth-32],fmt(p.inset));
 // Cao mộng (height): dọc bên phải răng cuối.
 const xr=P(cl+p.head/2,0)[0]+16;dimension(c,[xr,P(0,boardH)[1]],[xr,P(0,boardH+toothMM)[1]],fmt(p.height));
}
// ---- Mục 2: mặt cắt qua bề dày, vị trí dấu âm ----
function drawSection(p,q){
 const [c,w,h]=canvas('section'),T=state.model.thickness;
 const mX=68,barH=42,L=w-2*mX,s=L/T,x=mX,y=(h-barH)/2+4;
 poly(c,[[x,y],[x+L,y],[x+L,y+barH],[x,y+barH]],'#efe9e1','#6b4226',1.5);
 hatch(c,x,y,L,barH);
 text(c,'Mặt A',x-22,y+barH/2,'#7c2d12','center','middle');
 text(c,'Mặt B',x+L+22,y+barH/2,'#7c2d12','center','middle');
 dimension(c,[x,y+barH+20],[x+L,y+barH+20],fmt(T));
 if(Number.isFinite(q.markT)&&q.markT>0&&q.fit<=T){
  const left=x+(q.offset-p.slackT/2)*s,notchW=q.markT*s,right=left+notchW,nd=barH*0.52;
  c.fillStyle='#fff';c.fillRect(left,y-0.5,notchW,nd);
  c.strokeStyle='#b45309';c.lineWidth=1.7;c.strokeRect(left,y,notchW,nd);
  dimension(c,[left,y-16],[right,y-16],fmt(q.markT));
  const solidR=T-(q.offset-p.slackT/2)-q.markT,solidL=q.offset-p.slackT/2;
  if(solidR>0.06&&right<x+L-8)dimension(c,[right,y-16],[x+L,y-16],fmt(solidR));
  if(solidL>0.06&&left>x+8)dimension(c,[x,y-16],[left,y-16],fmt(solidL));
  if(p.slackT>0)text(c,`Dư mỗi bên ${fmt(p.slackT/2)} mm`,(left+right)/2,y+nd+12,'#a08060','center','middle');
 }
}
// Biên một dấu mộng âm (dogbone): thân + bốn cung khoét góc.
function mortisePoints(t,L,r){let a=[[0,0],[0,L]];[[r,L,Math.PI,0],[t-r,L,Math.PI,0],[t-r,0,0,-Math.PI],[r,0,0,-Math.PI]].forEach(([x,y,start,end],i)=>{if(i===1)a.push([t-2*r,L]);if(i===2)a.push([t,0]);if(i===3)a.push([2*r,0]);for(let j=1;j<=(i===3?11:12);j++){let z=start+(end-start)*j/12;a.push([x+r*Math.cos(z),y+r*Math.sin(z)]);}});return a;}
// ---- Mục 2 phụ: các dấu âm trên tấm nhận, đủ số mộng ----
function drawMortise(p,q){
 const [c,w,h]=canvas('mortise');
 if(!state.model.receiver){text(c,'Chưa chọn tấm nhận',w/2,h/2,'#6a5a50','center','middle');return;}
 if(!Number.isFinite(q.markT)||q.markT<=0||p.cutter<=0||q.markT<2*p.cutter){text(c,'Kiểm tra độ dày / dao',w/2,h/2,'#b91c1c','center','middle');return;}
 const bx=6,by=8,bw=w-12,bh=h-16;
 poly(c,[[bx,by],[bx+bw,by],[bx+bw,by+bh],[bx,by+bh]],'#fbf7f1','#dccfc0',1.2);
 // Mọi dấu âm giống hệt nhau nên chỉ vẽ MỘT cái phóng to (Khoa 16/09).
 const Lu=p.head+p.slackL,s=Math.min((bw-26)/Lu,(bh-22)/q.markT);
 const a=mortisePoints(q.markT,Lu,p.cutter/2);
 poly(c,a.map(([t,u])=>[w/2+(u-Lu/2)*s,by+bh/2+(t-q.markT/2)*s]),'#f6e2cd','#b45309',1.5);
}
let timer;
function render(){const p=params(),q=calculate(p,state.model);$('inset').disabled=p.count===1;$('fit').disabled=state.side==='none';['slackT','slackL','cutter'].forEach(k=>$(k).disabled=!state.model.receiver);document.querySelectorAll('[data-edge]').forEach(b=>{b.classList.toggle('selected',Number(b.dataset.edge)===state.edge);b.setAttribute('aria-pressed',Number(b.dataset.edge)===state.edge);});document.querySelectorAll('[data-side]').forEach(b=>{b.classList.toggle('selected',b.dataset.side===state.side);b.setAttribute('aria-pressed',b.dataset.side===state.side);});$('edgeTitle').textContent=`Cạnh ${state.edge} · ${names[state.edge-1]}`;$('boardSize').textContent=`${fmt(state.model.width)} × ${fmt(state.model.height)} × ${fmt(state.model.thickness)} mm`;$('contact').textContent=state.model.receiver?(state.model.available[state.edge-1]?'Có mặt tấm nhận tiếp giáp':'Chưa có mặt tiếp giáp tại cạnh này'):'Chỉ tạo mộng · chưa chọn tấm nhận';$('contact').classList.toggle('bad',state.model.receiver&&!state.model.available[state.edge-1]);$('spacing').textContent=`Cạnh dài ${fmt(q.width)} mm. ${p.count>1?`Tối đa ${q.maximum} mộng với thông số này.`:'Một mộng nằm giữa cạnh.'}`;$('rule').textContent=`Chỉ dấu âm thay đổi · Mộng 3D vẫn ${fmt(state.model.thickness)} mm`;$('markSize').textContent=state.model.receiver?`1 dấu phóng to · ${fmt(q.markT)} × ${fmt(q.markL)} mm`:'';$('summary').textContent=`${fmt(p.count)} mộng · ${state.model.receiver?fmt(p.count):0} dấu âm`;$('apply').disabled=!!q.error||state.done;showMessage(q.error||'Xem phần tô trên model trước khi áp dụng.',!!q.error);drawBoard(p,q);drawSection(p,q);drawMortise(p,q);clearTimeout(timer);timer=setTimeout(()=>bridge('preview',JSON.stringify(p)),70);return q;}
window.showMessage=function(message,error=false){$('status').textContent=message;$('status').className=error?'error':'';};
window.chooseEdge=function(edge){if(state.done)return;state.edge=Number(edge);render();};
window.receiveModel=function(m){state.model=m;state.live=!!m.live;state.source=m.source||0;$('source').replaceChildren(...m.boards.map((name,i)=>{let o=document.createElement('option');o.value=i;o.textContent=name;return o;}));$('source').value=state.source;state.edge=m.available.findIndex(Boolean)+1||1;$('demo').textContent=state.live?'Đã nối SketchUp':'Xem giao diện mẫu';render();};
window.applyFinished=function(ok){$('apply').disabled=false;if(ok){state.done=true;document.body.classList.add('done');$('apply').disabled=true;showMessage('Đã áp dụng. Ctrl+Z trong SketchUp để hoàn tác cả lượt.');$('status').className='success';}else{render();showMessage('Chưa áp dụng. Xem thông báo SketchUp, chỉnh lại thông số rồi thử.',true);}};
numeric.forEach(k=>{$(k).addEventListener('input',render);$(k).addEventListener('focus',render);});document.querySelectorAll('[data-edge]').forEach(b=>b.onclick=()=>chooseEdge(b.dataset.edge));document.querySelectorAll('[data-side]').forEach(b=>b.onclick=()=>{state.side=b.dataset.side;render();});$('minus').onclick=()=>{$('count').value=Math.max(1,Number($('count').value)-1);render();};$('plus').onclick=()=>{$('count').value=Number($('count').value)+1;render();};$('source').onchange=()=>{if(state.live){bridge('source',Number($('source').value));}else{showMessage('Chọn tấm thật trong SketchUp để đổi vai trò.',true);$('source').value=state.source;}};$('pick').onclick=()=>{bridge('pick','');showMessage('Bấm gần cạnh mang số 1–4 trên model SketchUp.');};$('cancel').onclick=()=>state.live?bridge('cancel',''):showMessage('Đây là bản xem giao diện. Đóng tab để thoát.');$('apply').onclick=()=>{if(render().error)return;if(!state.live){showMessage('Bản xem giao diện: chưa thay đổi model. Chạy từ Ruby Console để áp dụng.');return;}$('apply').disabled=true;showMessage('Đang tạo mộng và dấu âm…');bridge('apply',JSON.stringify(params()));};window.addEventListener('resize',()=>{if(!state.done)render();});
if(window.sketchup){bridge('ready','');}else{receiveModel({...state.model,live:false});}
// Vẽ lại một lần khi DM Sans tải xong để hộp số/canvas không kẹt ở font dự phòng.
if(document.fonts&&document.fonts.ready)document.fonts.ready.then(()=>{if(!state.done)render();});
