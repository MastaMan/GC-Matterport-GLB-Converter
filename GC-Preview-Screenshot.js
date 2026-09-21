(() => {
  'use strict';
  if (document.getElementById('gc-screenshot-controls')) return;
  const token = new URLSearchParams(location.search).get('captureToken') || '';
  let active = false, cancelled = false;
  const style = document.createElement('style');
  style.textContent = '#gc-screenshot-controls{position:fixed;right:16px;top:12px;z-index:100000;font:13px Arial;color:#fff}#gc-screenshot-controls button,#gc-screenshot-controls select,#gc-screenshot-controls input{font:inherit;padding:8px;border:1px solid #777;border-radius:5px;background:#252525;color:#fff}#gc-screenshot-controls [hidden]{display:none!important}#gc-screenshot-controls button{cursor:pointer;display:inline-block;width:auto}#gc-screenshot-controls button:disabled{opacity:.5}#gc-screenshot-menu{position:absolute;right:0;top:42px;width:220px;padding:12px;background:#252525;border:1px solid #777;border-radius:6px}#gc-screenshot-menu label{display:block;margin:5px 0 9px}#gc-screenshot-status{max-width:410px;margin-top:8px;padding:8px;background:#252525e8;border-radius:5px;overflow-wrap:anywhere}#gc-screenshot-blocker{position:fixed;inset:0;z-index:99999;background:#0002;cursor:wait}';
  document.head.append(style);
  const ui = document.createElement('div'); ui.id = 'gc-screenshot-controls';
  ui.innerHTML = '<button id="gc-take-shot" type="button">Take Screenshot</button> <button id="gc-shot-settings" type="button" aria-label="Screenshot Settings" title="Screenshot Settings">⚙</button><div id="gc-screenshot-menu" hidden><label>Square PNG</label><select id="gc-shot-size"><option value="512">512 × 512</option><option value="1024">1024 × 1024</option><option value="2048" selected>2048 × 2048</option><option value="4096">4096 × 4096</option><option value="custom">Custom size...</option></select><label id="gc-custom-row" hidden>Side, pixels <input id="gc-custom-size" type="number" min="128" max="10000" step="1" value="4096" style="width:100px"></label><p>Keeps the camera view. Renders a square frame.</p></div><div id="gc-screenshot-status" role="status" hidden></div>';
  document.body.append(ui);
  const get = id => document.getElementById(id);
  const status = (text, error=false) => { const box=get('gc-screenshot-status'); box.hidden=false; box.textContent=text; box.style.color=error?'#ffb4a9':'#fff'; };
  get('gc-shot-settings').onclick=()=>{get('gc-screenshot-menu').hidden=!get('gc-screenshot-menu').hidden;};
  get('gc-shot-size').onchange=()=>{get('gc-custom-row').hidden=get('gc-shot-size').value!=='custom';};
  document.addEventListener('keydown', event=>{if(event.key==='Escape' && active) cancelled=true;});
  async function api(path, body, extra={}) {
    const response=await fetch('/gc-screenshot/'+path,{method:body===undefined?'GET':'POST',headers:{'X-GC-Token':token,...extra},body});
    const result=await response.json();
    if(!response.ok) throw new Error(result.error || 'Local server error.');
    return result;
  }
  function privateValue(object, name) {
    for(let current=object;current;current=Object.getPrototypeOf(current)) {
      const symbol=Object.getOwnPropertySymbols(current).find(key=>key.description===name);
      if(symbol) return object[symbol];
    }
  }
  async function pixelsPNG(pixels,width,height,background) {
    const canvas=document.createElement('canvas'); canvas.width=width; canvas.height=height;
    const context=canvas.getContext('2d');
    if(!context) throw new Error('Cannot create screenshot canvas.');
    const image=context.createImageData(width,height);
    for(let row=0;row<height;row++) image.data.set(pixels.subarray((height-row-1)*width*4,(height-row)*width*4),row*width*4);
    context.putImageData(image,0,0);
    if(background) {context.globalCompositeOperation='destination-over';context.fillStyle=background;context.fillRect(0,0,width,height);}
    return new Promise((resolve,reject)=>canvas.toBlob(blob=>{canvas.width=canvas.height=1;blob?resolve(blob):reject(new Error('PNG encoder failed.'));},'image/png'));
  }
  // Optional local regression probe: compare opaque pixels at matching view rays.
  function colorProbe(reference,width,height) {
    const samples=[];
    for(const u of [-.2,-.1,0,.1,.2]) for(const v of [-.2,-.1,0,.1,.2]) {
      const x=Math.floor(width/2+u*height), y=Math.floor(height/2-v*height), offset=(y*width+x)*4;
      samples.push({u,v,reference:Array.from(reference.subarray(offset,offset+4))});
    }
    return (pixels,size,x,y,width,height)=>{
      for(const sample of samples) {
        const sx=Math.floor((sample.u+.5)*size)-x, sy=Math.floor((sample.v+.5)*size)-y;
        if(sx>=0&&sx<width&&sy>=0&&sy<height) {
          const offset=((height-1-sy)*width+sx)*4;
          sample.actual=Array.from(pixels.subarray(offset,offset+4));
        }
      }
      const checked=samples.filter(s=>s.actual&&s.actual[3]===255&&s.reference[3]===255);
      const errors=checked.flatMap(s=>s.actual.slice(0,3).map((v,i)=>Math.abs(v-s.reference[i])));
      get('gc-screenshot-status').dataset.colorCheck=JSON.stringify({count:checked.length,mean:errors.reduce((a,b)=>a+b,0)/(errors.length||1),max:Math.max(0,...errors),samples:checked});
    };
  }
  function googleAdapter() {
    const element=document.querySelector('model-viewer');
    if(!element?.loaded) throw new Error('Wait for the model to finish loading.');
    const scene=privateValue(element,'scene'), shared=privateValue(element,'renderer'), renderer=shared?.threeRenderer;
    if(!scene || !renderer || scene.effectRenderer) throw new Error('This Google Viewer version does not support screenshots.');
    const gl=renderer.getContext(), limit=Math.min(2048,gl.getParameter(gl.MAX_RENDERBUFFER_SIZE));
    const camera=scene.camera.clone(); camera.aspect=1; camera.clearViewOffset(); camera.updateProjectionMatrix();
    const previousTarget=renderer.getRenderTarget(), previousTone=renderer.toneMapping, previousExposure=renderer.toneMappingExposure;
    const ratio=renderer.getPixelRatio(), savedWidth=renderer.domElement.width/ratio, savedHeight=renderer.domElement.height/ratio;
    const viewport=renderer.getViewport({copy(v){return [v.x,v.y,v.z,v.w];}});
    let probe=null;
    if(new URLSearchParams(location.search).has('colorCheck')) {
      const reference=new Uint8Array(viewport[2]*viewport[3]*4);
      gl.readPixels(...viewport,gl.RGBA,gl.UNSIGNED_BYTE,reference);
      probe=colorProbe(reference,viewport[2],viewport[3]);
    }
    const wasPaused=element.paused;
    function restore() {
      renderer.setPixelRatio(ratio); renderer.setSize(savedWidth,savedHeight,false);
      renderer.setRenderTarget(previousTarget); renderer.setViewport(...viewport);
      renderer.toneMapping=previousTone; renderer.toneMappingExposure=previousExposure;
      renderer.setAnimationLoop((time,frame)=>shared.render(time,frame));
      scene.queueRender(); if(!wasPaused) element.play();
    }
    try {
      element.pause(); renderer.setAnimationLoop(null);
      shared.preRender(scene,performance.now(),0); scene.renderShadow(renderer);
      renderer.toneMapping=scene.toneMapping; renderer.setPixelRatio(1);
    } catch(error) { restore(); throw error; }
    return {
      limit,
      async tile(size,x,y,width,height) {
        // Three.js skips tone mapping for ordinary offscreen targets. Use the same
        // output framebuffer as the preview, with a square camera and tiled view.
        renderer.setSize(width,height,false); renderer.setRenderTarget(null);
        renderer.setViewport(0,0,width,height);
        camera.setViewOffset(size,size,x,y,width,height);
        renderer.render(scene,camera);
        if(gl.isContextLost()) throw new Error('WebGL context was lost during rendering.');
        const pixels=new Uint8Array(width*height*4);
        gl.readPixels(0,0,width,height,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
        probe?.(pixels,size,x,y,width,height);
        if(renderer.getContextAttributes().premultipliedAlpha) {
          for(let i=0;i<pixels.length;i+=4) {
            const alpha=pixels[i+3];
            if(alpha>0 && alpha<255) for(let c=0;c<3;c++) pixels[i+c]=Math.min(255,Math.round(pixels[i+c]*255/alpha));
          }
        }
        return pixelsPNG(pixels,width,height,getComputedStyle(document.body).backgroundColor);
      },
      restore
    };
  }
  function playcanvasAdapter() {
    const viewer=window.viewer;
    if(!viewer?.entities?.length || viewer.firstFrame) throw new Error('Wait for the model to finish loading.');
    const app=viewer.app, device=app.graphicsDevice, component=viewer.activeSceneCamera || viewer.camera.camera;
    if(device.isWebGPU || viewer.xrMode?.active) throw new Error('Use WebGL 2 without AR to take a screenshot.');
    const originalTarget=component.renderTarget;
    if(!originalTarget?.colorBuffer) throw new Error('The model render target is not ready.');
    const gl=device.gl, limit=Math.min(2048,device.maxTextureSize,gl.getParameter(gl.MAX_RENDERBUFFER_SIZE));
    const Texture=originalTarget.colorBuffer.constructor, Target=originalTarget.constructor;
    const probeReady=new URLSearchParams(location.search).has('colorCheck') ? originalTarget.colorBuffer.read(0,0,originalTarget.width,originalTarget.height).then(pixels=>colorProbe(pixels,originalTarget.width,originalTarget.height)) : Promise.resolve(null);
    const saved={projection:component.calculateProjection,aspect:component.aspectRatio,aspectMode:component.aspectRatioMode,
      auto:app.autoRender,next:app.renderNextFrame,timeScale:app.timeScale,controls:viewer.cameraControls.enabled,
      stats:viewer.miniStats.enabled,multiframe:viewer.multiframe.enabled,layers:component.layers.slice()};
    const events=[['update',viewer.update],['framerender',viewer.onFrameRender],['prerender',viewer.onPrerender],['postrender',viewer.onPostrender],['frameend',viewer.onFrameend]];
    viewer.onPrerender();
    const base=component.projectionMatrix.clone();
    if(component.projection===0) base.setPerspective(component.fov,1,component.nearClip,component.farClip,component.horizontalFov);
    else base.setOrtho(-component.orthoHeight,component.orthoHeight,-component.orthoHeight,component.orthoHeight,component.nearClip,component.farClip);
    let currentProjection=base.clone(), target=null, texture=null;
    const applyProjection=cam=>{if(cam===component) {component.projectionMatrix.copy(currentProjection); component.camera._viewProjMatDirty=true;}};
    events.forEach(([event,handler])=>app.off(event,handler,viewer));
    app.autoRender=false; app.renderNextFrame=false; app.timeScale=0;
    viewer.cameraControls.enabled=false; viewer.miniStats.enabled=false; viewer.multiframe.enabled=false;
    app.scene.on('prerender',applyProjection);
    component.aspectRatioMode=1; component.aspectRatio=1; component.layers=saved.layers.filter(id=>id!==viewer.miniStats.drawLayer.id);
    const destroyTarget=()=>{if(target) target.destroy();if(texture) texture.destroy();target=texture=null;};
    return {
      limit,
      async tile(size,x,y,width,height) {
        const probe=await probeReady;
        destroyTarget();
        texture=new Texture(device,{name:'GC Screenshot',width,height,format:originalTarget.colorBuffer.format,mipmaps:false,minFilter:0,magFilter:0});
        target=new Target({colorBuffer:texture,depth:true,samples:Math.min(originalTarget.samples,4),autoResolve:true,flipY:false});
        currentProjection.copy(base);
        const input=base.data, output=currentProjection.data;
        for(let column=0;column<4;column++) {
          output[column*4]=input[column*4]*size/width + input[column*4+3]*(size-2*x-width)/width;
          output[column*4+1]=input[column*4+1]*size/height + input[column*4+3]*(2*y+height-size)/height;
        }
        component.calculateProjection=matrix=>matrix.copy(currentProjection);
        component.renderTarget=target;
        app.render(); if(target.samples>1) target.resolve();
        if(gl.isContextLost()) throw new Error('WebGL context was lost during rendering.');
        const pixels=await texture.read(0,0,width,height);
        probe?.(pixels,size,x,y,width,height);
        return pixelsPNG(pixels,width,height,getComputedStyle(document.getElementById('canvas-wrapper')).backgroundColor);
      },
      restore() {
        component.renderTarget=originalTarget; component.calculateProjection=saved.projection;
        component.aspectRatioMode=saved.aspectMode; component.aspectRatio=saved.aspect; component.layers=saved.layers;
        app.scene.off('prerender',applyProjection); destroyTarget();
        events.forEach(([event,handler])=>app.on(event,handler,viewer));
        app.autoRender=saved.auto; app.timeScale=saved.timeScale;
        viewer.cameraControls.enabled=saved.controls; viewer.miniStats.enabled=saved.stats; viewer.multiframe.enabled=saved.multiframe;
        viewer.renderNextFrame();
      }
    };
  }
  async function capture(size) {
    if(active) throw new Error('A screenshot is already in progress.');
    if(!Number.isInteger(size) || size<128 || size>10000) throw new Error('Enter an integer side length from 128 to 10000 pixels.');
    active=true; cancelled=false;
    const blocker=document.createElement('div'); blocker.id='gc-screenshot-blocker'; document.body.append(blocker);
    get('gc-take-shot').disabled=get('gc-shot-settings').disabled=true; get('gc-screenshot-menu').hidden=true;
    let adapter=null, captureId=null;
    try {
      const config=await api('config');
      if(!config.canSave) throw new Error('Save the scene in 3ds Max, then reopen Preview.');
      adapter=document.querySelector('model-viewer')?googleAdapter():playcanvasAdapter();
      if(adapter.limit<1) throw new Error('WebGL render target is unavailable.');
      const session=await api('begin',JSON.stringify({width:size,height:size}),{'Content-Type':'application/json'});
      captureId=session.id;
      const tileSize=Math.floor(Math.min(config.tileLimit,adapter.limit));
      const tileCount=Math.ceil(size/tileSize)**2; let completed=0;
      for(let y=0;y<size;y+=tileSize) for(let x=0;x<size;x+=tileSize) {
        if(cancelled) throw new Error('Screenshot cancelled.');
        status('Rendering '+size+' × '+size+': '+completed+' / '+tileCount+' (Esc to cancel)');
        const blob=await adapter.tile(size,x,y,Math.min(tileSize,size-x),Math.min(tileSize,size-y));
        await api('tile',blob,{'Content-Type':'image/png','X-GC-Capture':captureId,'X-GC-X':String(x),'X-GC-Y':String(y)});
        completed++;
      }
      if(cancelled) throw new Error('Screenshot cancelled.');
      status('Saving PNG '+size+' × '+size+'…');
      const result=await api('finish','',{'X-GC-Capture':captureId});
      captureId=null; status('Saved: '+result.path); return result;
    } finally {
      if(captureId) {try {await api('cancel','',{'X-GC-Capture':captureId});} catch(error) {console.warn(error);}}
      try {adapter?.restore();} finally {
        blocker.remove();active=false;
        get('gc-take-shot').disabled=get('gc-shot-settings').disabled=false;
      }
    }
  }
  get('gc-take-shot').onclick=()=>capture(Number(get('gc-shot-size').value==='custom'?get('gc-custom-size').value:get('gc-shot-size').value)).catch(error=>status(error.message,true));
  window.GCPreviewScreenshot={capture};
})();