(() => {
 const token=new URLSearchParams(location.search).get('live');
 if(!token || !/^[a-f0-9]{32}$/.test(token)) return;
 const viewer=document.querySelector('model-viewer'), root=new URL('/live/'+token+'/',location.href);
 const status=document.createElement('div'); status.id='gc-live-status';
 Object.assign(status.style,{position:'fixed',bottom:'12px',left:'12px',zIndex:10,padding:'9px 13px',background:'#20252de8',color:'#fff',font:'13px sans-serif',maxWidth:'85vw',pointerEvents:'none'});
 status.textContent='Google Live Preview: loading…';document.body.append(status);
 let revision=0, appliedTimestamp=null, busy=false, state={}, templates=null, retryAt=0, applyCount=0, closed=false;
 const instances=new Map(), imageCache=new Map(), textureCache=new Map();
 const privateValue=(object,description)=>{
  for(let prototype=object;prototype;prototype=Object.getPrototypeOf(prototype)) {
   const symbol=Object.getOwnPropertySymbols(prototype).find(symbol=>symbol.description===description);
   if(symbol) return object[symbol];
  }
 };
 const show=(message,error=false)=>{status.textContent=message;status.style.color=error?'#ffb4a9':'#fff';};
 const bindKey=mesh=>{for(let node=mesh;node;node=node.parent) if(/^GC_Live_ID_\d+$/.test(node.name)) return node.name;return null;};
 const descriptorKey=descriptor=>JSON.stringify(descriptor);
 const transformKey=descriptor=>descriptor?JSON.stringify([descriptor.uv,descriptor.tiling,descriptor.offset,descriptor.rotation,descriptor.wrap]):'none';
 function localURL(relative) {
  const url=new URL(relative,root);
  if(url.origin!==location.origin || !url.pathname.startsWith(root.pathname)) throw new Error('Invalid local texture URL.');
  return url.href;
 }
 async function imageData(descriptor) {
  const url=localURL(descriptor.url);
  if(!imageCache.has(url)) imageCache.set(url,(async()=>{
   const wrapped=await viewer.createTexture(url);
   const raw=[...(privateValue(wrapped,'correlatedObjects')||[])].find(texture=>texture.isTexture);
   if(!raw) throw new Error('The installed Google texture API is incompatible. Restore the bundled viewer.');
   const source=raw.image, canvas=document.createElement('canvas');canvas.width=source.width;canvas.height=source.height;
   const context=canvas.getContext('2d',{willReadFrequently:true});context.drawImage(source,0,0);
   return {raw,canvas,pixels:context.getImageData(0,0,canvas.width,canvas.height)};
  })());
  try{return await imageCache.get(url);}catch(error){imageCache.delete(url);throw error;}
 }
 function configure(texture,descriptor,data) {
  texture.colorSpace=data?'':'srgb';texture.flipY=false;
  texture.channel=descriptor.uv;
  const angle=descriptor.rotation*Math.PI/180, [u,v]=descriptor.tiling,[x,y]=descriptor.offset;
  texture.offset.set(x+.5-.5*(u*Math.cos(angle)+v*Math.sin(angle)),-y+.5-.5*(v*Math.cos(angle)-u*Math.sin(angle)));
  texture.repeat.set(u,v);texture.center.set(0,0);texture.rotation=angle;
  texture.wrapS=descriptor.wrap[0];texture.wrapT=descriptor.wrap[1];texture.updateMatrix();texture.needsUpdate=true;
  return texture;
 }
 async function textureFor(descriptor,role,used) {
  if(!descriptor) return null;
  const key=role+':'+descriptorKey(descriptor);used.add(key);
  if(!textureCache.has(key)) {
   const image=await imageData(descriptor);let texture=image.raw.clone();texture.source=new image.raw.source.constructor(image.raw.image);
   if(role==='scalar') {
    const canvas=document.createElement('canvas');canvas.width=image.canvas.width;canvas.height=image.canvas.height;
    const context=canvas.getContext('2d'), pixels=new ImageData(new Uint8ClampedArray(image.pixels.data),canvas.width,canvas.height);
    for(let i=0;i<pixels.data.length;i+=4){const value=Math.max(pixels.data[i],pixels.data[i+1],pixels.data[i+2]);pixels.data[i]=pixels.data[i+1]=pixels.data[i+2]=pixels.data[i+3]=value;}
    context.putImageData(pixels,0,0);texture.image=canvas;
   }
   textureCache.set(key,configure(texture,descriptor,role!=='color'));
  }
  return textureCache.get(key);
 }
 async function metallicRoughness(rough,metal,used) {
  if(!rough&&!metal) return [null,null];
  // Distinct UV transforms cannot share a packed texture. Google's Three material
  // supports separate roughnessMap / metalnessMap, preserving both exactly.
  if(rough&&metal&&transformKey(rough)!==transformKey(metal)) return [await textureFor(rough,'scalar',used),await textureFor(metal,'scalar',used)];
  const key='mr:'+descriptorKey([rough,metal]);used.add(key);
  if(!textureCache.has(key)) {
   const roughImage=rough?await imageData(rough):null, metalImage=metal?await imageData(metal):null;
   const width=Math.max(roughImage?.canvas.width||1,metalImage?.canvas.width||1),height=Math.max(roughImage?.canvas.height||1,metalImage?.canvas.height||1);
   const read=image=>{
    if(!image)return null;
    if(image.canvas.width===width&&image.canvas.height===height)return image.pixels.data;
    const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;
    const context=canvas.getContext('2d',{willReadFrequently:true});context.drawImage(image.canvas,0,0,width,height);return context.getImageData(0,0,width,height).data;
   };
   const r=read(roughImage),m=read(metalImage),canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;
   const context=canvas.getContext('2d'), pixels=context.createImageData(width,height);
   for(let i=0;i<pixels.data.length;i+=4){pixels.data[i]=255;pixels.data[i+1]=r?Math.max(r[i],r[i+1],r[i+2]):255;pixels.data[i+2]=m?Math.max(m[i],m[i+1],m[i+2]):255;pixels.data[i+3]=255;}
   context.putImageData(pixels,0,0);
   const basis=(roughImage||metalImage).raw;const texture=basis.clone();texture.source=new basis.source.constructor(canvas);
   textureCache.set(key,configure(texture,rough||metal,true));
  }
  const texture=textureCache.get(key);return [rough?texture:null,metal?texture:null];
 }
 const mapSlots={basecolormap:['map','color'],alphamap:['alphaMap','scalar'],normalmap:['normalMap','normal'],ambientocclusionmap:['aoMap','scalar'],emissionmap:['emissiveMap','color'],clearcoatmap:['clearcoatMap','scalar'],clearcoatroughnessmap:['clearcoatRoughnessMap','scalar'],clearcoatnormalmap:['clearcoatNormalMap','normal'],sheencolormap:['sheenColorMap','color'],sheenroughnessmap:['sheenRoughnessMap','scalar'],specularmap:['specularIntensityMap','scalar'],specularcolormap:['specularColorMap','color'],transmissionmap:['transmissionMap','scalar'],volumethicknessmap:['thicknessMap','scalar']};
 const setColor=(target,rgb)=>target?.setRGB(...rgb);
 async function prepareMaterial(key,data,used) {
  const maps={};
  for(const [field,[property,role]] of Object.entries(mapSlots)) maps[property]=await textureFor(data[field],role,used);
  const [roughnessMap,metalnessMap]=await metallicRoughness(data.roughnessmap,data.metalnessmap,used);maps.roughnessMap=roughnessMap;maps.metalnessMap=metalnessMap;
  let pair=instances.get(key);
  if(!pair){pair={lit:templates[0].clone(),unlit:templates[1].clone()};instances.set(key,pair);}
  const material=data.unlit?pair.unlit:pair.lit;
  return {material,maps,apply(){
   setColor(material.color,data.basecolor);setColor(material.emissive,data.emissioncolor);
   material.metalness=data.metalness;material.roughness=data.roughness;
   material.normalScale?.set(data.normal,data.normal);material.aoMapIntensity=data.ambientocclusion;
   material.side=data.doublesided?2:0;material.transparent=data.alphamode===3;material.depthWrite=!material.transparent;material.alphaTest=data.alphamode===2?data.alphacutoff:0;material.opacity=1;
   material.clearcoat=data.enableclearcoat?data.clearcoat:0;material.clearcoatRoughness=data.clearcoatroughness;material.clearcoatNormalScale?.set(data.clearcoatnormal,data.clearcoatnormal);
   material.sheen=data.enablesheen?1:0;setColor(material.sheenColor,data.sheencolor);material.sheenRoughness=data.sheenroughness;
   material.specularIntensity=data.enablespecular?data.specular:1;setColor(material.specularColor,data.enablespecular?data.specularcolor:[1,1,1]);
   material.transmission=data.enabletransmission?data.transmission:0;material.ior=data.enableindexofrefraction?data.indexofrefraction:1.5;
   material.thickness=data.enablevolume?data.volumethickness:0;material.attenuationDistance=data.enablevolume&&data.volumedistance>0?data.volumedistance:Infinity;setColor(material.attenuationColor,data.enablevolume?data.volumecolor:[1,1,1]);
   Object.assign(material,maps);if(!data.aoEnabled)material.aoMap=null;material.needsUpdate=true;
  }};
 }
 async function readJSON(relative) {const response=await fetch(new URL(relative,root),{cache:'no-store'});if(!response.ok)throw new Error('Local sync file unavailable: '+relative);return response.json();}
 async function poll() {
  if(closed||busy||!viewer?.loaded||performance.now()<retryAt)return;
  busy=true;
  try {
   const manifest=await readJSON('manifest.json');
   if(manifest.session!==token)throw new Error('Preview session mismatch.');
   if(manifest.closed){closed=true;show('Google Live Preview: sync stopped. Reopen from Max to start a new session.');return;}
   if(manifest.timestamp===appliedTimestamp)return;
   const scene=privateValue(viewer,'scene'),renderer=privateValue(viewer,'renderer'),loader=privateValue(renderer?.loader,'loader');
   if(!scene?.model?.traverse||!scene.queueRender||!loader?.parse)throw new Error('Google Live Preview adapter is incompatible with this viewer build.');
   if(!templates) {
    const gltf={asset:{version:'2.0'},nodes:[],scenes:[{nodes:[]}],scene:0,materials:[{extensions:{KHR_materials_clearcoat:{clearcoatFactor:0}}},{extensions:{KHR_materials_unlit:{}}}],extensionsUsed:['KHR_materials_clearcoat','KHR_materials_unlit']};
    const parsed=await new Promise((resolve,reject)=>loader.parse(gltf,root.href,resolve,reject));templates=await parsed.parser.getDependencies('material');
   }
   let nextState=structuredClone(state),nextRevision=manifest.revision,nextTimestamp=manifest.timestamp;
   if(revision===0){const initial=await readJSON('state.json');nextState=initial.materials;nextRevision=initial.revision;nextTimestamp=initial.timestamp;}
   else for(let r=revision+1;r<=manifest.revision;r++){const patch=await readJSON('updates/'+r+'.json');for(const [key,changes] of Object.entries(patch.changes))Object.assign(nextState[key],changes);}
   const targets=[];scene.model.traverse(mesh=>{
    if(!mesh.isMesh)return;const key=bindKey(mesh);if(!nextState[key])throw new Error('Source Material ID binding changed. Reopen Live Preview.');
    for(const descriptor of Object.values(nextState[key]))if(descriptor?.url){const attribute=descriptor.uv===0?'uv':'uv'+descriptor.uv;if(!mesh.geometry.attributes[attribute])throw new Error('Required UV channel is absent. Reopen after adding UVs.');}
    targets.push({mesh,key});
   });
   if(new Set(targets.map(target=>target.key)).size!==Object.keys(nextState).length)throw new Error('Source ID layout changed. Reopen Live Preview.');
   const used=new Set(),prepared=new Map();
   for(const [key,data] of Object.entries(nextState))prepared.set(key,await prepareMaterial(key,data,used));
   // Never let an older asynchronous texture merge overwrite a newer change.
   const latest=await readJSON('manifest.json');if(latest.timestamp!==nextTimestamp){
    const activeTextures=new Set([...instances.values()].flatMap(pair=>[pair.lit,pair.unlit]).flatMap(material=>Object.values(material).filter(value=>value?.isTexture)));
    for(const [key,texture] of textureCache)if(!used.has(key)&&!activeTextures.has(texture)){texture.dispose();textureCache.delete(key);}
    return;
   }
   const before=JSON.stringify([viewer.getCameraOrbit(),viewer.getCameraTarget()]),geometries=targets.map(target=>target.mesh.geometry);
   for(const preparedMaterial of prepared.values())preparedMaterial.apply();
   for(const target of targets){const material=prepared.get(target.key).material;material.envMap=target.mesh.material.envMap;material.vertexColors=target.mesh.material.vertexColors;target.mesh.material=material;}
   scene.queueShadowRender();scene.queueRender();revision=nextRevision;appliedTimestamp=nextTimestamp;state=nextState;applyCount++;
   for(const [key,texture] of textureCache)if(!used.has(key)){texture.dispose();textureCache.delete(key);}
   const activeURLs=new Set(Object.values(state).flatMap(material=>Object.values(material).filter(value=>value?.url).map(value=>localURL(value.url))));
   for(const [url,promise] of imageCache)if(!activeURLs.has(url)){promise.then(image=>image.raw.dispose());imageCache.delete(url);}
   status.dataset.check=JSON.stringify({revision,timestamp:appliedTimestamp,applyCount,viewer:'google-model-viewer',cameraPreserved:before===JSON.stringify([viewer.getCameraOrbit(),viewer.getCameraTarget()]),geometryPreserved:targets.every((target,index)=>target.mesh.geometry===geometries[index]),bindings:targets.map(target=>({key:target.key,geometry:target.mesh.geometry.uuid,color:target.mesh.material.color.toArray(),roughness:target.mesh.material.roughness,metalness:target.mesh.material.metalness,thickness:target.mesh.material.thickness,attenuationDistance:target.mesh.material.attenuationDistance,attenuationColor:target.mesh.material.attenuationColor?.toArray(),thicknessMap:!!target.mesh.material.thicknessMap,ao:!!target.mesh.material.aoMap,roughMap:!!target.mesh.material.roughnessMap,metalMap:!!target.mesh.material.metalnessMap,packed:!!target.mesh.material.roughnessMap&&target.mesh.material.roughnessMap===target.mesh.material.metalnessMap,metalPixel:target.mesh.material.metalnessMap?.image?.getContext?Array.from(target.mesh.material.metalnessMap.image.getContext('2d').getImageData(0,0,1,1).data):null,mrPixel:target.mesh.material.roughnessMap?.image?.getContext?Array.from(target.mesh.material.roughnessMap.image.getContext('2d').getImageData(0,0,1,1).data):null}))});
   show('Google Live Preview · auto sync · revision '+revision);
  } catch(error){if(error.message.includes('updates/')||error.message.includes('texture'))revision=0;show('Live Preview: '+error.message,true);retryAt=performance.now()+1500;}
  finally{busy=false;}
 }
 setInterval(poll,150);poll();
})();
