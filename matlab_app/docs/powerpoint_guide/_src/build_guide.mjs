import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {FileBlob,PresentationFile}=await import(pathToFileURL(require.resolve('@oai/artifact-tool')).href);
const sharp=require('sharp');
const here=path.dirname(fileURLToPath(import.meta.url));
const guide=path.dirname(here), root=path.resolve(guide,'../../..');
const build=path.join(root,'.cache/powerpoint-guide');
const reference=process.env.GUIDE_TEMPLATE;
if(!reference) throw new Error('GUIDE_TEMPLATE must point to 技術レポートPowerPoint/reference.pptx');
const name='アライメント計測ツール_ユーザー手順書.pptx';
// 下書きは .cache に作るだけなので、手順書をPowerPointで開いていても続ける（置き換えは finalize_guide.mjs が止める）。
try {await fs.access(path.join(guide,'~$'+name));console.warn('手順書がPowerPointで開かれています。下書きだけ作ります。');}catch(e){if(e.code!=='ENOENT')throw e;}
await fs.mkdir(build,{recursive:true});
const p=await PresentationFile.importPptx(await FileBlob.load(reference));
const records=JSON.parse('['+(await p.inspect({kind:'textbox,shape,image,chart,table',maxChars:2000000})).ndjson.trim().split('\n').join(',')+']');
// テンプレートの表紙、本文、まとめを複製元として残す。
const cover=p.slides.items[0], base=p.slides.items[2], ending=p.slides.items[24];
const originalText=new Map();
for(const rec of records){
 if(![0,2,24].includes(rec.slideIndex))continue;
 const keep=rec.kind==='textbox' && (rec.slideIndex===2 ? rec.position.top<140 || rec.position.top>675 : rec.slideIndex===0 ? rec.position.left<740 : rec.position.top<135 || rec.position.top>675);
 if(keep) originalText.set(rec.id,{shape:p.resolve(rec.id),text:rec.text,slide:rec.slideIndex});
 else p.delete(rec.id);
}
p.slides.keep([0,2,24]);
const FONT='BIZ UDGothic', navy='#22223B', teal='#2A9D8F', coral='#E76F51';
function text(s,value,x,y,w,h,size=22,color=navy,bold=false){
 const sh=s.shapes.add({geometry:'textbox',position:{left:x,top:y,width:w,height:h},fill:'none',line:{fill:'none',width:0}});
 sh.text=value;sh.text.style={typeface:FONT,fontSize:size,color,bold,verticalAlignment:'top',wrap:true,insets:0}; return sh;
}
function badge(s,n,x,y){
 const sh=s.shapes.add({geometry:'ellipse',position:{left:x-14,top:y-14,width:28,height:28},fill:coral,line:{fill:'#FFFFFF',width:1.4}});
 sh.text=String(n);sh.text.style={typeface:FONT,fontSize:18,bold:true,color:'#FFFFFF',alignment:'center',verticalAlignment:'middle',insets:0};
}
function step(s,n,title,body,x,y,w){text(s,String(n).padStart(2,'0'),x,y,38,30,25,teal,true);text(s,title,x+45,y,w-45,35,21,navy,true);text(s,body,x+45,y+41,w-45,110,18);}
function updateChrome(s,title,section,page){
 for(const sh of s.shapes.items){const y=sh.position.top,t=String(sh.text);if(y<45)sh.text=section;else if(y<140){sh.text=title;sh.text.style={typeface:FONT,fontSize:37.33,bold:true,color:navy,insets:0};}else if(y>675){sh.text=t==='Sobol感度解析 入門'?'アライメント計測ツール　操作手順':String(page);}}
 s.speakerNotes.text='対象：2026-10-22のローカル版。掲載画面は同梱の模擬データを使用。\n根拠：matlab_app/README.md、AlignmentEstimationApp.m、+alignest各計算処理。';
}
async function picture(s,file,box,crop){
 let pipeline=sharp(path.join(guide,'images',file));if(crop)pipeline=pipeline.extract({left:crop[0],top:crop[1],width:crop[2],height:crop[3]});
 const bytes=await pipeline.png().toBuffer(); const m=await sharp(bytes).metadata();
 const scale=Math.min(box[2]/m.width,box[3]/m.height), w=m.width*scale,h=m.height*scale;
 const x=box[0]+(box[2]-w)/2,y=box[1]+(box[3]-h)/2;
 s.images.add({blob:bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),contentType:'image/png',alt:file+' 実アプリの模擬データ画面',position:{left:x,top:y,width:w,height:h},fit:'contain'});
 return {x,y,scale,ox:crop?.[0]??0,oy:crop?.[1]??0};
}
function table(s,rows,x,y,w,h,widths){
 const t=s.tables.add({rows:rows.length,columns:rows[0].length,left:x,top:y,width:w,height:h,values:rows,columnWidths:widths});
 t.borders.assign({fill:'#DADDE6',width:.5,style:'solid'});
 for(let r=0;r<rows.length;r++)for(let c=0;c<rows[0].length;c++){let ce=t.getCell(r,c);ce.fill=r===0?navy:r%2?'#F3F4F8':'#FFFFFF';ce.text.style={typeface:FONT,fontSize:r===0?20:19,color:r===0?'#FFFFFF':navy,bold:r===0,insets:9,verticalAlignment:'middle'};}
 return t;
}
const slides=JSON.parse(await fs.readFile(path.join(here,'content.json'),'utf8'));
// 表紙は参照の文字枠・配色を維持し、右側の図をアプリ画面に置き換える。
for(const entry of originalText.values())if(entry.slide===0){const sh=entry.shape,t=entry.text;
 if(t.startsWith('学習用'))sh.text='ユーザー向け操作手順書';
 else if(t==='Sobol感度解析 入門'){sh.text='アライメント計測ツール';sh.position={left:76.8,top:185,width:640,height:130};sh.text.style={typeface:FONT,fontSize:48,color:'#FFFFFF',bold:true,insets:0};}
 else if(t.startsWith('概念')){sh.text='データの取り込みから\n手法比較・結果出力まで';sh.position={left:76.8,top:345,width:600,height:110};}
 else if(t.startsWith('2026')){sh.text='2026年10月22日 ローカル版\n画面は同梱の模擬データを使用';sh.position={left:76.8,top:590,width:640,height:65};}
}
await picture(cover,'15_map.png',[730,180,480,340]);
cover.speakerNotes.text='MATLAB版ユーザー手順書。画面はローカルの実アプリを同梱の模擬データで撮影。Windowsではウィンドウ枠やフォントが異なる場合があります。';
const ordered=[cover];
for(let i=0;i<slides.length;i++){
 const cfg=slides[i],s=base.duplicate();updateChrome(s,cfg.title,cfg.section,i+2);ordered.push(s);
 if(cfg.kind==='screen'){
  if(cfg.panels){
  for(let j=0;j<cfg.panels.length;j++){const q=cfg.panels[j],b=await picture(s,cfg.image,[58,200+j*190,805,130],q.crop);badge(s,j+1,42,b.y+(q.marker[1]-b.oy)*b.scale);}
  }else{
  const b=await picture(s,cfg.image,cfg.crop?[58,150,805,500]:[58,145,820,513],cfg.crop);
  for(const [j,pt] of (cfg.markers??[]).entries())badge(s,j+1,b.x+(pt[0]-b.ox)*b.scale,b.y+(pt[1]-b.oy)*b.scale);
  }
  cfg.steps.forEach((st,j)=>step(s,j+1,st[0],st[1],915,160+j*160,310));
  if(cfg.note)text(s,cfg.note,58,660,1150,22,15,'#55566C');
 }else if(cfg.kind==='table'){
  table(s,cfg.rows,58,165,1164,cfg.height??400,cfg.widths);
  if(cfg.note)text(s,cfg.note,58,590,1164,65,21);
 }else if(cfg.kind==='steps'){
  for(let j=0;j<cfg.steps.length;j++){const st=cfg.steps[j];step(s,j+1,st[0],st[1],58+(j%2)*600,170+Math.floor(j/2)*155,550);}
  if(cfg.image)await picture(s,cfg.image,[58,625,1164,35],[0,0,1600,45]);
 }else if(cfg.kind==='start'){
  step(s,1,'MATLABを起動','アプリ一式の matlab_app フォルダを\n「現在のフォルダー」にします。',58,175,640);
  step(s,2,'起動コマンドを入力','コマンドウィンドウで次を実行します。',58,330,640);
  text(s,'runAlignmentEstimationApp',103,435,630,48,26,teal,true);
  text(s,'試すファイル\nsample_data/sample_alignment.xlsx',58,545,680,70,24);
  text(s,'必要な環境',820,175,380,40,26,navy,true);
  text(s,'MATLAB R2022bで動作確認\n追加Toolbox・Excel本体は不要\n\nWindowsの.exe版を使う場合は、\n作成時と同じ版のMATLAB Runtime\nが必要です。',820,235,385,275,22);
  text(s,'画面の例はMac版です。操作名は同じで、外観はOSにより変わる場合があります。',58,640,1164,35,18,'#55566C');
 }
 if(cfg.notes)s.speakerNotes.text+='\n'+cfg.notes;
}
// 濃紺のまとめページを再利用する。
for(const sh of ending.shapes.items){if(sh.position.top<135)sh.text='操作を終える前の確認';else if(sh.position.top>675)sh.text=String(sh.text)==='Sobol感度解析 入門'?'アライメント計測ツール　操作手順':String(slides.length+2);}
const checks=[['入力条件','列・単位・行の除外条件を確認し、変更後は再取り込み。'],['評価条件','学習Shotの選び方・数、手法、質的変数、補正モデルを確認。'],['結果の確認','実行記録、誤差の表・散布図、Waferごと・平均の残差を確認。'],['保存','設定JSON、評価結果Excel、必要な推定値・図を保存。']];
checks.forEach((c,i)=>{text(ending,String(i+1),65,175+i*109,42,45,32,[coral,teal,'#8D6A9F','#E9C46A'][i],true);text(ending,c[0],120,175+i*109,200,40,27,'#FFFFFF',true);text(ending,c[1],340,177+i*109,850,70,23,'#D9DBEA');});
ending.speakerNotes.text='画面例と操作名の根拠：matlab_app/AlignmentEstimationApp.m、README.md。設定JSONと結果Excelは別ファイルとして保存します。';
ordered.push(ending);
p.slides.keep(ordered.map(x=>'sl/'+x.id));p.slides.reorder(ordered.map(x=>'sl/'+x.id));
await fs.writeFile(path.join(build,'content-inspection.ndjson'),(await p.inspect({kind:'slide,textbox,table,notes',maxChars:1000000})).ndjson);
await(await PresentationFile.exportPptx(p)).save(path.join(build,'guide.building.pptx'));
for(let i=0;i<p.slides.items.length;i++){
 const png=await p.export({slide:p.slides.items[i],format:'png',scale:1});
 await fs.writeFile(path.join(build,`slide-${String(i+1).padStart(2,'0')}.png`),new Uint8Array(await png.arrayBuffer()));
}
await fs.writeFile(path.join(build,'montage.webp'),new Uint8Array(await(await p.export({format:'webp',montage:true,scale:.5})).arrayBuffer()));
console.log('BUILT',p.slides.items.length);
