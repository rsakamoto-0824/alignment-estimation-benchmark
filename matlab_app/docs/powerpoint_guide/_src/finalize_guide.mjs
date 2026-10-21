import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath, pathToFileURL} from 'node:url';
const guide=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const root=path.resolve(guide,'../../..');
const skill=process.env.PRESENTATIONS_SKILL;
const reference=process.env.GUIDE_TEMPLATE;
if(!skill || !reference || !process.env.RUNTIME_PYTHON) throw new Error('PRESENTATIONS_SKILL, GUIDE_TEMPLATE, RUNTIME_PYTHON are required');
const finalPath=path.join(guide,'アライメント計測ツール_ユーザー手順書.pptx');
// 表のページ番号（表紙が1ページ目、content.json の先頭が2ページ目）
const slides=JSON.parse(await fs.readFile(path.join(guide,'_src/content.json'),'utf8'));
const tableSlides=slides.flatMap((slide,i)=>slide.kind==='table'?[i+2]:[]);
try{await fs.access(path.join(guide,'~$'+path.basename(finalPath)));throw new Error('PowerPointで手順書を閉じてください');}catch(e){if(e.code!=='ENOENT')throw e;}
const {finalizePresentation}=await import(pathToFileURL(path.join(skill,'container_tools/artifact_tool_utils.mjs')).href);
// finalizePresentation は既存のファイルを上書きしないので、今の手順書を .cache/powerpoint-guide/backup/ に移してから置く。
// 検証で止まったときは元に戻す。
const backupDir=path.join(root,'.cache/powerpoint-guide/backup');
const now=new Date(), pad=(v)=>String(v).padStart(2,'0');  // 控えの名前は端末の時刻（例：20261022_083104）
const stamp=`${now.getFullYear()}${pad(now.getMonth()+1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
let backupPath;
try{
 await fs.access(finalPath);
 await fs.mkdir(backupDir,{recursive:true});
 backupPath=path.join(backupDir,path.basename(finalPath,'.pptx')+'_'+stamp+'.pptx');
 await fs.rename(finalPath,backupPath);
}catch(e){if(e.code!=='ENOENT')throw e;}
let result;
try{
result=await finalizePresentation({
 workspaceDir:root,
 candidatePath:path.join(root,'.cache/powerpoint-guide/guide.building.pptx'),
 finalPath,
 pythonExecutable:process.env.RUNTIME_PYTHON,
 integrityValidatorPath:path.join(skill,'container_tools/inspect_presentation_package_integrity.py'),
 layoutValidatorPath:path.join(skill,'container_tools/inspect_presentation_layout_geometry.py'),
 layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-bullet-geometry','--validate-heading-fit',...tableSlides.flatMap(n=>['--require-native-table-slide',String(n)])],
 requiredNativeTableOwnerSlides:tableSlides,
 fontPolicy:{basis:'reference',families:['BIZ UDGothic'],referencePath:reference,referenceSha256:createHash('sha256').update(await fs.readFile(reference)).digest('hex')},
 verifyArtifactToolImport:true,
 receiptPath:path.join(root,`.cache/powerpoint-guide/final-validation_${stamp}.json`)  // 記録は配置ごとに別のファイル（同名は上書きできない）
});
}catch(e){
 if(backupPath){await fs.rm(finalPath,{force:true});await fs.rename(backupPath,finalPath);}
 throw e;
}
console.log(JSON.stringify(result,null,2));
if(backupPath)console.log('BACKUP',backupPath);
