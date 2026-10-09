// Build-time only. Bundles Folia's pure procedural composition functions for
// Qt's existing QML JS engine; no Pixi/React/Three runtime is bundled.
const fs=require('fs'),path=require('path');
// Optional third argument points at a build-time TypeScript installation.
const compiler=process.argv[3]||'typescript';
const ts=require(path.isAbsolute(compiler)?compiler:require.resolve(compiler,{paths:[process.cwd()]}));
const root=path.resolve(process.argv[2]);
const modules=new Map();
function visit(file){
    file=path.resolve(file);const id=path.relative(root,file).replaceAll('\\','/').replace(/\.ts$/,'');
    if(modules.has(id))return id;
    const source=fs.readFileSync(file,'utf8');
    let code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2015,module:ts.ModuleKind.CommonJS,removeComments:true}}).outputText;
    modules.set(id,'');
    code=code.replace(/require\("([^"]+)"\)/g,(_,dep)=>{
        if(!dep.startsWith('.'))throw Error('Unexpected runtime dependency: '+dep);
        return 'require('+JSON.stringify(visit(path.resolve(path.dirname(file),dep+'.ts')))+')';
    });
    modules.set(id,code);return id;
}
visit(path.join(root,'tempera/temperaCompositions.ts'));
visit(path.join(root,'tempera/temperaShotProfiles.ts'));
visit(path.join(root,'tempera/temperaBlocks.ts'));
visit(path.join(root,'sonnet/sonnetShotFlowLayouts.ts'));
visit(path.join(root,'sonnet/sonnetPosterBlocksLayout.ts'));
const output='// Generated from Folia 71c5705, AGPL-3.0. See licenses/Folia-AGPL-3.0.txt.\n'+
    'var factories={\n'+[...modules].map(([id,code])=>JSON.stringify(id)+':function(require,module,exports){\n'+code+'\n}').join(',\n')+'\n};\nvar cache={};\nfunction require(id){if(cache[id])return cache[id].exports;var m={exports:{}};cache[id]=m;factories[id](require,m,m.exports);return m.exports;}\n'+
    fs.readFileSync(path.join(__dirname,'folia_graphics_adapter.js'),'utf8');
fs.writeFileSync('music_player_desktop/components/FoliaComposition.js',output);
console.log('Bundled '+modules.size+' pure modules, '+Math.round(output.length/1024)+' KiB');
