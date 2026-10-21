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
try{await fs.access(path.join(guide,'~$'+path.basename(finalPath)));throw new Error('PowerPointで手順書を閉じてください');}catch(e){if(e.code!=='ENOENT')throw e;}
const {finalizePresentation}=await import(pathToFileURL(path.join(skill,'container_tools/artifact_tool_utils.mjs')).href);
const result=await finalizePresentation({
 workspaceDir:root,
 candidatePath:path.join(root,'.cache/powerpoint-guide/guide.building.pptx'),
 finalPath,
 pythonExecutable:process.env.RUNTIME_PYTHON,
 integrityValidatorPath:path.join(skill,'container_tools/inspect_presentation_package_integrity.py'),
 layoutValidatorPath:path.join(skill,'container_tools/inspect_presentation_layout_geometry.py'),
 layoutArgs:['--expected-slide-size-emu','12192000,6858000','--validate-bullet-geometry','--validate-heading-fit',...[4,23,25].flatMap(n=>['--require-native-table-slide',String(n)])],
 requiredNativeTableOwnerSlides:[4,23,25],
 fontPolicy:{basis:'reference',families:['BIZ UDGothic'],referencePath:reference,referenceSha256:createHash('sha256').update(await fs.readFile(reference)).digest('hex')},
 verifyArtifactToolImport:true,
 receiptPath:path.join(root,'.cache/powerpoint-guide/final-validation.json')
});
console.log(JSON.stringify(result,null,2));
