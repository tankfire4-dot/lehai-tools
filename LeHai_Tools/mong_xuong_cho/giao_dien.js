'use strict';
// Bảng phân loại tấm ngàm / tấm nhận. Ruby tự ghép cặp theo tiếp giáp rồi gửi danh sách qua
// receiveModel; bảng chỉ giữ thông số từng cặp (số mộng, lùi tâm, thu dấu) + hình mộng dùng chung.
const $=id=>document.getElementById(id);
const shapeKeys=['head','height','neck','bevel','slackT','slackL','cutter'];
const state={live:false,mode:'ngam',busy:false,focus:null,rows:{},model:{tenons:[],receivers:[],pairs:[]}};
const SH={head:35,height:11,neck:6,bevel:1,slackT:.2,slackL:.2,cutter:6};
const FIT=15; // dày sau phay mặc định (Khoa 03/10)
// Dày sau phay có layer Aspire (dao mẫu theo TÊN layer — Khoa 04/10). Trùng TAG_PHAY trong main.rb: thêm độ dày
// mới phải thêm cả hai chỗ + dao mẫu trong Aspire. Số khác → báo đỏ, không cho Áp dụng.
const PHAY_MM=[15,13];
// Bên trong lưu MẶT GIỮ (A/B — Ruby + tấm đã làm dùng giá trị này); chữ hiện ra nói MẶT PHAY = mặt còn lại
// (Khoa 04/10: "giữ mặt" bắt người dùng lật thêm một lớp trong đầu).
const KIEU={none:'Không phay',A:'Phay mặt B',B:'Phay mặt A'};
// Kiểu mộng chung (Khoa 03/10: người dùng chỉ quan tâm preview + không phay / phay một mặt) — nhớ theo máy
function docKieu(){try{const k=localStorage.getItem('mxc.kieu');return KIEU[k]?k:'none';}catch(e){return 'none';}}
state.kieu=docKieu();
// 3 kiểu Khoa hay dùng (chốt 04/10): bấm = điền sẵn dư dày / dư dài / dày sau phay + bật tắt phay.
// Chữ hiện ra dùng PHAY, không dùng THU (Khoa 04/10 — một từ cho một việc); tên biến cũ (thu, fit) giữ nguyên. Không khóa ô
// nào: sửa tay thì nút tắt sáng, hiện "Tùy chỉnh". Phay còn 13 = mỏng nhất dao Ø6 còn phay được dấu âm
// (dấu rộng 13 + 0,2 ≥ hai tai 6 + 6 + 1 mm đoạn thẳng — xem check() "Dấu quá hẹp cho dao này").
// Không phay lấy dư 0,2 / 0,3 như mộng Hộc Kéo (tao_modul_nhanh/hoc_keo.rb HINH_MONG).
const PRESET=[{thu:false,slackT:.2,slackL:.3},{thu:true,fit:15,slackT:.2,slackL:.2},{thu:true,fit:13,slackT:.2,slackL:.2}];
// Mặt giữ khi thu (A/B) chọn riêng, nhớ theo máy; đổi kiểu mộng không đổi mặt giữ. Nút trên bảng ghi MẶT PHAY:
// nút "A" mang data-mat="B" (phay A = giữ B).
function docMat(){try{return localStorage.getItem('mxc.mat')==='B'?'B':'A';}catch(e){return 'A';}}
state.mat=state.kieu==='none'?docMat():state.kieu;
const DEMO={mode:'ngam',tenons:[{label:'Ngàm 1 · bạ trên',faceW:600,faceH:50,thickness:17.5,mirror:false,done:[]},{label:'Ngàm 2 · bạ dưới',faceW:600,faceH:120,thickness:17.5,mirror:false,done:[{edge:2,count:2,inset:30,side:'none',fit:14,...SH}]},{label:'Ngàm 3 · hông',problem:'đã có mộng/khoét nhưng không phải do tool này làm'}],receivers:[{label:'Nhận 1 · hông trái'},{label:'Nhận 2 · hông phải'}],pairs:[
 {key:'0-4',ti:0,tenon:'Ngàm 1 · bạ trên',edge:4,edgeName:'trái',receiver:'Nhận 1 · hông trái',state:'moi',length:50,thickness:17.5},
 {key:'0-2',ti:0,tenon:'Ngàm 1 · bạ trên',edge:2,edgeName:'phải',receiver:'Nhận 2 · hông phải',state:'moi',length:50,thickness:17.5},
 {key:'1-4',ti:1,tenon:'Ngàm 2 · bạ dưới',edge:4,edgeName:'trái',receiver:'Nhận 1 · hông trái',state:'moi',length:120,thickness:17.5},
 {key:'1-2',ti:1,tenon:'Ngàm 2 · bạ dưới',edge:2,edgeName:'phải',receiver:'Nhận 2 · hông phải',state:'chi_dau',length:120,thickness:17.5,stored:{count:2,inset:30,side:'none',fit:14,...SH}}]};
const fmt=n=>Number.isFinite(n)?Number(n.toFixed(3)).toLocaleString('vi-VN'):'—';
const num=v=>String(v).trim()===''?NaN:Number(v);
function bridge(name,value){if(window.sketchup&&typeof window.sketchup[name]==='function')window.sketchup[name](value);}
function el(tag,cls,text){const e=document.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=text;return e;}
function shape(){const s={};shapeKeys.forEach(k=>s[k]=num($(k).value));return s;}
// Nhớ hình mộng dùng chung giữa các lần mở bảng (theo máy). Không có bộ nhớ thì dùng mặc định.
function saveShape(){try{localStorage.setItem('mxc.shape.v2',JSON.stringify(shape()));}catch(e){}}
function loadShape(){try{const s=JSON.parse(localStorage.getItem('mxc.shape.v2')||'null');if(s)shapeKeys.forEach(k=>{if(Number.isFinite(s[k]))$(k).value=s[k];});}catch(e){}}

// Lỗi của một cặp MỚI, hoặc ''. Cùng luật với plan_edge bên Ruby.
function check(r,p,s){
 if(p.block)return `Tấm ngàm ${p.block}.`;   // Ruby chặn: mọc mộng sẽ xóa mất thứ không dựng lại được
 const L=p.length,T=p.thickness,fit=r.side==='none'?T:r.fit;
 const vals=[r.count,...shapeKeys.map(k=>s[k]),...(r.count===1?[]:[r.inset]),...(r.side==='none'?[]:[r.fit])];
 if(vals.some(v=>!Number.isFinite(v)))return 'Nhập đủ thông số bằng số.';
 if(!Number.isInteger(r.count)||r.count<1||r.count>200)return 'Số mộng phải là số nguyên từ 1.';
 if(s.neck<=0||s.head<=s.neck||s.bevel<0||s.bevel>=s.head/2||s.height<=s.neck+s.bevel)return 'Hình mộng: rộng đầu phải lớn hơn cổ; cao phải lớn hơn cổ + vát.';
 if(r.count===1&&L-s.head<2)return `Đầu dài ${fmt(L)} mm quá ngắn cho mộng rộng ${fmt(s.head)} mm.`;
 if(r.count>1&&(r.inset-s.head/2<1||r.inset>=L/2))return `Lùi tâm cần từ ${fmt(s.head/2+1)} đến dưới ${fmt(L/2)} mm (đầu dài ${fmt(L)} mm).`;
 if(fit<1||fit>T)return `Dày sau phay cần từ 1 đến ${fmt(T)} mm.`;
 if(r.side!=='none'&&T-fit>0.001&&!PHAY_MM.some(m=>Math.abs(fit-m)<0.01))return `Chưa có layer Aspire cho dày sau phay ${fmt(fit)} mm — chỉ làm ${PHAY_MM.join(' hoặc ')} mm.`;
 const markT=fit+s.slackT,markL=s.head+s.slackL+s.cutter;
 if(s.slackT<0||s.slackL<0||s.cutter<=0||markT-2*s.cutter<1)return 'Dấu quá hẹp cho dao này: cần rộng ít nhất 2 × Ø dao + 1 mm.';
 if(r.count>1){const max=Math.floor((L-2*r.inset)/(Math.max(s.head,markL)+1)+1e-9)+1;if(r.count>max)return `Không đủ chỗ: tối đa ${max} mộng trên đầu dài ${fmt(L)} mm.`;}
 return '';
}
// Số mộng đề xuất theo độ dài đầu: ngắn dưới 150 mm thì 1 mộng giữa, dài thì ~1 mộng / 300 mm.
function suggest(p,base){let n=p.length<150?1:Math.max(2,Math.round(p.length/300)+1);const s=shape();while(n>1&&check({...base,count:n},p,s))n--;return n;}

// Nhãn Ruby "Ngàm 1 · PNmas_tuaothang_modul01_dotke2" → {tag:'Ngàm 1', name:'dotke2'}: bỏ phần đầu tên
// mọi tấm cùng có (tên module), cắt ở dấu _ - . hoặc khoảng trắng. Tên đầy đủ vẫn hiện khi rê chuột.
let namePrefix='';
function splitLabel(l){const i=String(l).indexOf(' · ');return i<0?{tag:String(l),name:''}:{tag:l.slice(0,i),name:l.slice(i+3)};}
function computePrefix(m){
 const names=m.tenons.concat(m.receivers).map(b=>splitLabel(b.label).name).filter(Boolean);
 if(names.length<2){namePrefix='';return;}
 let pre=names.reduce((a,n)=>{let i=0;while(i<a.length&&i<n.length&&a[i]===n[i])i++;return a.slice(0,i);});
 const cut=Math.max(...['_','-','.',' '].map(c=>pre.lastIndexOf(c)));
 pre=cut>=0?pre.slice(0,cut+1):'';
 namePrefix=names.every(n=>n.length>pre.length)?pre:'';
}
function short(l){const {tag,name}=splitLabel(l);return {tag,name:name.startsWith(namePrefix)?name.slice(namePrefix.length):name};}
function shortText(l){const s=short(l);return s.name?`${s.tag} ${s.name}`:s.tag;}
function chip(b){const s=short(b.label),li=el('li',b.problem?'bad':'');li.title=b.problem?`${b.label} — ${b.problem}`:b.label;
 li.append(el('b',null,s.tag));if(s.name)li.append(el('span',null,s.name));if(b.problem)li.append(el('i',null,'!'));return li;}

function renderLists(){
 const m=state.model;computePrefix(m);
 [['ngam',m.tenons,'listNgam','countNgam','roleNgam'],['nhan',m.receivers,'listNhan','countNhan','roleNhan']].forEach(([role,list,listId,countId,boxId])=>{
  const ul=$(listId);ul.replaceChildren();
  if(!list.length)ul.append(el('li','none','Chưa có tấm nào'));
  list.forEach(b=>ul.append(chip(b)));
  $(countId).textContent=list.length;
  $(boxId).classList.toggle('active',state.mode===role);
 });
 // Tấm bị loại: gom một chỗ, mỗi tấm một dòng, thay vì nhét câu dài vào thẻ tên.
 const bad=m.tenons.concat(m.receivers).filter(b=>b.problem),pl=$('problemList');pl.replaceChildren();
 bad.forEach(b=>{const li=el('li');li.append(el('b',null,shortText(b.label)),document.createTextNode(` — ${b.problem}`));pl.append(li);});
 $('problems').hidden=!bad.length;
 $('unscale').hidden=!bad.some(b=>b.scaled);
}

function buildRows(){
 const tb=$('rows');tb.replaceChildren();
 document.querySelectorAll('[data-all]').forEach(i=>i.value='');   // danh sách đổi → dòng Tất cả về trống, khỏi tưởng dòng mới đã nhận số cũ
 for(const p of state.model.pairs){
  if(p.state==='moi'&&!state.rows[p.key]){const base={on:true,inset:50,side:state.kieu,fit:Math.min(fitChung(),p.thickness)};state.rows[p.key]={...base,count:soMongChung()!==null?soMongChung():suggest(p,base)};}
  if(p.state==='chi_dau'&&!state.rows[p.key])state.rows[p.key]={on:true};
  const r=p.state==='moi'?state.rows[p.key]:{...p.stored,on:p.state==='chi_dau'&&state.rows[p.key].on};
  const tr=el('tr');tr.dataset.key=p.key;
  const on=el('td','c-on'),box=el('input');box.type='checkbox';box.dataset.k='on';box.checked=!!r.on;box.disabled=p.state==='da_lam';on.append(box);
  const who=el('td','pair'),a=short(p.tenon),b=short(p.receiver),l1=el('div');
  l1.append(el('b',null,a.tag),el('span','edge',` đầu ${p.edgeName} → `),el('b',null,b.tag));
  if(p.state!=='moi')l1.append(el('span',`tag ${p.state}`,p.state==='da_lam'?'đã làm':'chỉ đóng dấu'));
  who.append(l1);if(a.name||b.name)who.append(el('div','names',`${a.name||'—'} → ${b.name||'—'}`));
  who.title=`${p.tenon}, đầu ${p.edgeName} → ${p.receiver}`;
  const cell=(k,attrs,cls)=>{const td=el('td','num'+(cls?' '+cls:'')),i=el('input');i.type='number';i.dataset.k=k;Object.assign(i,attrs);i.value=Number.isFinite(r[k])?r[k]:'';td.append(i);return td;};
  const sideTd=el('td'),sel=el('select');sideTd.append(el('span','txt'));sel.dataset.k='side';[['none','Không phay'],['B','Phay mặt A'],['A','Phay mặt B']].forEach(([v,t])=>{const o=el('option',null,t);o.value=v;sel.append(o);});sel.value=r.side||'none';sideTd.append(sel);
  const goTd=el('td','c-go');if(p.state!=='moi'){const g=el('button','ghost','Gỡ');g.dataset.go=p.key;g.title='Gỡ mộng đầu này: cắt răng, xoá dấu phay + dấu âm của đầu đó';goTd.append(g);}
  tr.append(on,who,el('td','num',fmt(p.length)),cell('count',{min:1,step:1}),cell('inset',{min:1,step:1},'c-nc'),sideTd,cell('fit',{min:1,step:.1},'c-nc'),goTd);
  ghiTxt(tr,r);
  if(p.state!=='moi'){tr.querySelectorAll('input[type=number],select').forEach(i=>i.disabled=true);blankUnused(tr,r);}
  const err=el('tr','err');err.hidden=true;const etd=el('td');etd.colSpan=8;err.append(etd);
  tb.append(tr,err);
 }
 const m=state.model;
 $('empty').textContent=m.pairs.length?'':!m.tenons.length?'Chưa có tấm ngàm nào.':!m.receivers.length?'Chưa có tấm nhận nào.':'Chưa thấy đầu tấm ngàm nào áp phẳng vào tấm nhận. Kiểm tra hai tấm có chạm sát nhau không.';
 markFocus();
}

// Ô không dùng tới thì để trống thay vì hiện số mờ: 1 mộng → lùi tâm "giữa"; không phay → dày sau phay "—".
// Giá trị vẫn nằm trong state.rows, bật lại là hiện lại.
function blankUnused(tr,r){
 [['inset',r.count===1,'giữa'],['fit',(r.side||'none')==='none','—']].forEach(([k,unused,ph])=>{const i=tr.querySelector(`[data-k=${k}]`);if(!i)return;
  if(unused){i.value='';i.placeholder=ph;}else if(i.value===''&&Number.isFinite(r[k]))i.value=r[k];});
}
// Bảng gọn: kiểu hiện dạng CHỮ; mở "Tùy chỉnh (phụ)" mới hiện ô chọn. Số mộng luôn là ô nhập.
function ghiTxt(tr,r){const t=tr.querySelector('.txt');if(t)t.textContent=KIEU[r.side||'none'];}
// Dày sau phay chung: ô hiện ngay cạnh 4 thông số khi chọn Phay một mặt (trước nằm khuất trong Tùy chỉnh)
// Số mộng chung ở khung chính (Khoa 04/10: trước nằm khuất trong Tùy chỉnh). Trống = tự tính theo chiều dài
// từng đầu (suggest); có số = mọi cặp MỚI đang tick lấy số đó, kể cả cặp thêm sau. Cặp đã làm giữ số cũ.
function soMongChung(){const v=num($('countAll').value);return Number.isFinite(v)?v:null;}
function datSoMong(){const v=soMongChung();
 for(const p of state.model.pairs){const r=state.rows[p.key];if(p.state!=='moi'||!r||!r.on)continue;r.count=v!==null?v:suggest(p,r);
  const i=document.querySelector(`#rows tr[data-key="${p.key}"] [data-k=count]`);if(i)i.value=Number.isFinite(r.count)?r.count:'';}
 validate();}
function fitChung(){const v=num($('fitAll').value);return Number.isFinite(v)?v:FIT;}
function datFit(){const v=fitChung();try{localStorage.setItem('mxc.fit',String(v));}catch(e){}
 for(const p of state.model.pairs){const r=state.rows[p.key];if(p.state!=='moi'||!r||!r.on)continue;r.fit=Math.min(v,p.thickness);
  const f=document.querySelector(`#rows tr[data-key="${p.key}"] [data-k=fit]`);if(f)f.value=r.fit;}
 validate();}
function datKieu(k){state.kieu=k;try{localStorage.setItem('mxc.kieu',k);}catch(e){}
 if(k!=='none'){state.mat=k;try{localStorage.setItem('mxc.mat',k);}catch(e){}}
 $('fitBox').hidden=k==='none';
 for(const p of state.model.pairs){const r=state.rows[p.key];if(p.state!=='moi'||!r||!r.on)continue;r.side=k;if(k!=='none')r.fit=Math.min(fitChung(),p.thickness);
  const tr=document.querySelector(`#rows tr[data-key="${p.key}"]`);if(tr){const sel=tr.querySelector('[data-k=side]');if(sel)sel.value=k;const f=tr.querySelector('[data-k=fit]');if(f&&Number.isFinite(r.fit))f.value=r.fit;}}
 validate();}
function apKieu(i){const p=PRESET[i];$('slackT').value=p.slackT;$('slackL').value=p.slackL;saveShape();demChinh();
 if(p.thu){$('fitAll').value=p.fit;datKieu(state.mat);datFit();}else datKieu('none');}
function datMat(m){state.mat=m;try{localStorage.setItem('mxc.mat',m);}catch(e){}if(state.kieu!=='none')datKieu(m);else toKieu();}
// Tô nút kiểu đang khớp; không khớp kiểu nào thì hiện "Tùy chỉnh". Công tắc A/B chỉ hiện khi đang thu.
function toKieu(){const s=shape(),thu=state.kieu!=='none',f=fitChung(),eq=(a,b)=>Math.abs(a-b)<1e-9;
 const i=PRESET.findIndex(p=>p.thu===thu&&eq(p.slackT,s.slackT)&&eq(p.slackL,s.slackL)&&(!p.thu||eq(p.fit,f)));
 document.querySelectorAll('#kieuBox [data-preset]').forEach(b=>b.classList.toggle('on',+b.dataset.preset===i));
 $('tuyChinh').hidden=i>=0;$('matBox').hidden=!thu;
 document.querySelectorAll('#matBox [data-mat]').forEach(b=>b.classList.toggle('on',b.dataset.mat===state.mat));}
function demChinh(){const n=['neck','bevel','cutter'].filter(k=>num($(k).value)!==SH[k]).length;$('dachinh').textContent=n?'· đã chỉnh '+n+' ô':'';}
function markFocus(){document.querySelectorAll('#rows tr[data-key]').forEach(tr=>tr.classList.toggle('focus',tr.dataset.key===state.focus));}

// Kiểm lại mọi cặp, bật/tắt ô nhập, cập nhật tóm tắt. Không dựng lại bảng để giữ con trỏ nhập.
function validate(){
 toKieu();
 const s=shape();let first='',count=0,marks=0,newTeeth=0;
 for(const p of state.model.pairs){
  const tr=document.querySelector(`#rows tr[data-key="${p.key}"]`);if(!tr)continue;
  const err=tr.nextElementSibling;
  if(p.state==='da_lam'){tr.classList.add('off');ghiTxt(tr,{...p.stored});continue;}
  const r=state.rows[p.key],on=!!r.on;tr.classList.toggle('off',!on);
  let e='';
  if(p.state==='moi'){
   tr.querySelectorAll('input[type=number],select').forEach(i=>i.disabled=!on);
   if(on){tr.querySelector('[data-k=inset]').disabled=r.count===1;tr.querySelector('[data-k=fit]').disabled=r.side==='none';e=check(r,p,s);}
   blankUnused(tr,r);ghiTxt(tr,r);
   tr.querySelector('[data-k=count]').classList.toggle('bad',!!e);
  }
  err.hidden=!e;err.firstChild.textContent=e;tr.classList.toggle('row-error',!!e);
  if(on){count++;const n=p.state==='moi'?r.count:p.stored.count;marks+=Number.isFinite(n)?n:0;if(p.state==='moi')newTeeth+=Number.isFinite(n)?n:0;}
  if(e&&!first)first=`${short(p.tenon).tag}, đầu ${p.edgeName}: ${e}`;
 }
 $('summary').textContent=count?`${count} cặp sẽ làm · ${marks} dấu âm${newTeeth?` · ${newTeeth} mộng mới`:''}`:'Chưa có cặp nào để làm';
 $('apply').disabled=!count||!!first||state.busy;
 const bad=state.model.tenons.find(t=>t.problem)||state.model.receivers.find(t=>t.problem);
 drawPreview();
 showMessage(first||(bad?'Có tấm bị loại — xem khung đỏ phía trên.':count?'Bấm từng dòng để soát cặp trên model rồi Áp dụng.':''),!!first||!!bad);
}

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
// Biên một dấu mộng âm (dogbone): thân + bốn cung khoét góc.
function mortisePoints(t,L,r){let a=[[0,0],[0,L]];[[r,L,Math.PI,0],[t-r,L,Math.PI,0],[t-r,0,0,-Math.PI],[r,0,0,-Math.PI]].forEach(([x,y,start,end],i)=>{if(i===1)a.push([t-2*r,L]);if(i===2)a.push([t,0]);if(i===3)a.push([2*r,0]);for(let j=1;j<=(i===3?11:12);j++){let z=start+(end-start)*j/12;a.push([x+r*Math.cos(z),y+r*Math.sin(z)]);}});return a;}
// ---- Xem trước cặp đang chọn ----
// Mặt tấm ngàm NHÌN TỪ MẶT A, đúng chiều thật (không xoay đầu đang chọn lên trên). Hệ mặt tấm:
// x = chiều dài u (0..W), y = chiều cao z (0..H). Đầu e đi theo đúng thứ tự dựng bên Ruby.
function mapEdge(e,u,z,W,H){return e===1?[u,H+z]:e===2?[W+z,H-u]:e===3?[W-u,-z]:[-z,u];}
// Răng mộng dọc một đầu dài L: (u, z) với z tính ra ngoài từ mép; bỏ hai điểm góc.
function toothProfile(r,s,L){
 const n=r.count,centers=n===1?[L/2]:Array.from({length:n},(_,i)=>r.inset+i*(L-2*r.inset)/(n-1)),rad=s.neck/2,a=[];
 for(const c of centers){const l=c-s.head/2,rt=c+s.head/2;a.push([l,0]);
  for(let i=1;i<=12;i++){const t=-Math.PI/2+Math.PI*i/12;a.push([l+rad*Math.cos(t),rad+rad*Math.sin(t)]);}
  a.push([l,s.height-s.bevel],[l+s.bevel,s.height],[rt-s.bevel,s.height],[rt,s.height-s.bevel],[rt,s.neck]);
  for(let i=1;i<=12;i++){const t=Math.PI/2-Math.PI*i/12;a.push([rt-rad*Math.cos(t),rad+rad*Math.sin(t)]);}}
 return a;
}
// Thông số thật của cặp để vẽ: cặp mới lấy bảng + hình chung; cặp cũ lấy đúng số đã ghi.
function pairSpec(p){if(p.state==='moi')return {r:state.rows[p.key],s:shape()};const st=p.stored||{};return {r:st,s:st};}
// Các đầu có mộng của một tấm ngàm: đầu đã làm từ trước + cặp mới đang bật và hợp lệ.
function tenonEdges(ti){
 const t=state.model.tenons[ti]||{},out={};
 (t.done||[]).forEach(d=>out[d.edge]={r:d,s:d,kind:'done'});
 state.model.pairs.filter(p=>p.ti===ti&&p.state==='moi'&&state.rows[p.key]&&state.rows[p.key].on).forEach(p=>{const sp=pairSpec(p);if(!check(sp.r,p,sp.s))out[p.edge]={...sp,kind:'new'};});
 return out;
}
function drawFace(id,p,zoom){
 // Khung "Cả tấm" cao theo tỷ lệ tấm (120–300px): cao cố định 120px làm tấm vuông/tấm cao co còn một mẩu.
 if(!zoom){const t0=state.model.tenons[p.ti]||{},el=$(id);if(Number.isFinite(t0.faceW)&&t0.faceW>0){const k=(t0.faceH+40)/(t0.faceW+40);el.style.height=Math.round(Math.min(300,Math.max(120,el.getBoundingClientRect().width*k)))+'px';}}
 const [c,w,h]=canvas(id),t=state.model.tenons[p.ti]||{};
 if(!Number.isFinite(t.faceW)){text(c,'Không có dữ liệu mặt tấm',w/2,h/2,'#8a7f75','center','middle');return;}
 const W=t.faceW,H=t.faceH,edges=tenonEdges(p.ti),fx=x=>t.mirror?W-x:x;
 const ring=[];for(let e=1;e<=4;e++){ring.push(mapEdge(e,0,0,W,H));const d=edges[e];if(d)toothProfile(d.r,d.s,e%2?W:H).forEach(([u,z])=>ring.push(mapEdge(e,u,z,W,H)));}
 const pts=ring.map(([x,y])=>[fx(x),y]);
 // Khung nhìn: cả tấm, hoặc phóng vào MỘT mộng ở giữa đầu đang chọn (thấy rõ cổ, vát).
 const sp=pairSpec(p),L=p.edge%2?W:H,out=(sp.s.height||10)+8;
 let box=[-out,-out,W+out,H+out];
 if(zoom){const d0=edges[p.edge]||sp,n0=d0.r.count||1,m0=n0===1?L/2:d0.r.inset+Math.floor((n0-1)/2)*(L-2*d0.r.inset)/(n0-1),half=(d0.s.head||35)/2+Math.max(d0.s.neck||6,8)+10;const a=mapEdge(p.edge,m0-half,-14,W,H),b=mapEdge(p.edge,m0+half,(d0.s.height||10)+14,W,H);box=[Math.min(a[0],b[0]),Math.min(a[1],b[1]),Math.max(a[0],b[0]),Math.max(a[1],b[1])];if(t.mirror)box=[W-box[2],box[1],W-box[0],box[3]];}
 // Hình cả tấm chừa thêm dải bên phải cho kích thước chiều cao tấm.
 const pad=26,padR=zoom?0:44,s=Math.min((w-2*pad-padR)/(box[2]-box[0]),(h-2*pad)/(box[3]-box[1]));
 const ox=(w-padR-(box[2]-box[0])*s)/2,oy=(h-(box[3]-box[1])*s)/2,P=([x,y])=>[ox+(x-box[0])*s,h-oy-(y-box[1])*s];
 c.save();c.beginPath();c.rect(0,0,w,h);c.clip();
 poly(c,pts.map(P),'#f4efe7','#6b4226',1.4);
 // Đầu đang chọn: vạch hồng dọc mép + tên tấm nhận phía ngoài.
 const e0=P((([x,y])=>[fx(x),y])(mapEdge(p.edge,0,0,W,H))),e1=P((([x,y])=>[fx(x),y])(mapEdge(p.edge,L,0,W,H)));
 line(c,e0,e1,'#db2777',3);
 // Tên tấm nhận ngoài mỗi đầu (chỉ ở hình cả tấm); canh chữ ra phía ngoài để không đè mép.
 if(!zoom)state.model.pairs.filter(q=>q.ti===p.ti).forEach(q=>{const Lq=q.edge%2?W:H,m=mapEdge(q.edge,Lq/2,out,W,H),pt=P([fx(m[0]),m[1]]),cx=P([W/2,H/2]);const al=Math.abs(pt[0]-cx[0])<4?'center':pt[0]<cx[0]?'right':'left';text(c,q.receiver.split(' · ')[0],pt[0],Math.min(Math.max(pt[1],10),h-8),q.key===p.key?'#db2777':'#8a7f75',al,'middle');});
 c.restore();
 if(!zoom){dimension(c,[P([0,0])[0],h-10],[P([W,0])[0],h-10],fmt(W));dimension(c,[w-padR/2-4,P([0,0])[1]],[w-padR/2-4,P([0,H])[1]],fmt(H));return;}
 // Phóng to: ghi rộng đầu + cao mộng trên răng gần giữa của đầu đang chọn.
 const d=edges[p.edge];if(!d)return;
 const n=d.r.count,mid=n===1?L/2:d.r.inset+Math.floor((n-1)/2)*(L-2*d.r.inset)/(n-1);
 const q1=P((([x,y])=>[fx(x),y])(mapEdge(p.edge,mid-d.s.head/2,d.s.height+5,W,H))),q2=P((([x,y])=>[fx(x),y])(mapEdge(p.edge,mid+d.s.head/2,d.s.height+5,W,H)));
 dimension(c,q1,q2,fmt(d.s.head));
 const b1=P((([x,y])=>[fx(x),y])(mapEdge(p.edge,mid+d.s.head/2+6,0,W,H))),b2=P((([x,y])=>[fx(x),y])(mapEdge(p.edge,mid+d.s.head/2+6,d.s.height,W,H)));
 dimension(c,b1,b2,fmt(d.s.height));
}
// Mặt cắt qua bề dày tấm ngàm: vị trí dấu âm theo bên giữ.
function drawSection(p){
 const [c,w,h]=canvas('section'),{r,s}=pairSpec(p),T=p.thickness,side=r.side||'none',fit=side==='none'?T:r.fit,off=side==='B'?T-fit:0,markT=fit+s.slackT;
 const mX=46,barH=34,Lw=w-2*mX,k=Lw/T,x=mX,y=(h-barH)/2+6;
 poly(c,[[x,y],[x+Lw,y],[x+Lw,y+barH],[x,y+barH]],'#efe9e1','#6b4226',1.3);hatch(c,x,y,Lw,barH);
 text(c,'Mặt A',x-24,y+barH/2,'#24627c','center','middle');text(c,'Mặt B',x+Lw+24,y+barH/2,'#24627c','center','middle');
 if(!(Number.isFinite(markT)&&markT>0&&fit<=T))return;
 const left=x+(off-s.slackT/2)*k,nw=markT*k,nd=barH*0.55;
 c.fillStyle='#fff';c.fillRect(left,y-0.5,nw,nd);c.strokeStyle='#b45309';c.lineWidth=1.6;c.strokeRect(left,y,nw,nd);
 dimension(c,[left,y-13],[left+nw,y-13],fmt(markT));
 text(c,side==='none'?'Không phay':`Phay mặt ${side==='A'?'B':'A'} · bớt ${fmt(T-fit)} mm`,w/2,y+barH+16,'#8a7f75','center','middle');
}
function drawMortise(p){
 const [c,w,h]=canvas('mortise'),{r,s}=pairSpec(p),T=p.thickness,fit=(r.side||'none')==='none'?T:r.fit,markT=fit+s.slackT,Lu=s.head+s.slackL;
 if(!(markT>2*s.cutter)){text(c,'Kiểm tra độ dày / dao',w/2,h/2,'#b91c1c','center','middle');return;}
 const k=Math.min((w-30)/Lu,(h-20)/markT),a=mortisePoints(markT,Lu,s.cutter/2);
 poly(c,a.map(([t,u])=>[w/2+(u-Lu/2)*k,h/2+(t-markT/2)*k]),'#eef3ff','#2563eb',1.4);
 $('markSize').textContent=`${fmt(r.count)} dấu · mỗi dấu ${fmt(markT)} × ${fmt(Lu+s.cutter)} mm · sâu ${fmt(s.height)} mm`;
}
function drawPreview(){
 const p=state.model.pairs.find(q=>q.key===state.focus)||state.model.pairs.find(q=>q.state!=='da_lam')||state.model.pairs[0];
 $('preview').hidden=!p;if(!p)return;
 const t=state.model.tenons[p.ti]||{};
 $('previewTitle').textContent=`${shortText(p.tenon)}, đầu ${p.edgeName} → ${shortText(p.receiver)} · nhìn từ mặt A`;
 const {r,s}=pairSpec(p);
 if(p.state==='moi'&&check(r,p,s)){['faceAll','faceZoom','section','mortise'].forEach(id=>{const [c,w,h]=canvas(id);text(c,'Sửa lỗi của dòng này để xem hình',w/2,h/2,'#b91c1c','center','middle');});$('markSize').textContent='';return;}
 drawFace('faceAll',p,false);drawFace('faceZoom',p,true);drawSection(p);drawMortise(p);
 $('faceCap').textContent=`Tấm ${fmt(t.faceW)} × ${fmt(t.faceH)} × ${fmt(t.thickness)} mm · đầu đang chọn tô hồng · ${fmt(r.count)} mộng${r.count>1?` · lùi tâm ${fmt(r.inset)} mm`:' giữa đầu'}`;
}

window.showMessage=function(message,error=false){$('status').textContent=message;$('status').className=error?'error':'';};
window.receiveModel=function(m){state.model=m;state.mode=m.mode||state.mode;state.live=!!m.live;if(!m.pairs.some(p=>p.key===state.focus))state.focus=null;$('demo').textContent=state.live?'Đã nối SketchUp':'Xem giao diện mẫu';renderLists();buildRows();validate();};
window.applyFinished=function(ok,message){state.busy=false;validate();showMessage(message,!ok);if(ok)$('status').className='success';};

// Sửa một ô trong bảng = sửa thông số cặp đó.
$('rows').addEventListener('input',ev=>{const k=ev.target.dataset.k,tr=ev.target.closest('tr[data-key]');if(!k||!tr)return;const r=state.rows[tr.dataset.key];if(!r)return;r[k]=k==='on'?ev.target.checked:k==='side'?ev.target.value:num(ev.target.value);validate();});
// Dòng "Tất cả": gõ một số → chép xuống mọi cặp MỚI đang tick. Cặp đã làm / chỉ đóng dấu giữ thông số cũ.
$('allRow').addEventListener('input',ev=>{const k=ev.target.dataset.all;if(!k)return;const v=k==='side'?ev.target.value:num(ev.target.value);if(k==='side'?!v:!Number.isFinite(v))return;
 for(const p of state.model.pairs){const r=state.rows[p.key];if(p.state!=='moi'||!r||!r.on)continue;r[k]=v;const i=document.querySelector(`#rows tr[data-key="${p.key}"] [data-k=${k}]`);if(i)i.value=v;}
 validate();});
$('rows').addEventListener('click',ev=>{const g=ev.target.closest('[data-go]');if(g){ev.stopPropagation();state.live?bridge('go',g.dataset.go):showMessage('Bản xem giao diện.');return;}
 const tr=ev.target.closest('tr[data-key]');if(!tr||ev.target.closest('input,select'))return;state.focus=tr.dataset.key;markFocus();drawPreview();bridge('focus',state.focus);});
shapeKeys.forEach(k=>$(k).addEventListener('input',()=>{saveShape();demChinh();validate();}));
document.querySelectorAll('#kieuBox [data-preset]').forEach(b=>b.addEventListener('click',()=>apKieu(+b.dataset.preset)));
document.querySelectorAll('#matBox [data-mat]').forEach(b=>b.addEventListener('click',()=>datMat(b.dataset.mat)));
$('shapeBox').addEventListener('toggle',()=>$('bang').classList.toggle('nc',$('shapeBox').open));
$('fitAll').addEventListener('input',datFit);
$('countAll').addEventListener('input',datSoMong);
$('goTam').onclick=()=>state.live?bridge('go_tam',''):showMessage('Bản xem giao diện.');
// Bấm vào khung nào = đang chọn tấm cho nhóm đó (thay nút "Bấm tấm trên model").
document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=ev=>{if(ev.target.closest('button'))return;state.mode=b.dataset.mode;bridge('mode',state.mode);renderLists();});
document.querySelectorAll('[data-take]').forEach(b=>b.onclick=()=>state.live?bridge('take',b.dataset.take):showMessage('Bản xem giao diện: chọn tấm trong SketchUp.',true));
document.querySelectorAll('[data-clear]').forEach(b=>b.onclick=()=>{if(state.live)bridge('clear',b.dataset.clear);else showMessage('Bản xem giao diện: không xóa được.',true);});
$('unscale').onclick=()=>state.live?bridge('unscale',''):showMessage('Bản xem giao diện.');
$('refresh').onclick=()=>state.live?bridge('refresh',''):showMessage('Bản xem giao diện.');
$('cancel').onclick=()=>state.live?bridge('cancel',''):showMessage('Đây là bản xem giao diện. Đóng tab để thoát.');
$('apply').onclick=()=>{validate();if($('apply').disabled)return;
 const rows=state.model.pairs.filter(p=>p.state!=='da_lam'&&state.rows[p.key].on).map(p=>{const r=state.rows[p.key];return p.state==='moi'?{key:p.key,count:r.count,inset:r.inset,side:r.side,fit:r.fit}:{key:p.key};});
 const payload=JSON.stringify({shape:shape(),rows});
 if(!state.live){window.lastPayload=payload;showMessage('Bản xem giao diện: chưa thay đổi model.');return;}
 state.busy=true;$('apply').disabled=true;showMessage('Đang tạo mộng và dấu âm…');bridge('apply',payload);};
window.addEventListener('resize',drawPreview);
loadShape();demChinh();
try{const f=Number(localStorage.getItem('mxc.fit'));if(f>0)$('fitAll').value=f;}catch(e){}
$('fitBox').hidden=state.kieu==='none';
toKieu();
if(window.sketchup){bridge('ready','');}else{receiveModel({...DEMO,live:false});}
