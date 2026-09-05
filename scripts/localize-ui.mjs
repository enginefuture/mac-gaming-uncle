import fs from 'node:fs';
import path from 'node:path';
// One-time migration helper: lex Swift strings, including nested interpolation,
// rather than treating interpolated Swift source as a regular expression.
const root = process.cwd();
const files = fs.readdirSync('Sources/MacGamingUncleApp').filter(x=>x.endsWith('.swift') && x !== 'LanguagePicker.swift').map(x=>'Sources/MacGamingUncleApp/'+x);
files.push('Sources/IndieRuntime/SystemProbe.swift', 'Sources/IndieCore/IndieError.swift', 'Sources/IndieRuntime/GPTKDownloadService.swift', 'Sources/IndieCatalog/SteamAccountLibrary.swift', 'Sources/IndieCatalog/SteamNativeStore.swift');
for(const directory of ['Sources/IndieRuntime','Sources/IndieCatalog']) {
  for(const file of fs.readdirSync(directory).filter(x=>x.endsWith('.swift') && x !== 'BottleFonts.swift')) {
    const full=directory+'/'+file; if(!files.includes(full)) files.push(full);
  }
}
const keys = new Set();
const translations = new Map(fs.readFileSync('scripts/ui-translations.tsv','utf8').trimEnd().split('\n').map(line=>line.split('\t')));
function transform(s) {
  let i=0;
  function code(end=false) {
    let out='', depth=0;
    while(i<s.length) {
      if(s.startsWith('//',i)) {let j=s.indexOf('\n',i); if(j<0) j=s.length; out+=s.slice(i,j); i=j; continue;}
      if(s.startsWith('/*',i)) {let j=s.indexOf('*/',i+2); j=j<0?s.length:j+2; out+=s.slice(i,j); i=j; continue;}
      if(s[i]==='"' && s[i-1]!=='#') {out+=str();continue;}
      if(end && s[i]===')' && depth===0) {i++;return out;}
      if(s[i]==='(') depth++;
      if(s[i]===')') depth--;
      out+=s[i++];
    }
    return out;
  }
  function str() {
    const start=i++; let key='', output='"';
    while(i<s.length) {
      if(s.startsWith('\\(',i)) {i+=2; const inner=code(true); key+='%@'; output+='\\('+inner+')';continue;}
      if(s[i]==='\\') {const e=s.slice(i,i+2); key+=e;output+=e;i+=2;continue;}
      if(s[i]==='"') {i++;output+='"';break;}
      key+=s[i]; output+=s[i++];
    }
    if(/[\p{Script=Han}]/u.test(key)) {keys.add(key); return /\bL\(\s*$/.test(s.slice(0,start)) ? output : 'L('+output+')';}
    return output;
  }
  return code();
}
for(const file of files) {
  let source=fs.readFileSync(file,'utf8');
  const result=transform(source);
  if(process.argv.includes('--write')) {
    let output=result;
    if(!file.includes('/IndieCore/') && !source.includes('import IndieCore')) output='import IndieCore\n'+output;
    fs.writeFileSync(file,output);
  }
}
const missing=[...keys].filter(key=>!translations.has(key));
if(missing.length) {console.error('Missing translations:',missing); process.exit(1);}
for(const [key,value] of translations) {
  if(!value || (key.match(/%@/g)||[]).length !== (value.match(/%@/g)||[]).length) {
    throw new Error('Invalid translation or placeholder count: '+key);
  }
}
if(process.argv.includes('--catalog')) {
  const quote = value => JSON.stringify(value.replaceAll('\\n','\n'));
  for(const language of ['en','zh-Hans']) {
    const dir='Sources/IndieCore/Resources/'+language+'.lproj';
    fs.mkdirSync(dir,{recursive:true});
    const entries=[...translations].map(([key,value])=>quote(key)+' = '+quote(language==='en'?value:key)+';');
    fs.writeFileSync(path.join(dir,'Localizable.strings'),entries.join('\n')+'\n');
  }
}
console.log(keys.size+' source messages; '+translations.size+' translations');
