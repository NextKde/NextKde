// Exercises upstream geometry through the Qt adapter, without Pixi or a browser.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const program={};vm.createContext(program);
vm.runInContext(fs.readFileSync('music_player_desktop/components/FoliaComposition.js','utf8'),program);
const visited=new Set();let maxPaths=0,frames=0;
for(let seed=0;seed<3000&&visited.size<program.kinds().length;seed++){
    const view=program.build('interop-'+seed,seed,1440,900);
    visited.add(view.kind);assert(view.records.length>0,view.kind);
    maxPaths=Math.max(maxPaths,view.records.length);
    for(const t of [0,.12,.45,.8,1]){
        view.update(40+t*5,40,45);
        for(const record of view.records){
            assert(!/NaN|Infinity|undefined/.test(record.path),view.kind);
            const frame=program.frame(record);
            for(const value of Object.values(frame))assert(Number.isFinite(value),view.kind);
            frames++;
        }
    }
}
assert.equal(visited.size,program.kinds().length,'Exercise every upstream composition');
const shots=['editorial-column','type-impact','fragment-collage','tracking-ribbon','mask-reveal','poster-blocks','quiet-tableau'];
let layouts=0;
for(const kind of shots)for(let count=1;count<=24;count++)for(const [width,height] of [[1440,900],[900,640]]){
    const units=Array.from({length:count},(_,index)=>({group:index,displayText:index%2?'Keep moving':'字形排版',originX:index*150,originY:0,measuredWidth:index%2?145:160,measuredHeight:54,fontSize:45}));
    const boxes=program.sonnetLayout(units,kind,'layout-'+count,width,height);
    assert.equal(boxes.length,count,kind);
    for(const box of boxes)for(const field of ['x','y','fontScale'])assert(Number.isFinite(box[field]),kind+' '+field);
    layouts++;
}
console.log(JSON.stringify({passed:true,temperaCompositions:visited.size,maxPathNodes:maxPaths,temperaFrames:frames,sonnetLayouts:layouts},null,2));
