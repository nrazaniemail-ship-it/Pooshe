const C="pooshe-v6";
const A=["./","./index.html","./manifest.webmanifest","./pooshe-icon.png"];

self.addEventListener("install",event=>{
  event.waitUntil(
    caches.open(C)
      .then(cache=>cache.addAll(A))
      .then(()=>self.skipWaiting())
  );
});

self.addEventListener("activate",event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(key=>key!==C).map(key=>caches.delete(key))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener("fetch",event=>{
  const request=event.request;
  if(request.method!=="GET" || new URL(request.url).origin!==location.origin) return;

  event.respondWith((async()=>{
    const cache=await caches.open(C);
    try{
      const response=await fetch(request,{cache:"no-store"});
      if(response && response.ok) await cache.put(request,response.clone());
      return response;
    }catch(error){
      const cached=await cache.match(request);
      if(cached) return cached;
      if(request.mode==="navigate"){
        const fallback=await cache.match("./index.html");
        if(fallback) return fallback;
      }
      throw error;
    }
  })());
});
