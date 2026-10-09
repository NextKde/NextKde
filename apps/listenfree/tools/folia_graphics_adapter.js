// Graphics command recorder: original procedural functions -> Qt Quick Shapes.
// Kept separate from the generated bundle so re-imports are reproducible.
function vec(owner,xKey,yKey){return {set:function(x,y){owner[xKey]=x;owner[yKey]=y===undefined?x:y}}}
function Graphics(){this.paths=[];this.pending='';this.x=0;this.y=0;this.px=0;this.py=0;this.sx=1;this.sy=1;this.rotation=0;this.alpha=1;this.visible=true;this.parent=null;this.position=vec(this,'x','y');this.pivot=vec(this,'px','py');this.scale=vec(this,'sx','sy');}
Graphics.prototype.moveTo=function(x,y){this.pending+='M'+x+' '+y;return this;};
Graphics.prototype.lineTo=function(x,y){this.pending+='L'+x+' '+y;return this;};
Graphics.prototype.poly=function(p){if(p.length){this.moveTo(p[0],p[1]);for(var i=2;i<p.length;i+=2)this.lineTo(p[i],p[i+1]);this.pending+='Z';}return this;};
Graphics.prototype.rect=function(x,y,w,h){return this.poly([x,y,x+w,y,x+w,y+h,x,y+h]);};
Graphics.prototype.circle=function(x,y,r){this.pending+='M'+(x-r)+' '+y+'a'+r+' '+r+' 0 1 0 '+(2*r)+' 0a'+r+' '+r+' 0 1 0 '+(-2*r)+' 0Z';return this;};
Graphics.prototype.fill=function(spec){this.paths.push({path:this.pending,fill:spec.color,alpha:spec.alpha===undefined?1:spec.alpha,stroke:'transparent',strokeWidth:0});this.pending='';return this;};
Graphics.prototype.stroke=function(spec){this.paths.push({path:this.pending,fill:'transparent',alpha:spec.alpha===undefined?1:spec.alpha,stroke:spec.color,strokeWidth:spec.width||1});this.pending='';return this;};
Graphics.prototype.cut=function(){if(this.paths.length)this.paths[this.paths.length-1].path+=this.pending;this.pending='';return this;};
function Container(){Graphics.call(this);this.children=[];}
Container.prototype.addChild=function(child){child.parent=this;this.children.push(child);return child;};
function colorString(value){if(typeof value==='number')return '#'+value.toString(16).padStart(6,'0');var match=String(value).match(/^rgba?\(([^)]+)\)$/);if(match){var parts=match[1].split(',').map(Number);return '#'+Math.round((parts.length>3?parts[3]:1)*255).toString(16).padStart(2,'0')+parts.slice(0,3).map(function(n){return Math.round(n).toString(16).padStart(2,'0');}).join('');}return value||'#ffffff';}
var nativeGraphics={Graphics:Graphics,Container:Container,Color:{shared:{value:'#fff',setValue:function(c){this.value=c;return this;},toNumber:function(){return this.value;}}}};
function kinds(){return Object.keys(require('tempera/temperaShotProfiles').TEMPERA_SHOT_PROFILES);}
function hash(text){var h=2166136261;for(var i=0;i<text.length;i++){h^=text.charCodeAt(i);h=Math.imul(h,16777619);}return h>>>0;}
function build(seedText,line,width,height){
    var seed=hash(seedText+':'+line),keys=kinds(),kind=keys[seed%keys.length];
    var palette={paper:'#202a32',ink:'#ebdac4',tone1:'#2f4651',tone2:'#5b6971',tone3:'#877565',tone4:'#d4bc9d',accent:'#c39578'};
    var profile=require('tempera/temperaShotProfiles').TEMPERA_SHOT_PROFILES[kind];
    var view=require('tempera/temperaBlocks').buildTemperaBlocks(nativeGraphics,{kind:kind,seed:seed,palette:palette,width:width,height:height,flowAngle:Math.PI/2+.12,showDecor:true,decor:{motif:'diamonds',hatchAngle:.6,scribbleSeed:seed}});
    var records=[];function walk(item){if(item.paths)for(var i=0;i<item.paths.length;i++){var p=item.paths[i];records.push({owner:item,path:p.path,fill:colorString(p.fill),stroke:colorString(p.stroke),strokeWidth:p.strokeWidth,alpha:p.alpha});}if(item.children)item.children.forEach(walk);}
    walk(view.container);
    return {kind:kind,profile:profile,records:records,update:view.updateTime};
}
function frame(record){var n=record.owner,angle=n.rotation,scaleX=n.sx,scaleY=n.sy,c=Math.cos(angle),s=Math.sin(angle),x=n.x-n.px*scaleX*c+n.py*scaleY*s,y=n.y-n.px*scaleX*s-n.py*scaleY*c,alpha=n.alpha*record.alpha;var p=n.parent;while(p){c=Math.cos(p.rotation);s=Math.sin(p.rotation);var nx=(x-p.px)*p.sx,ny=(y-p.py)*p.sy;x=nx*c-ny*s+p.x;y=nx*s+ny*c+p.y;angle+=p.rotation;scaleX*=p.sx;scaleY*=p.sy;alpha*=p.alpha;p=p.parent;}return {x:x,y:y,rotation:angle*180/Math.PI,sx:scaleX,sy:scaleY,alpha:alpha};}
function sonnetLayout(units,kind,seedText,width,height){
    if(!units.length)return [];
    var boxes=units.map(function(unit,i){var box=Object.assign({},unit);box.index=i;box.isHero=i===Math.floor(units.length/2);box.isSemiHero=units.length>3&&i===0;box.fontScale=box.isHero?1.65:box.isSemiHero?1.12:.85;box.measuredWidth*=box.fontScale;box.measuredHeight*=box.fontScale;box.vertical=false;box.layoutDirection='horizontal';box.rotation=0;box.x=0;box.y=0;box.enterX=0;box.enterY=0;return box;});
    var lib=require('sonnet/sonnetShotFlowLayouts'),gaps=lib.resolveSonnetFlowGaps(units[0].fontSize),variant=hash(seedText+units[0].displayText)%4;
    var ctx={boxes:boxes,heroIndex:Math.floor(boxes.length/2),width:width*.88,height:height*.7,flowGap:gaps.flowGap,stackGap:gaps.stackGap};
    if(kind==='editorial-column')lib.layoutEditorialColumn(ctx,boxes.length===1?0:hash(seedText+units[0].displayText)%5,0);
    else if(kind==='tracking-ribbon')lib.layoutTrackingRibbon(ctx,variant%3);
    else if(kind==='fragment-collage')lib.layoutFragmentCollage(ctx,variant%3);
    else if(kind==='type-impact'||kind==='mask-reveal')lib.layoutCrossStack(ctx);
    else if(kind==='poster-blocks')boxes=require('sonnet/sonnetPosterBlocksLayout').layoutSonnetPosterBlocks(boxes,ctx.width,ctx.height,units[0].fontSize,variant).placements;
    else lib.layoutQuietTableau(ctx,variant);
    return boxes;
}
