extends Node
## One set's web browser (web_engine.gd starts Chromium; these are browser views in it). It draws
## the set's screen (screen_common.gd spec "page" pixels) in a SubViewport of its own: a toolbar
## across the top (back, forward, reload, the address, the tabs, a new tab, the zoom) over the
## active tab's page. Each tab is a gdCEF browser rendering off screen with its own speaker (a
## child of the set's, so it comes from the set, fades with distance and follows its volume).
## Pointer, clicks, wheel and keys come from TV mode (screen_input.gd): on the toolbar they go to
## its controls, on the page to the tab.
## For ponies watching along (watch_company.gd) it keeps the pages opened (history: [[seconds,
## title]], seconds since the browser opened) and a little of the page's visible text.
## Things Chromium would show in windows of its own, which an off-screen browser has none of, are
## kept from it (gdCEF 0.20 handles none of them, and two playtest crashes, 2026-11-03, came
## seconds after a cancelled right-click menu and a page touching the microphone): see GUARD_JS.
## Picking a file for the page (a picture to post) opens the game's own file dialog instead, and a
## right click opens a menu of the mod's own (open, open in a new tab, save, copy, paste) in place of
## Chromium's. Saving (that menu, a page's download link) goes to the system Downloads folder, done
## by the mod itself: gdCEF 0.20's own downloads never finish with this Chromium (its
## OnBeforeDownload answers false, cef.log "Should return true from OnBeforeDownload"). A middle
## click off a link scrolls as the pointer moves away from where it was, until the next click. The tabs are kept in the settings and come back when
## the browser opens again. Known ad servers (EasyList's whole-domain rules, easylist_domains.txt)
## are blocked by gdCEF's own ad blocker. A page gone full screen (a video) gets the whole screen,
## the toolbar hidden until it leaves full screen. On a YouTube video page (YT_JS) the mod follows
## the video, its captions (turned on hidden when the player has not asked to see them) and its
## ads, for ponies watching along (tv_set.gd status, watch_company.gd).
## CyTube rooms (cytu.be, ROOM_JS): when the room plays a file or stream the page's player cannot
## (H.264 in an HLS playlist or an MP4: gdCEF's Chromium has no H.264), the mod plays it itself
## through ffmpeg (media_player.gd) over the page's video, in step with the room's clock.
## gdCEF API: github.com/Lecrapouille/gdcef doc/API.md and its sources (browser_io.cpp); every
## browser signal passes the browser last.

signal painted(texture: Texture2D)
## A text box on the page or the address bar took (true) or lost (false) the focus: the VR
## keyboard follows it.
signal typing(on: bool)
## Something to tell the player on the set's caption (a download finished...).
signal notice(text: String)

const STYLE := preload("res://world/ui/menu_style.gd")
const HOME := "https://duckduckgo.com/"
const FRAME_RATE := 30
## One mouse wheel notch; gdCEF scrolls ten pixels a unit (playtests: 2 was too little, 6 a bit slow).
const WHEEL_NOTCH := 7
const TEXT_KEEP := 1500
const TEXT_EVERY := 20.0
const WATCH_EVERY := 0.5
## The toolbar's height in screen pixels, and its font size.
const BAR := 56
const BAR_FONT := 22
## Zoom steps in percent (Ctrl + wheel, Ctrl +/-; Ctrl 0 or the zoom button: the setting's own).
const ZOOMS := [50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300]
## Each tab is a whole Chromium page in memory.
const TABS_MAX := 20
## The address bar's width at rest and while typing in it; the tabs take the rest of the bar, each
## up to TAB_WIDEST wide and down to a tenth of the room (more tabs than that scroll: wheel, arrows).
const ADDRESS_REST := 300
const ADDRESS_TYPING := 640
const TAB_WIDEST := 260
const TABS_SHOWN := 10
## Sites whose videos cannot play here, told once a visit: gdCEF's Chromium has no licensed
## H.264/AAC (Twitch, Kick) and no verified DRM (Netflix and the other paid services refuse it).
const NO_PLAY := {"netflix.com": "DRM", "disneyplus.com": "DRM", "hulu.com": "DRM", "max.com": "DRM", "primevideo.com": "DRM",
	"amazon.com/gp/video": "DRM", "tv.apple.com": "DRM", "peacocktv.com": "DRM", "paramountplus.com": "DRM", "crunchyroll.com": "DRM",
	"open.spotify.com": "DRM", "twitch.tv": "H.264", "kick.com": "H.264"}
## The largest file handed to a page (it travels as text through the page's script).
const PICK_MAX_BYTES := 40 * 1024 * 1024
const MIME := {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp",
	"bmp": "image/bmp", "webm": "video/webm", "mp4": "video/mp4", "pdf": "application/pdf", "txt": "text/plain", "mp3": "audio/mpeg"}
const PICTURES := ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
## Printable characters whose code is also the Windows key code of another key: gdCEF sends each
## character as a key press of that code before typing it ('.' is Delete, "'" Right, '!' PageUp,
## '#' End, ']' the menu key...), so they are typed through the page instead.
const CLASHING := "!\"#$%&'()*+,-./[\\]^_`{|}~"
## Kept from the page (each document, as it starts and once loaded): alert/confirm/prompt answer at
## once, "leave this page?" is never asked, microphone, camera, screen, notification and location
## requests are refused at once, a file input asks Godot (file_wanted) instead of Chromium, and
## new windows open as a new tab (open_tab). A left click on a target=_blank link the page does not
## handle itself opens it in the same tab (4chan's thumbnails are such links, expanded by the page:
## only the middle button opens a tab). A download link (download attribute, a blob, a booru's
## /img/download/) is saved by the mod (download), and the page going full screen is told.
## Full screen and videos that behave on any page (playtests 2026-11-07, Twibooru and Derpibooru):
## - A page asking for full screen that Chromium does not give it within 0.4 s gets the element
##   stretched over the whole page instead; the page sees it as full screen (fullscreenElement), so
##   its own exit (the F key on a booru, its button) works, and is told it changed.
## - A plain video with the browser's own controls: a click plays or pauses it (a quarter second
##   later, so a double click does not), a double click goes full screen or back, and Space plays
##   or pauses the video last clicked (not while typing). The site's own click on it (a booru
##   enlarging the picture) does not happen. Clicks on its control bar are its own.
## - Twice a second the toolbar is told whether the page is full screen, however it came or went
##   (it stayed hidden when F left full screen).
const FULL_JS := "(function(){if(window.__wpFullGuard)return;window.__wpFullGuard=true;var G=function(n){return window.godotMethods&&window.godotMethods[n];};var D=Document.prototype;var fsD=Object.getOwnPropertyDescriptor(D,'fullscreenElement'),wkD=Object.getOwnPropertyDescriptor(D,'webkitFullscreenElement');var real=function(){var a=fsD&&fsD.get?fsD.get.call(document):null;var b=wkD&&wkD.get?wkD.get.call(document):null;return a||b;};var fake=null,old=null,over='',told=null;var tell=function(on){on=!!on;if(on===told)return;told=on;var f=G('full_screen');if(f)f(on);};var sync=function(){tell(fake||real());};var changed=function(){try{document.dispatchEvent(new Event('fullscreenchange'));document.dispatchEvent(new Event('webkitfullscreenchange'));}catch(e){}};var leave=function(){if(!fake)return;if(old===null)fake.removeAttribute('style');else fake.setAttribute('style',old);document.documentElement.style.overflow=over;fake=null;sync();changed();};var enter=function(el){if(fake)leave();if(!el||!el.style)return;fake=el;old=el.getAttribute('style');over=document.documentElement.style.overflow;el.style.cssText+=';position:fixed!important;left:0!important;top:0!important;right:0!important;bottom:0!important;width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;margin:0!important;z-index:2147483647!important;background:#000!important;object-fit:contain!important;transform:none!important;';document.documentElement.style.overflow='hidden';sync();changed();};try{Object.defineProperty(D,'fullscreenElement',{configurable:true,get:function(){return fake||(fsD&&fsD.get?fsD.get.call(this):null);}});Object.defineProperty(D,'webkitFullscreenElement',{configurable:true,get:function(){return fake||(wkD&&wkD.get?wkD.get.call(this):null);}});Object.defineProperty(D,'webkitIsFullScreen',{configurable:true,get:function(){return !!(fake||real());}});}catch(e){}var ex=D.exitFullscreen;D.exitFullscreen=function(){if(fake){leave();return Promise.resolve();}return ex?ex.apply(this,arguments):Promise.resolve();};var wex=D.webkitExitFullscreen;if(wex)D.webkitExitFullscreen=function(){if(fake){leave();return;}return wex.apply(this,arguments);};window.__wpLeaveFull=function(){if(real()&&ex)ex.call(document).catch(function(){});leave();};var wrap=function(proto,name){var orig=proto[name];if(!orig)return;proto[name]=function(){var el=this,p=null;try{p=orig.apply(el,arguments);}catch(e){}setTimeout(function(){if(!real())enter(el);},400);return p&&p.catch?p.catch(function(){}):Promise.resolve();};};wrap(Element.prototype,'requestFullscreen');wrap(Element.prototype,'webkitRequestFullscreen');wrap(Element.prototype,'webkitRequestFullScreen');if(window.HTMLVideoElement)wrap(HTMLVideoElement.prototype,'webkitEnterFullscreen');var plain=function(t){return !!(t&&t.tagName&&t.tagName.toLowerCase()==='video'&&t.controls);};var onBar=function(v,e){var r=v.getBoundingClientRect();return e.clientY>r.bottom-48;};var flip=function(v){if(v.paused){var p=v.play();if(p&&p.catch)p.catch(function(){});}else v.pause();};var toggleFull=function(v){if(fake||real()){if(real()&&ex)ex.call(document).catch(function(){});leave();return;}if(v.requestFullscreen)v.requestFullscreen();else enter(v);};var last=null,pending=null;document.addEventListener('click',function(e){var t=e.target;if(!plain(t)){if(e.isTrusted)last=null;return;}last=t;if(onBar(t,e))return;e.preventDefault();e.stopImmediatePropagation();if(pending)clearTimeout(pending);pending=setTimeout(function(){pending=null;flip(t);},250);},true);document.addEventListener('dblclick',function(e){var t=e.target;if(!plain(t)||onBar(t,e))return;e.preventDefault();e.stopImmediatePropagation();if(pending){clearTimeout(pending);pending=null;}toggleFull(t);},true);document.addEventListener('keydown',function(e){if(e.key!==' '&&e.code!=='Space')return;if(e.ctrlKey||e.altKey||e.metaKey)return;var a=document.activeElement;if(a&&(a.isContentEditable||/^(input|textarea|select)$/i.test(a.tagName||'')))return;var v=plain(fake)?fake:last;if(!v||!document.contains(v))return;e.preventDefault();e.stopImmediatePropagation();flip(v);},true);document.addEventListener('fullscreenchange',sync);document.addEventListener('webkitfullscreenchange',sync);setInterval(sync,500);})();"
const TOGGLE_FULL_JS := "if(window.__wpToggleFull)window.__wpToggleFull();"
const LEAVE_FULL_JS := "if((document.fullscreenElement||document.webkitFullscreenElement)&&document.exitFullscreen)document.exitFullscreen().catch(function(){});if(window.__wpLeaveFull)window.__wpLeaveFull();"
const GUARD_JS := "(function(){if(window.__watchPartyGuard)return;window.__watchPartyGuard=true;var G=function(n){return window.godotMethods&&window.godotMethods[n];};window.alert=function(){};window.confirm=function(){return true;};window.prompt=function(m,d){return d===undefined?'':String(d);};window.print=function(){};window.onbeforeunload=null;var add=EventTarget.prototype.addEventListener;EventTarget.prototype.addEventListener=function(t,f,o){if(t==='beforeunload')return;return add.call(this,t,f,o);};var no=function(){return Promise.reject(new DOMException('Not allowed here','NotAllowedError'));};try{var md=navigator.mediaDevices;if(md){md.getUserMedia=no;md.getDisplayMedia=no;md.enumerateDevices=function(){return Promise.resolve([]);};}navigator.getUserMedia=navigator.webkitGetUserMedia=function(a,b,c){if(c)c(new DOMException('Not allowed here','NotAllowedError'));};}catch(e){}try{if(window.Notification){Notification.requestPermission=function(){return Promise.resolve('denied');};}}catch(e){}try{if(navigator.permissions){navigator.permissions.query=function(){return Promise.resolve({state:'denied',onchange:null,addEventListener:function(){},removeEventListener:function(){}});};}}catch(e){}try{if(navigator.geolocation){navigator.geolocation.getCurrentPosition=function(a,b){if(b)b({code:1,message:'denied'});};navigator.geolocation.watchPosition=function(a,b){if(b)b({code:1,message:'denied'});return 0;};}}catch(e){}window.open=function(u){if(u){var f=G('open_tab');if(f)f(String(new URL(u,location.href)));else location.href=u;}return null;};var pick=function(n){window.__watchPartyFile=n;var f=G('file_wanted');if(f)f(n.accept||'',!!n.multiple);};var click=HTMLInputElement.prototype.click;HTMLInputElement.prototype.click=function(){if((this.type||'').toLowerCase()==='file'){pick(this);return;}return click.call(this);};try{var sp=HTMLInputElement.prototype.showPicker;if(sp)HTMLInputElement.prototype.showPicker=function(){if((this.type||'').toLowerCase()==='file'){pick(this);return;}return sp.call(this);};}catch(e){}document.addEventListener('click',function(e){var n=e.target;while(n&&n.tagName){var t=n.tagName.toLowerCase();if(t==='a'&&n.href&&e.isTrusted&&e.button===0&&(n.hasAttribute('download')||n.href.indexOf('blob:')===0||n.pathname.indexOf('/img/download/')===0)){e.preventDefault();e.stopPropagation();var dl=G('download');if(dl)dl(n.href,n.getAttribute('download')||'',navigator.userAgent);return;}if(t==='input'&&(n.type||'').toLowerCase()==='file'){e.preventDefault();e.stopPropagation();pick(n);return;}if(t==='label'&&n.control&&(n.control.type||'').toLowerCase()==='file'){e.preventDefault();e.stopPropagation();pick(n.control);return;}n=n.parentNode;}},true);window.addEventListener('click',function(e){if(e.defaultPrevented||e.button!==0)return;var n=e.target;while(n&&n.tagName){if(n.tagName.toLowerCase()==='a'&&n.href&&n.target&&n.target!=='_self'&&n.target!=='_top'&&n.target!=='_parent'){if(n.hasAttribute('download'))return;e.preventDefault();location.href=n.href;return;}n=n.parentNode;}},false);})();"
## What is under the pointer (x, y in page pixels) for the right-click menu: link, image, video,
## the selected text and whether it is a text box (context_menu, as JSON).
const CONTEXT_JS := "(function(x,y){var d=window.devicePixelRatio||1,e=document.elementFromPoint(x/d,y/d),r={link:'',image:'',video:'',text:String(window.getSelection()||''),edit:false,agent:navigator.userAgent};for(var n=e;n&&n.tagName;n=n.parentElement){var t=n.tagName.toLowerCase();if(!r.link&&t==='a'&&n.href)r.link=n.href;if(!r.image&&t==='img')r.image=n.currentSrc||n.src||'';if(!r.video&&t==='video')r.video=n.currentSrc||n.src||'';}if(e&&(e.isContentEditable||/^(input|textarea)$/i.test(e.tagName||'')))r.edit=true;var f=window.godotMethods&&window.godotMethods.context_menu;if(f)f(JSON.stringify(r));})(%d,%d);"
## The link under the pointer (middle click) opens in a tab of its own; off a link, scrolling by
## the pointer starts (middle_free).
const LINK_JS := "(function(x,y){var d=window.devicePixelRatio||1,n=document.elementFromPoint(x/d,y/d);while(n&&n.tagName&&!(n.tagName.toLowerCase()==='a'&&n.href))n=n.parentElement;var g=window.godotMethods;if(!g)return;if(n&&n.href){if(g.open_background)g.open_background(n.href);}else if(g.middle_free)g.middle_free();})(%d,%d);"
## Text boxes report focus to Godot (window.godotMethods, gdCEF's JS bridge; the method's name
## without its leading underscore).
const FOCUS_JS := "(function(){if(window.__watchPartyFocus)return;window.__watchPartyFocus=true;function text(e){if(!e)return false;if(e.isContentEditable)return true;var t=(e.tagName||'').toLowerCase();if(t==='textarea')return true;if(t==='iframe')return 2;if(t!=='input')return false;var y=(e.type||'text').toLowerCase();return ['text','search','email','url','password','tel','number'].indexOf(y)>=0;}function tell(on){if(window.godotMethods&&window.godotMethods.text_focus)window.godotMethods.text_focus(on);}document.addEventListener('focusin',function(e){tell(+text(e.target));},true);document.addEventListener('focusout',function(){tell(0);},true);var a=text(document.activeElement);if(a)tell(+a);})();"
## Types text at the caret of whatever has the focus (same-origin frames too).
const INSERT_JS := "(function(t){var d=document,e=d.activeElement;while(e&&e.tagName==='IFRAME'){try{d=e.contentDocument;e=d.activeElement;}catch(x){break;}}if(d.execCommand('insertText',false,t))return;if(e&&'value' in e){var v=e.value,s=e.selectionStart,n=e.selectionEnd;try{e.value=v.slice(0,s)+t+v.slice(n);e.selectionStart=e.selectionEnd=s+t.length;}catch(x){e.value=v+t;}e.dispatchEvent(new Event('input',{bubbles:true}));}})(%s);"
## Hands picked files to the file input the page asked with: [{n: name, t: type, d: base64}].
const FILES_JS := "(function(list){var i=window.__watchPartyFile;if(!i)return;var dt=new DataTransfer();list.forEach(function(f){var b=atob(f.d),a=new Uint8Array(b.length);for(var k=0;k<b.length;k++)a[k]=b.charCodeAt(k);dt.items.add(new File([a],f.n,{type:f.t}));});i.files=dt.files;i.dispatchEvent(new Event('input',{bubbles:true}));i.dispatchEvent(new Event('change',{bubbles:true}));})(%s);"
## YouTube (youtube.com pages, from their first load; the site changes pages without loading):
## twice a second on a video page, the video, where it is, whether an ad is on and the caption
## lines up (youtube, as JSON). Captions are turned on for the ponies (English if there are any)
## and hidden unless the player shows them: the CC button and the C key show or hide them
## instead of turning them off (kept in the site's own storage).
const YT_JS := "(function(){if(window.__watchPartyTube)return;window.__watchPartyTube=true;var G=function(n){return window.godotMethods&&window.godotMethods[n];};var KEY='watchPartyCaptions',css=document.createElement('style'),asked='',tries=0,list=0,clicking=false,last='';function shown(){try{return localStorage.getItem(KEY)==='shown';}catch(e){return false;}}function apply(){var t=shown()?'':'.ytp-caption-window-container{opacity:0!important}';if(css.textContent!==t)css.textContent=t;if(!css.isConnected)(document.head||document.documentElement).appendChild(css);}function toggle(){try{localStorage.setItem(KEY,shown()?'hidden':'shown');}catch(e){}apply();}document.addEventListener('click',function(e){if(clicking)return;var b=e.target&&e.target.closest&&e.target.closest('.ytp-subtitles-button');if(b){e.preventDefault();e.stopImmediatePropagation();toggle();}},true);document.addEventListener('keydown',function(e){if(e.key!=='c'&&e.key!=='C')return;if(e.ctrlKey||e.altKey||e.metaKey)return;var t=e.target,n=((t&&t.tagName)||'').toLowerCase();if(n==='input'||n==='textarea'||(t&&t.isContentEditable))return;e.preventDefault();e.stopImmediatePropagation();toggle();},true);function on(p,id){if(asked===id||tries>20)return;tries++;var l=[];try{if(p.loadModule)p.loadModule('captions');l=p.getOption('captions','tracklist')||[];}catch(e){}list=l.length;if(!l.length){var b=document.querySelector('.ytp-subtitles-button');if(tries>6&&b&&b.offsetParent&&b.getAttribute('aria-pressed')==='false'){clicking=true;b.click();clicking=false;asked=id;}return;}asked=id;var c=null;try{c=p.getOption('captions','track');}catch(e){}if(c&&c.languageCode)return;var en=l.filter(function(t){return /^en/.test(t.languageCode||'');});var k=en.filter(function(t){return t.kind!=='asr';})[0]||en[0]||l[0];try{p.setOption('captions','track',k);}catch(e){}}setInterval(function(){apply();var f=G('youtube');if(!f)return;var p=document.getElementById('movie_player');if(location.pathname!=='/watch'||!p||!p.getVideoData){f(JSON.stringify({video:false,url:location.href}));return;}var d=p.getVideoData()||{};if(!d.video_id)return;if(d.video_id!==last){last=d.video_id;asked='';tries=0;list=0;}on(p,d.video_id);var ad=p.classList.contains('ad-showing'),lines=[];document.querySelectorAll('.caption-visual-line').forEach(function(s){var t=(s.textContent||'').replace(/\\s+/g,' ').trim();if(t)lines.push(t);});f(JSON.stringify({video:true,url:location.href,id:d.video_id,title:d.title||'',channel:d.author||'',time:p.getCurrentTime?p.getCurrentTime():0,length:p.getDuration?p.getDuration():0,state:p.getPlayerState?p.getPlayerState():-1,ad:ad,captions:list>0||lines.length>0,lines:ad?[]:lines}));},500);})();"
## A blob: or data: address the page made, read by the page and handed over as base64 (save_data).
const BLOB_JS := "(function(u,n){fetch(u).then(function(r){return r.blob();}).then(function(b){var d=new FileReader();d.onload=function(){var f=window.godotMethods&&window.godotMethods.save_data;if(f)f(n,b.type||'',String(d.result).split(',')[1]||'');};d.readAsDataURL(b);});})(%s,%s);"
const AGENT := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36"
## Scrolling by the pointer (middle click off a link): no scrolling this close to where it started
## (screen pixels), then this many page pixels a second for each pixel further.
const SCROLL_STILL := 14.0
const SCROLL_SPEED := 6.0
## ...and faster still the further it goes: at SCROLL_RAMP pixels out twice that, and so on (to
## get to the bottom of a long page quickly).
const SCROLL_RAMP := 120.0
## Caption lines kept for one video, and how long after a caption changes it counts as talking.
const TUBE_LINES := 3000
const TUBE_TALKING := 1.5
const AD_LIST := "res://mods/watch_party/easylist_domains.txt"
## CyTube (cytu.be): twice a second, the room's media (type, id, length), where the room is in it
## (from the server's own updates, which the page's handlers are wrapped to hear), whether the
## page's player failed (an error, or not moving for 6 s while the room plays: a room without
## autoplay leaves it on its play button, which does nothing for H.264), and where the video sits
## on the page (page pixels). While the mod plays the room (__watchPartyOwn) the page's player is
## kept paused and muted.
const ROOM_JS := "(function(){if(window.__watchPartyRoom)return;window.__watchPartyRoom=true;var room={time:0,at:0,paused:true,known:false},last=-1,still=0;function wrap(){var C=window.Callbacks;if(!C||C.__watchParty)return;C.__watchParty=true;['changeMedia','mediaUpdate'].forEach(function(k){var f=C[k];if(typeof f!=='function')return;C[k]=function(d){try{if(d&&typeof d.currentTime==='number'){room.time=d.currentTime;room.at=Date.now();room.paused=!!d.paused;room.known=true;}}catch(e){}return f.apply(this,arguments);};});}setInterval(function(){wrap();var g=window.godotMethods&&window.godotMethods.room;if(!g)return;var P=window.PLAYER,r=null,w=document.getElementById('videowrap'),e=document.getElementById('ytapiplayer')||w;if(e){var b=e.getBoundingClientRect(),d=window.devicePixelRatio||1;r=[b.left*d,b.top*d,b.width*d,b.height*d];}var v=w&&w.querySelector('video');if(v&&!v.paused&&v.currentTime!==last)still=0;else still+=0.5;last=v?v.currentTime:-1;if(window.__watchPartyOwn&&v){if(!v.paused)v.pause();v.muted=true;}var failed=!!((v&&v.error)||(w&&w.querySelector('.vjs-error'))||(!room.paused&&still>=6));g(JSON.stringify({url:location.href,type:P?String(P.mediaType||''):'',id:P?String(P.mediaId||''):'',length:P?(Number(P.mediaLength)||0):0,time:room.time+(room.paused?0:(Date.now()-room.at)/1000),paused:room.paused,known:room.known,failed:failed,rect:r}));},500);})();"
const MEDIA := preload("res://mods/watch_party/media_player.gd")
## CyTube media the mod can play: custom media (its id is the address of a JSON manifest of
## sources and sound tracks), a raw file, an HLS stream (id: the address).
const STREAM_TYPES := ["cm", "fi", "hl"]
## The highest picture taken from a manifest, and how far from the room it may drift (seconds).
const STREAM_QUALITY := 1080
const STREAM_DRIFT := 4.0
const STREAM_RESYNC_WAIT := 10.0

var engine: Node
## The set's speaker: each tab's own speaker is its child and copies its volume.
var speaker: AudioStreamPlayer3D
var size := Vector2i(1600, 900)
## The settings (watch_settings.gd): home page, zoom, and the folder files are picked from.
var settings: RefCounted
## Chromium's pixels as a share of the page's on the screen (watch_settings.gd browser_scale, set
## by tv_set.gd): it draws a smaller page, shown stretched over the page area (the toolbar stays
## sharp), and its zoom is scaled to match, so a page lays out as at full size, only softer.
## Pointer points and the stream's place go through _to_cef / _from_cef.
var page_scale := 1.0
## Pauses every video and sound on a page (a tab left, when the settings say so).
const PAUSE_JS := "document.querySelectorAll('video,audio').forEach(function(m){try{m.pause();}catch(e){}});"
## The active tab's browser (null when closed).
var browser: Object
var history: Array = []
var page_text := ""
var opened_at := 0.0
## A file dialog is open for the page (TV mode keeps going while the mouse is free for it).
var picking := false
## Tabs: {browser, rect (the TextureRect gdCEF paints), speaker, title, url, zoom (percent), focus}.
var _tabs: Array[Dictionary] = []
var _active := -1
var _screen: SubViewport
var _page: TextureRect
var _address: LineEdit
var _tab_bar: TabBar
var _back_button: Button
var _forward_button: Button
var _zoom_button: Button
var _title := ""
var _url := ""
var _text_wait := 2.0
var _watch := 0.0
var _pointer := Vector2.ZERO
## The page's text box has the focus (FOCUS_JS); the address bar's focus is the viewport's own.
var _page_typing := false
## The focus is in a frame inside the page (a video player, an embed: FOCUS_JS says 2): it may be a
## text field there or not. T stays a letter (wants_text); Home still zooms (typing_text).
var _page_frame := false
## Where the last press went ("bar" or "page"), so its release goes there too.
var _pressed_on := ""
var _dialog: FileDialog
## Save as: its dialog, [address, user agent] waiting for a place, and where a page's blob goes.
var _save_dialog: FileDialog
var _save_pending: Array = []
var _blob_target := ""
## The left button is held down on the toolbar (a tab being dragged), and the pointer before.
var _bar_held := false
## The CyTube stream played by the mod: its key (type:id), player, speaker, picture, clip, the
## room's clock ([room seconds, ticks seconds then, paused]), when it last jumped into step.
var _stream_key := ""
var _stream: Node
var _stream_speaker: AudioStreamPlayer3D
var _stream_view: TextureRect
var _stream_clip: Control
var _room_clock: Array = [0.0, 0.0, true]
var _stream_synced := 0.0
var _pointer_before := Vector2.ZERO
var _mouse_before := Input.MOUSE_MODE_CAPTURED
## The right-click menu, what was under the pointer ({link, image, video, text, edit}) and where.
var _menu: PopupMenu
var _menu_info: Dictionary = {}
var _menu_at := Vector2.ZERO
## The tabs as last kept in the settings ([addresses], active).
var _kept: Array = []
var _bar: Control
## The page is full screen: no toolbar, the page has the whole screen.
var _full := false
## The YouTube video on the active tab (YT_JS): {id, title, channel, time, length, playing, ad,
## captions}, empty off a video. Its caption lines: [[video seconds, text], ...].
var tube: Dictionary = {}
var _tube_lines: Array = []
var _tube_changed := -1e9
var _tube_up := false
## Scrolling by the pointer: on, from where (screen pixels), page pixels not sent yet, its mark.
var _autoscroll := false
var _scroll_from := Vector2.ZERO
var _scroll_carry := Vector2.ZERO
var _scroll_mark: Label
var _middle_at := Vector2.ZERO
static var _ad_list_path := ""

## Opens the tabs open last time (or the home page), and `url` in a tab of its own when given;
## false with engine.note saying why.
func open(url: String) -> bool:
	if not is_instance_valid(engine) or not bool(engine.call("ready")): return false
	_build_screen()
	# Settings → Watch Party "Reopen tabs": off, the browser starts on one page (each tab is a live page).
	var saved: Array = settings.browser_tabs.duplicate() if settings != null and bool(settings.browser_restore) else []
	for address: Variant in saved:
		if not new_tab(str(address), false): return false
	if not url.is_empty() or _tabs.is_empty():
		if not new_tab(url): return false
	elif settings != null:
		switch_tab(clampi(int(settings.browser_tab), 0, _tabs.size() - 1))
	opened_at = Time.get_ticks_msec() / 1000.0
	history.clear()
	# Deferred: the set only takes a picture once it has marked itself as showing the web.
	painted.emit.call_deferred(_screen.get_texture())
	return true

func close() -> void:
	if is_instance_valid(_menu): _menu.hide()
	_stop_stream()
	for tab: Dictionary in _tabs: _close_browser(tab)
	_tabs.clear()
	_active = -1
	browser = null
	if is_instance_valid(_dialog) and _dialog.visible: _dialog.hide()
	_end_picking()

func _exit_tree() -> void:
	close()

func alive() -> bool:
	return browser != null and is_instance_valid(browser)

## Seconds since it opened (the position ponies' spans follow).
func position() -> float:
	return Time.get_ticks_msec() / 1000.0 - opened_at

func title() -> String:
	return _title

func url() -> String:
	return _url

## What the set shows: the toolbar over the page.
func texture() -> Texture2D:
	return _screen.get_texture() if is_instance_valid(_screen) else null

## The page alone as it looks now (for a pony's picture).
func image() -> Image:
	var shown: Texture2D = browser.call("get_texture") as Texture2D if alive() else null
	return shown.get_image() if shown != null else null

## The page's mean colour from a few sample points (the set's light follows it).
func average() -> Color:
	if not alive() or not browser.has_method("get_pixel_color"): return Color(0.8, 0.8, 0.8)
	var page_size := _cef_size()
	var total := Color(0, 0, 0)
	for y in 4:
		for x in 6:
			total += browser.call("get_pixel_color", int((x + 0.5) * page_size.x / 6.0), int((y + 0.5) * page_size.y / 4.0)) as Color
	return total / 24.0

func _page_size() -> Vector2i:
	return Vector2i(size.x, size.y - _top())

## The page Chromium draws (page_scale of what it fills on the screen).
func _cef_size() -> Vector2i:
	return Vector2i((Vector2(_page_size()) * page_scale).round())

## The pointer over the page, in Chromium's pixels.
func _to_cef() -> Vector2i:
	return Vector2i((Vector2(_pointer.x, _pointer.y - _top()) * page_scale).round())

## Where the page starts on the screen: below the toolbar, or at the top when full screen.
func _top() -> int:
	return 0 if _full else BAR

# --- tabs ---------------------------------------------------------------------------------------

## A new tab at `url` (the home page when empty), made the active one unless `show` is false (the
## first one always is). With TABS_MAX open it opens in the active tab instead (shown) or not at all.
func new_tab(url := "", show := true) -> bool:
	if _tabs.size() >= TABS_MAX:
		if show: go(url if not url.is_empty() else _home())
		else: notice.emit("%d tabs are open already" % TABS_MAX)
		return true
	if _full: _full_screen(false)
	var cef: Node = engine.get("cef")
	var rect := TextureRect.new(); rect.name = "TabPage"
	rect.visible = false
	rect.size = Vector2(_cef_size())
	add_child(rect)
	# gdCEF's own downloads never finish here (header): the mod saves files itself.
	var config := {"frame_rate": int(settings.browser_fps) if settings != null else FRAME_RATE, "javascript": true, "user_gesture_required": false, "webgl": true,
		"allow_downloads": false, "download_folder": OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)}
	var address := _address_for(url) if not url.is_empty() else _home()
	var made: Object = cef.call("create_browser", address, rect, config)
	if made == null:
		engine.set("note", "Chromium could not open a page: " + str(cef.call("get_error")))
		rect.queue_free()
		return false
	made.call("resize", Vector2(_cef_size()))
	var tab := {"browser": made, "rect": rect, "speaker": _tab_speaker(made), "title": "", "url": address, "zoom": _zoom_setting(), "focus": false}
	for pair: Array in [["on_browser_paint", _on_paint], ["on_page_loaded", _on_loaded], ["on_page_start_loading", _on_start],
			["on_page_failed_loading", _on_failed], ["on_html_content_requested", _on_html]]:
		if made.has_signal(pair[0]): made.connect(pair[0], pair[1])
	for method: String in ["_text_focus", "_open_tab", "_open_background", "_file_wanted", "_context_menu", "_full_screen", "_youtube", "_download", "_save_data", "_middle_free", "_room"]:
		if made.has_method("register_method"): made.call("register_method", self, method)
	var ads := _ad_list()
	if not ads.is_empty() and made.has_method("load_ad_block_filter_list"): made.call("load_ad_block_filter_list", ads)
	_tabs.append(tab)
	_tab_bar.add_tab("New tab")
	_tab_bar.set_tab_metadata(_tab_bar.tab_count - 1, made.get_instance_id())
	_fit_tabs.call_deferred()
	print("[watch_party] browser: opened ", address)
	if show or _active < 0: switch_tab(_tabs.size() - 1)
	return true

func switch_tab(index: int) -> void:
	if index < 0 or index >= _tabs.size(): return
	if _full: _full_screen(false)
	end_autoscroll()
	if index != _active:
		_forget_tube()
		_stop_stream()
		# The tab left behind keeps running (gdCEF cannot hide a page); its videos and sounds stop.
		if settings != null and bool(settings.browser_pause_hidden) and _active >= 0 and _active < _tabs.size():
			var left: Object = _tabs[_active].browser
			if left != null and is_instance_valid(left) and left.has_method("execute_javascript"): left.call("execute_javascript", PAUSE_JS)
	_active = index
	browser = _tabs[index].browser
	_page_typing = int(_tabs[index].focus) != 0
	_page_frame = int(_tabs[index].focus) == 2
	if _tab_bar.current_tab != index: _tab_bar.current_tab = index
	_tab_bar.ensure_tab_visible(index)
	_title = str(_tabs[index].title); _url = str(_tabs[index].url)
	_page.texture = browser.call("get_texture") as Texture2D
	_show_address()
	_show_zoom()
	_watch = 0.0
	typing.emit(_page_typing)

## Closes tab `index`; the last one goes back to the home page instead.
func close_tab(index: int) -> void:
	_tabs_moved()
	if index < 0 or index >= _tabs.size(): return
	if _tabs.size() == 1:
		go(_home())
		return
	_close_browser(_tabs[index])
	_tabs.remove_at(index)
	_tab_bar.remove_tab(index)
	_fit_tabs.call_deferred()
	var next := _active
	if index < _active: next -= 1
	switch_tab(clampi(next, 0, _tabs.size() - 1))

func _close_browser(tab: Dictionary) -> void:
	var view: Object = tab.browser
	if view != null and is_instance_valid(view):
		if view.has_method("set_audio_stream"): view.call("set_audio_stream", null)
		if view.has_method("close"): view.call("close")
	for key: String in ["rect", "speaker"]:
		var node: Variant = tab.get(key)
		if is_instance_valid(node): (node as Node).queue_free()

func _tab_of(view: Object) -> int:
	for i in _tabs.size():
		if _tabs[i].browser == view: return i
	return -1

## Its own speaker beside the set's, which the page's sound is pushed into.
func _tab_speaker(view: Object) -> AudioStreamPlayer3D:
	if not is_instance_valid(speaker) or not view.has_method("set_audio_stream"): return null
	var player := AudioStreamPlayer3D.new(); player.name = "TabSound"
	player.bus = speaker.bus
	player.unit_size = speaker.unit_size
	player.max_distance = speaker.max_distance
	player.volume_db = speaker.volume_db
	var generator := AudioStreamGenerator.new()
	generator.buffer_length = 0.5
	player.stream = generator
	speaker.add_child(player)
	player.play()
	view.call("set_audio_stream", player.get_stream_playback())
	return player

# --- the screen and its toolbar -----------------------------------------------------------------

func _build_screen() -> void:
	if is_instance_valid(_screen): return
	_screen = SubViewport.new(); _screen.name = "WebScreen"
	_screen.size = size
	_screen.disable_3d = true
	_screen.transparent_bg = false
	_screen.gui_embed_subwindows = true
	_screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_screen)
	var root := Control.new(); root.name = "Screen"
	root.size = Vector2(size)
	root.theme = STYLE.theme()
	_screen.add_child(root)
	var backdrop := ColorRect.new(); backdrop.color = Color.WHITE
	backdrop.size = Vector2(size); backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	_page = TextureRect.new(); _page.name = "Page"
	_page.position = Vector2(0, BAR); _page.size = Vector2(_page_size())
	_page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page.stretch_mode = TextureRect.STRETCH_SCALE
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_page)
	# A CyTube stream the mod plays sits over the page's own video, clipped to the page.
	_stream_clip = Control.new(); _stream_clip.name = "StreamClip"
	_stream_clip.clip_contents = true
	_stream_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stream_clip.position = _page.position; _stream_clip.size = _page.size
	root.add_child(_stream_clip)
	_stream_view = TextureRect.new(); _stream_view.name = "Stream"
	_stream_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stream_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_stream_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stream_view.visible = false
	_stream_clip.add_child(_stream_view)
	var bar := PanelContainer.new(); bar.name = "Toolbar"
	bar.position = Vector2.ZERO; bar.size = Vector2(size.x, BAR)
	var look := StyleBoxFlat.new(); look.bg_color = STYLE.INK
	look.content_margin_left = 8; look.content_margin_right = 8; look.content_margin_top = 6; look.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", look)
	root.add_child(bar)
	_bar = bar
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	_back_button = _bar_button(row, "←", back, "Back (Alt+Left)")
	_forward_button = _bar_button(row, "→", forward, "Forward (Alt+Right)")
	_bar_button(row, "↻", reload, "Reload (F5)")
	_address = LineEdit.new(); _address.name = "Address"
	_address.custom_minimum_size = Vector2(ADDRESS_REST, 0)
	_address.select_all_on_focus = true
	_address.placeholder_text = "Address or words to search for"
	_address.context_menu_enabled = false
	_address.add_theme_font_size_override("font_size", BAR_FONT)
	_address.text_submitted.connect(_address_entered)
	_address.focus_entered.connect(_address_taken)
	_address.focus_exited.connect(_address_left)
	row.add_child(_address)
	_tab_bar = TabBar.new(); _tab_bar.name = "Tabs"
	_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.resized.connect(_fit_tabs)
	_tab_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tab_bar.clip_tabs = true
	_tab_bar.max_tab_width = TAB_WIDEST
	_tab_bar.focus_mode = Control.FOCUS_NONE
	_tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	_tab_bar.add_theme_font_size_override("font_size", BAR_FONT - 3)
	_tab_bar.tab_clicked.connect(_tab_clicked)
	# Tabs can be dragged into another order; each knows its browser by metadata.
	_tab_bar.drag_to_rearrange_enabled = true
	_tab_bar.active_tab_rearranged.connect(_tabs_moved)
	_tab_bar.tab_close_pressed.connect(close_tab)
	row.add_child(_tab_bar)
	_bar_button(row, "+", _new_tab_pressed, "New tab (Ctrl+T)")
	_zoom_button = _bar_button(row, "100%", reset_zoom, "Zoom: Ctrl + wheel, Ctrl +/-. Click: back to %d%%" % _zoom_setting())

func _bar_button(row: Container, text: String, pressed: Callable, tip: String) -> Button:
	var button := Button.new(); button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(46, 0)
	button.add_theme_font_size_override("font_size", BAR_FONT)
	button.pressed.connect(pressed)
	row.add_child(button)
	return button

func _new_tab_pressed() -> void:
	if new_tab(): _address.grab_focus()

func _show_address() -> void:
	if not is_instance_valid(_address) or _address.has_focus(): return
	_address.text = _url

## Something on the page (a text box) or the address bar or a menu has the keys: the zoom key
## (screen_zoom.gd) types there instead.
## A text field for certain (not just a frame that has the focus): Home is a key there, not the zoom.
func typing_text() -> bool:
	return (_page_typing and not _page_frame) or (is_instance_valid(_address) and _address.has_focus()) or _menu_open()

func wants_text() -> bool:
	return _page_typing or (is_instance_valid(_address) and _address.has_focus()) or _menu_open()

func _address_taken() -> void:
	_address.custom_minimum_size.x = ADDRESS_TYPING
	typing.emit(true)

func _address_entered(text: String) -> void:
	_screen.gui_release_focus()
	go(text)

func _address_left() -> void:
	_address.custom_minimum_size.x = ADDRESS_REST
	_show_address()
	typing.emit(_page_typing)

## A tab clicked: its order first follows any drag that just ended.
func _tab_clicked(index: int) -> void:
	_tabs_moved()
	switch_tab(index)

## Tabs dragged into another order (the tab bar's own drag): the tab list follows it.
func _tabs_moved(_to: int = -1) -> void:
	if not is_instance_valid(_tab_bar) or _tab_bar.tab_count != _tabs.size(): return
	var order: Array[Dictionary] = []
	for i in _tab_bar.tab_count:
		var id: Variant = _tab_bar.get_tab_metadata(i)
		for tab: Dictionary in _tabs:
			var view: Object = tab.browser
			if view != null and is_instance_valid(view) and view.get_instance_id() == id:
				order.append(tab)
				break
	if order.size() != _tabs.size(): return
	var same := true
	for i in order.size():
		if order[i].browser != _tabs[i].browser: same = false
	if same: return
	_tabs = order
	_active = _tab_of(browser)

## Tabs share the tab bar's room: as wide as TAB_WIDEST while they fit, narrower as more open, down
## to a TABS_SHOWN-th of it; beyond that the bar scrolls.
func _fit_tabs() -> void:
	if not is_instance_valid(_tab_bar) or _tab_bar.tab_count == 0: return
	var room := _tab_bar.size.x
	_tab_bar.max_tab_width = int(clampf(room / _tab_bar.tab_count, room / TABS_SHOWN, TAB_WIDEST))
	if _active >= 0 and _active < _tab_bar.tab_count: _tab_bar.ensure_tab_visible(_active)

## The toolbar's buttons and the tab titles follow the pages.
func _refresh_bar() -> void:
	if not alive(): return
	_tabs_moved()
	_back_button.disabled = not bool(browser.call("has_previous_page"))
	_forward_button.disabled = not bool(browser.call("has_next_page"))
	for i in _tabs.size():
		var view: Object = _tabs[i].browser
		if view == null or not is_instance_valid(view): continue
		var page_title := str(view.call("get_title"))
		_tabs[i].title = page_title
		_tabs[i].url = str(view.call("get_url"))
		var shown := page_title if not page_title.is_empty() else "New tab"
		if _tab_bar.get_tab_title(i) != shown: _tab_bar.set_tab_title(i, shown)

# --- zoom ---------------------------------------------------------------------------------------

func _zoom_setting() -> int:
	return int(settings.browser_zoom) if settings != null else 125

## Zooms the active page `steps` steps in (positive) or out; the new zoom becomes the setting.
func zoom(steps: int) -> void:
	if not alive(): return
	var now := int(_tabs[_active].zoom)
	var at := 0
	for i in ZOOMS.size():
		if absi(int(ZOOMS[i]) - now) < absi(int(ZOOMS[at]) - now): at = i
	var percent := int(ZOOMS[clampi(at + steps, 0, ZOOMS.size() - 1)])
	if settings != null:
		settings.browser_zoom = percent
		settings.save()
	_set_zoom(percent)

## Back to the setting's zoom.
func reset_zoom() -> void:
	if alive(): _set_zoom(_zoom_setting())

func _set_zoom(percent: int) -> void:
	_tabs[_active].zoom = percent
	_apply_zoom(browser, percent * page_scale)
	_show_zoom()

## Chromium's zoom level: 1.2 to the power of the level is the scale.
static func _apply_zoom(view: Object, percent: float) -> void:
	if view != null and is_instance_valid(view) and view.has_method("set_zoom_level"):
		view.call("set_zoom_level", log(percent / 100.0) / log(1.2))

func _show_zoom() -> void:
	if is_instance_valid(_zoom_button) and _active >= 0: _zoom_button.text = "%d%%" % int(_tabs[_active].zoom)

# --- input (screen_input.gd) ------------------------------------------------------------------

## The pointer at `uv` on the screen (0..1, top left 0,0).
func move(uv: Vector2) -> void:
	if not is_instance_valid(_screen): return
	_pointer = Vector2(clampf(uv.x, 0.0, 1.0) * size.x, clampf(uv.y, 0.0, 1.0) * size.y)
	var motion := InputEventMouseMotion.new()
	motion.position = _pointer; motion.global_position = _pointer
	motion.relative = _pointer - _pointer_before
	_pointer_before = _pointer
	# Held on the toolbar: a drag (Godot starts dragging a tab only with the button in the mask).
	if _bar_held: motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_screen.push_input(motion, true)
	if alive() and _pointer.y >= _top(): browser.call("set_mouse_moved", _to_cef().x, _to_cef().y)

## Only the left button reaches Chromium: a right click would ask it for a menu it cannot draw
## here (a playtest crash came seconds after some), so the mod's own menu opens instead, and a
## middle click on a link opens it in a tab of its own (LINK_JS).
func button(index: int, pressed: bool) -> void:
	if not is_instance_valid(_screen): return
	# A click off the right-click menu closes it and goes no further (Godot leaves an embedded menu
	# open when the click is pushed in from outside).
	if pressed and _menu_open() and not Rect2(Vector2(_menu.position), Vector2(_menu.size)).has_point(_pointer):
		_menu.hide()
		_pressed_on = "none"
		return
	# Any click ends scrolling by the pointer, and does nothing else.
	if pressed and _autoscroll:
		end_autoscroll()
		_pressed_on = "none"
		return
	var on_page := _pointer.y >= _top() and not _menu_open()
	if index == MOUSE_BUTTON_RIGHT:
		if pressed and on_page and alive():
			_menu_at = _pointer
			browser.call("execute_javascript", CONTEXT_JS % [_to_cef().x, _to_cef().y])
		return
	if index == MOUSE_BUTTON_XBUTTON1 or index == MOUSE_BUTTON_XBUTTON2:
		# The mouse's side buttons: back and forward.
		if pressed: (back if index == MOUSE_BUTTON_XBUTTON1 else forward).call()
		return
	if index == MOUSE_BUTTON_MIDDLE:
		if pressed and on_page and alive():
			_middle_at = _pointer
			browser.call("execute_javascript", LINK_JS % [_to_cef().x, _to_cef().y])
		return
	if index != MOUSE_BUTTON_LEFT: return
	if not pressed and _pressed_on == "none": return
	if pressed:
		_pressed_on = "page" if on_page else "bar"
	if _pressed_on == "bar":
		_bar_held = pressed
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT; click.pressed = pressed
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		click.position = _pointer; click.global_position = _pointer
		_screen.push_input(click, true)
		return
	if pressed and _screen.gui_get_focus_owner() != null: _screen.gui_release_focus()
	if alive(): browser.call("set_mouse_left_%s" % ("down" if pressed else "up"))

## Wheel notches: positive scrolls up (the page moves down); with Ctrl it zooms.
func wheel(notches: float, shift := false, ctrl := false) -> void:
	if not alive() or is_zero_approx(notches): return
	if _menu_open():
		_menu.hide()
		return
	end_autoscroll()
	if ctrl:
		zoom(1 if notches > 0.0 else -1)
		return
	if _pointer.y < _top():
		# Over the toolbar: the tab bar scrolls when its tabs do not all fit.
		for down: bool in [true, false]:
			var turn := InputEventMouseButton.new()
			turn.button_index = MOUSE_BUTTON_WHEEL_UP if notches > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
			turn.pressed = down
			turn.position = _pointer; turn.global_position = _pointer
			_screen.push_input(turn, true)
		return
	scroll(notches, shift)

## The page scrolls `notches` (the remote's wheel, wherever the pointer was left).
func scroll(notches: float, sideways := false) -> void:
	if not alive(): return
	if sideways: browser.call("set_mouse_wheel_horizontal", roundi(notches * WHEEL_NOTCH), false, false, false)
	else: browser.call("set_mouse_wheel_vertical", roundi(notches * WHEEL_NOTCH), false, false, false)

## A key from the keyboard: the browser's own shortcuts, then the address bar while it has the
## focus, else the page.
func key(event: InputEventKey) -> void:
	if not alive(): return
	if _menu_open():
		_screen.push_input(event, true)
		return
	if event.pressed and _shortcut(event): return
	if is_instance_valid(_address) and _address.has_focus():
		_screen.push_input(event, true)
		return
	_page_key(event.unicode if event.unicode != 0 else int(event.keycode), event.pressed, event.shift_pressed, event.alt_pressed, event.is_command_or_control_pressed())

## A key from the VR keyboard: a character (one letter) or a Godot keycode (Enter, Backspace…).
func tap(character: String, keycode := KEY_NONE) -> void:
	if not alive(): return
	var code := character.unicode_at(0) if not character.is_empty() else int(keycode)
	if is_instance_valid(_address) and _address.has_focus():
		for down: bool in [true, false]:
			var event := InputEventKey.new()
			event.pressed = down
			event.keycode = keycode if character.is_empty() else KEY_NONE
			event.unicode = code if not character.is_empty() else 0
			_screen.push_input(event, true)
		return
	_page_key(code, true, false, false, false)
	_page_key(code, false, false, false, false)

func _page_key(code: int, pressed: bool, shift: bool, alt: bool, ctrl: bool) -> void:
	# A character that is also another key's code goes in through the page instead (CLASHING).
	if code > 32 and code < 127 and char(code) in CLASHING and not ctrl and not alt:
		if pressed: browser.call("execute_javascript", INSERT_JS % JSON.stringify(char(code)))
		return
	browser.call("set_key_pressed", code, pressed, shift, alt, ctrl)

## Ctrl+L the address, Ctrl+T/W a tab, Ctrl+Tab the next, Alt+Left/Right back/forward, F5
## reload, Ctrl +/-/0 zoom. True when it was one.
func _shortcut(event: InputEventKey) -> bool:
	var ctrl := event.is_command_or_control_pressed()
	match event.keycode:
		KEY_L when ctrl: _address.grab_focus()
		KEY_T when ctrl: _new_tab_pressed()
		KEY_W when ctrl: close_tab(_active)
		KEY_TAB when ctrl: switch_tab((_active + (-1 if event.shift_pressed else 1) + _tabs.size()) % _tabs.size())
		KEY_LEFT when event.alt_pressed: back()
		KEY_RIGHT when event.alt_pressed: forward()
		KEY_F5: reload()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD when ctrl: zoom(1)
		KEY_MINUS, KEY_KP_SUBTRACT when ctrl: zoom(-1)
		KEY_0, KEY_KP_0 when ctrl: reset_zoom()
		_: return false
	return true

func back() -> void:
	if alive() and bool(browser.call("has_previous_page")): browser.call("previous_page")

func forward() -> void:
	if alive() and bool(browser.call("has_next_page")): browser.call("next_page")

func reload() -> void:
	if alive(): browser.call("reload")

func go(address: String) -> void:
	if not alive(): return
	var typed := _address_for(address)
	if typed.is_empty(): return
	browser.call("load_url", typed)
	_url = typed
	_show_address()

func _home() -> String:
	var home := str(settings.browser_home) if settings != null else ""
	return _address_for(home) if not home.strip_edges().is_empty() else HOME

## What was typed as an address: a web address as it is, a bare name with a dot as https, else a
## search.
static func _address_for(typed_in: String) -> String:
	var typed := typed_in.strip_edges()
	if typed.is_empty(): return ""
	if "://" in typed or typed.begins_with("about:"): return typed
	return ("https://" + typed) if "." in typed and not " " in typed else "https://duckduckgo.com/?q=" + typed.uri_encode()

func set_muted(muted: bool) -> void:
	for tab: Dictionary in _tabs:
		var view: Object = tab.browser
		if view != null and is_instance_valid(view) and view.has_method("set_muted"): view.call("set_muted", muted)

# --- the page -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	for tab: Dictionary in _tabs:
		var player: Variant = tab.get("speaker")
		if not is_instance_valid(player): continue
		if is_instance_valid(speaker): (player as AudioStreamPlayer3D).volume_db = speaker.volume_db
	if is_instance_valid(_stream_speaker) and is_instance_valid(speaker): _stream_speaker.volume_db = speaker.volume_db
	if not alive(): return
	if _autoscroll: _scroll_by_pointer(delta)
	_watch -= delta
	if _watch <= 0.0:
		_watch = WATCH_EVERY
		_refresh_bar()
		_keep_tabs()
		var now_title := str(browser.call("get_title"))
		var now_url := str(browser.call("get_url"))
		if now_url != _url or now_title != _title or history.is_empty():
			var new_page := now_url != _url
			_url = now_url; _title = now_title
			_show_address()
			if new_page: _tell_no_play(_url)
			if new_page or history.is_empty(): history.append([position(), _page_line()])
			else: history[history.size() - 1] = [float(history[-1][0]), _page_line()]
			while history.size() > 200: history.pop_front()
	_text_wait -= delta
	if _text_wait <= 0.0:
		_text_wait = TEXT_EVERY
		if browser.has_method("request_html_content"): browser.call("request_html_content")

func _tell_no_play(address: String) -> void:
	var bare := address.get_slice("://", 1).trim_prefix("www.")
	for site: String in NO_PLAY:
		if bare.begins_with(site) or bare.get_slice("/", 0).ends_with("." + site.get_slice("/", 0)) and not "/" in site:
			notice.emit("This site's videos cannot play here: the game's browser has no DRM for paid streaming services." if NO_PLAY[site] == "DRM"
				else "This site's streams cannot play here: the game's browser has no H.264 video.")
			return

func _page_line() -> String:
	var host := _url.get_slice("://", 1).get_slice("/", 0).trim_prefix("www.")
	return "%s (%s)" % [_title if not _title.is_empty() else "a page", host] if not host.is_empty() else _title

func _on_paint(view: Variant = null) -> void:
	if view != browser or not is_instance_valid(_page) or not alive(): return
	var shown := browser.call("get_texture") as Texture2D
	if shown != _page.texture: _page.texture = shown
	# The set shows the screen's texture; it skips this unless it is not showing it yet.
	painted.emit(_screen.get_texture())

func _on_start(view: Variant = null) -> void:
	if view is Object and is_instance_valid(view):
		(view as Object).call("execute_javascript", GUARD_JS)
		(view as Object).call("execute_javascript", FULL_JS)

func _on_loaded(_code: Variant = 0, view: Variant = null) -> void:
	if not view is Object or not is_instance_valid(view): return
	(view as Object).call("execute_javascript", GUARD_JS)
	(view as Object).call("execute_javascript", FULL_JS)
	(view as Object).call("execute_javascript", FOCUS_JS)
	var host := str((view as Object).call("get_url")).get_slice("://", 1).get_slice("/", 0)
	if host == "youtube.com" or host.ends_with(".youtube.com"): (view as Object).call("execute_javascript", YT_JS)
	if host == "cytu.be" or host.ends_with(".cytu.be"): (view as Object).call("execute_javascript", ROOM_JS)
	var index := _tab_of(view)
	if index >= 0:
		_tabs[index].focus = false
		_apply_zoom(view, int(_tabs[index].zoom) * page_scale)
	if view == browser:
		_text_wait = 3.0
		_page_typing = false
		_page_frame = false
		typing.emit(false)

func _on_failed(code: Variant = 0, message: Variant = "", _view: Variant = null) -> void:
	print("[watch_party] browser: page failed (%s) %s" % [str(code), str(message)])

func _on_html(html: Variant = "", view: Variant = null) -> void:
	if view != browser: return
	page_text = visible_text(str(html)).left(TEXT_KEEP)

func _text_focus(on: Variant = false) -> void:
	# Which tab asked is not passed; only the active one takes input.
	var kind := int(on) if (on is int or on is float) else (1 if bool(on) else 0)
	_page_typing = kind != 0
	_page_frame = kind == 2
	if _active >= 0: _tabs[_active].focus = kind
	typing.emit(_page_typing)

## A new window (GUARD_JS): a tab of its own.
func _open_tab(address: Variant = "") -> void:
	var text := str(address)
	if text.begins_with("http") or text.begins_with("about:"): new_tab.call_deferred(text)

## A middle-clicked link (LINK_JS): a tab of its own behind this one.
func _open_background(address: Variant = "") -> void:
	var text := str(address)
	if text.begins_with("http"): new_tab.call_deferred(text, false)

## The open tabs' addresses into the settings when they change (they come back next time).
func _keep_tabs() -> void:
	if settings == null: return
	var addresses: Array = []
	for tab: Dictionary in _tabs:
		var address := str(tab.url)
		if address.begins_with("http"): addresses.append(address)
	var now := [addresses, _active]
	if now == _kept: return
	_kept = now
	settings.browser_tabs = addresses
	settings.browser_tab = _active
	settings.save()

# --- full screen, sound, ads --------------------------------------------------------------------

## The toolbar's Full button: the biggest video on the page fills the screen, or back again.
func toggle_full() -> void:
	if alive(): browser.call("execute_javascript", TOGGLE_FULL_JS)

## Out of full screen (Esc in TV mode, screen_input.gd); false when the page was not full screen.
func leave_full() -> bool:
	if not _full: return false
	if alive(): browser.call("execute_javascript", LEAVE_FULL_JS)
	_full_screen(false)
	return true

## The page went full screen (a video) or left it: the toolbar goes, the page takes the screen.
func _full_screen(on: Variant = false) -> void:
	var full := bool(on)
	if full == _full or not is_instance_valid(_page): return
	_full = full
	if is_instance_valid(_bar): _bar.visible = not full
	_page.position = Vector2(0, _top())
	_page.size = Vector2(_page_size())
	if alive():
		browser.call("resize", Vector2(_cef_size()))
		var rect: Variant = _tabs[_active].get("rect")
		if is_instance_valid(rect): (rect as Control).size = Vector2(_cef_size())
	if full and is_instance_valid(_address) and _address.has_focus(): _screen.gui_release_focus()

## A middle click off a link (LINK_JS): the page scrolls as the pointer moves away from there.
func _middle_free() -> void:
	if not alive() or _middle_at.y < _top(): return
	_autoscroll = true
	_scroll_from = _middle_at
	_scroll_carry = Vector2.ZERO
	if not is_instance_valid(_scroll_mark):
		_scroll_mark = Label.new(); _scroll_mark.name = "ScrollMark"
		_scroll_mark.text = "↕"
		_scroll_mark.add_theme_font_size_override("font_size", 40)
		_scroll_mark.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
		_scroll_mark.add_theme_color_override("font_outline_color", Color.WHITE)
		_scroll_mark.add_theme_constant_override("outline_size", 8)
		_scroll_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.get_parent().add_child(_scroll_mark)
	_scroll_mark.reset_size()
	_scroll_mark.position = _scroll_from - _scroll_mark.size / 2.0
	_scroll_mark.visible = true

## Ends scrolling by the pointer (a click, the wheel, another tab, TV mode left).
func end_autoscroll() -> void:
	_autoscroll = false
	if is_instance_valid(_scroll_mark): _scroll_mark.visible = false

func _scroll_by_pointer(delta: float) -> void:
	var away := _pointer - _scroll_from
	for axis in 2:
		var beyond := maxf(0.0, absf(away[axis]) - SCROLL_STILL)
		_scroll_carry[axis] += signf(away[axis]) * beyond * (1.0 + beyond / SCROLL_RAMP) * SCROLL_SPEED * delta
	# gdCEF scrolls ten page pixels a unit; down and right are negative units.
	var units := Vector2i(int(_scroll_carry.x / 10.0), int(_scroll_carry.y / 10.0))
	if units.y != 0: browser.call("set_mouse_wheel_vertical", -units.y, false, false, false)
	if units.x != 0: browser.call("set_mouse_wheel_horizontal", -units.x, false, false, false)
	_scroll_carry -= Vector2(units) * 10.0

## The ad server list as a file gdCEF can open (it reads the disk, not the mod's pack): copied to
## the mod's data folder once a session. "" when it cannot be.
static func _ad_list() -> String:
	if not _ad_list_path.is_empty(): return _ad_list_path
	var text := FileAccess.get_file_as_string(AD_LIST)
	if text.is_empty(): return ""
	var copy := Mods.data_folder("watch_party").path_join("easylist_domains.txt")
	var file := FileAccess.open(copy, FileAccess.WRITE)
	if file == null: return ""
	file.store_string(text)
	file.close()
	_ad_list_path = ProjectSettings.globalize_path(copy)
	return _ad_list_path

# --- CyTube -------------------------------------------------------------------------------------

## ROOM_JS's report from the active tab: start, follow or stop the mod's own playing of the room.
func _room(json: Variant = "") -> void:
	var report: Variant = JSON.parse_string(str(json))
	if not report is Dictionary or not alive(): return
	if str(report.get("url", "")) != str(browser.call("get_url")): return
	var type := str(report.get("type", ""))
	if type not in STREAM_TYPES:
		_stop_stream()
		return
	if bool(report.get("known", false)):
		_room_clock = [float(report.get("time", 0.0)), Time.get_ticks_msec() / 1000.0, bool(report.get("paused", false))]
	_place_stream(report.get("rect"))
	var key := type + ":" + str(report.get("id", ""))
	if key == _stream_key:
		_follow_room(float(report.get("length", 0.0)))
		return
	# Something new in the room: only once the page's player failed at it (a format Chromium can
	# play stays the page's own, never twice over) and the room's clock is known.
	if not bool(report.get("failed", false)) or not bool(report.get("known", false)):
		if not _stream_key.is_empty(): _stop_stream()
		return
	_stop_stream()
	_stream_key = key
	var id := str(report.get("id", ""))
	var length := float(report.get("length", 0.0))
	if type == "cm": _fetch_manifest(id, length, key)
	else: _start_stream(id, "", length, key)

## Where the room is now (seconds into its media).
func _room_now() -> float:
	if bool(_room_clock[2]): return float(_room_clock[0])
	return float(_room_clock[0]) + Time.get_ticks_msec() / 1000.0 - float(_room_clock[1])

## Custom media: its manifest (fetched by Godot: no cross-site limits) names the sources.
func _fetch_manifest(address: String, length: float, key: String) -> void:
	if not address.begins_with("http"): return
	var request := HTTPRequest.new()
	request.use_threads = true
	add_child(request)
	request.request_completed.connect(_manifest_came.bind(request, length, key))
	if request.request(address, PackedStringArray(["User-Agent: " + AGENT])) != OK: request.queue_free()

func _manifest_came(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, length: float, key: String) -> void:
	request.queue_free()
	if key != _stream_key: return
	var manifest: Variant = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code < 400 else null
	if not manifest is Dictionary:
		print("[watch_party] browser: the room's media manifest could not be read (result %d, HTTP %d)" % [result, code])
		return
	# The best picture up to STREAM_QUALITY (else the lowest there is).
	var picture := ""
	var best := -1
	var lowest := 1 << 30
	var lowest_url := ""
	for source: Variant in manifest.get("sources", []):
		if not source is Dictionary: continue
		var quality := int((source as Dictionary).get("quality", 0))
		var address := str((source as Dictionary).get("url", ""))
		if not address.begins_with("http"): continue
		if quality <= STREAM_QUALITY and quality > best:
			best = quality
			picture = address
		if quality < lowest:
			lowest = quality
			lowest_url = address
	if picture.is_empty(): picture = lowest_url
	# Its sound track (English first), else the sound inside the picture's stream.
	var sound := ""
	for track: Variant in manifest.get("audioTracks", []):
		if not track is Dictionary: continue
		var address := str((track as Dictionary).get("url", ""))
		if not address.begins_with("http"): continue
		if sound.is_empty() or str((track as Dictionary).get("language", "")).begins_with("en"): sound = address
		if str((track as Dictionary).get("language", "")).begins_with("en"): break
	if picture.is_empty(): return
	if float(manifest.get("duration", 0.0)) > 0.0: length = float(manifest.duration)
	_start_stream(picture, sound, length, key)

## The room's media through ffmpeg, from where the room is, its picture over the page's video.
func _start_stream(picture: String, sound: String, length: float, key: String) -> void:
	if key != _stream_key or not picture.begins_with("http"): return
	var hub: Variant = engine.get("hub") if is_instance_valid(engine) else null
	var ffmpeg := str((hub as Node).get("ffmpeg")) if hub is Node else ""
	if ffmpeg.is_empty():
		notice.emit("The room's video needs ffmpeg (TV menu), which this browser cannot play itself.")
		return
	if is_instance_valid(speaker):
		_stream_speaker = AudioStreamPlayer3D.new(); _stream_speaker.name = "StreamSound"
		_stream_speaker.bus = speaker.bus
		_stream_speaker.unit_size = speaker.unit_size
		_stream_speaker.max_distance = speaker.max_distance
		_stream_speaker.volume_db = speaker.volume_db
		speaker.add_child(_stream_speaker)
	_stream = MEDIA.new(); _stream.name = "RoomStream"
	_stream.set("ffmpeg", ffmpeg)
	_stream.set("speaker", _stream_speaker)
	_stream.set("audio_source", sound)
	var shown := _stream_view.size if _stream_view.size.x > 16.0 else Vector2(1280, 720)
	_stream.set("width", clampi(int(shown.x) / 2 * 2, 320, 1920))
	_stream.set("height", clampi(int(shown.y) / 2 * 2, 180, 1080))
	add_child(_stream)
	_stream.connect("picture", _stream_picture)
	if not bool(_stream.call("play", picture, _room_now(), length, true)):
		_stop_stream()
		return
	_stream_synced = Time.get_ticks_msec() / 1000.0
	if bool(_room_clock[2]): _stream.call("pause")
	if alive(): browser.call("execute_javascript", "window.__watchPartyOwn=true;")
	print("[watch_party] browser: playing the room's media through ffmpeg (%s, sound %s)" % [picture, sound if not sound.is_empty() else "in it"])
	notice.emit("Playing the room's video through ffmpeg (Chromium here cannot)")

func _stream_picture(texture: ImageTexture) -> void:
	if not is_instance_valid(_stream_view): return
	if _stream_view.texture != texture: _stream_view.texture = texture
	_stream_view.visible = true

## Paused with the room, playing with it, and back in step when it drifted (a file, not live).
func _follow_room(length: float) -> void:
	if not is_instance_valid(_stream): return
	var state := str(_stream.get("state"))
	if bool(_room_clock[2]) and state == "playing": _stream.call("pause")
	elif not bool(_room_clock[2]) and state == "paused": _stream.call("resume")
	var now := Time.get_ticks_msec() / 1000.0
	if length <= 0.0 or state != "playing" or now - _stream_synced < STREAM_RESYNC_WAIT: return
	if absf(float(_stream.call("position")) - _room_now()) > STREAM_DRIFT:
		_stream_synced = now
		_stream.call("seek", _room_now())

## Over the page's video: `rect` in page pixels [x, y, width, height].
func _place_stream(rect: Variant) -> void:
	if not is_instance_valid(_stream_clip): return
	_stream_clip.position = Vector2(0, _top())
	_stream_clip.size = Vector2(_page_size())
	if rect is Array and (rect as Array).size() == 4:
		_stream_view.position = Vector2(float(rect[0]), float(rect[1])) / page_scale
		_stream_view.size = Vector2(float(rect[2]), float(rect[3])) / page_scale

func _stop_stream() -> void:
	_stream_key = ""
	if is_instance_valid(_stream):
		if alive(): browser.call("execute_javascript", "window.__watchPartyOwn=false;")
		_stream.call("stop")
		_stream.queue_free()
	_stream = null
	if is_instance_valid(_stream_speaker): _stream_speaker.queue_free()
	_stream_speaker = null
	if is_instance_valid(_stream_view):
		_stream_view.visible = false
		_stream_view.texture = null

# --- YouTube ------------------------------------------------------------------------------------

## YT_JS's report from the active tab: the video, and its caption lines kept with their times.
## Lines grow word by word (automatic captions): a line that extends a recent one replaces it.
func _youtube(json: Variant = "") -> void:
	var report: Variant = JSON.parse_string(str(json))
	if not report is Dictionary or not alive(): return
	# Any tab may report; only the one showing counts.
	if str(report.get("url", "")) != str(browser.call("get_url")): return
	if not bool(report.get("video", false)):
		_forget_tube()
		return
	var id := str(report.get("id", ""))
	if id != str(tube.get("id", "")): _forget_tube()
	var ad := bool(report.get("ad", false))
	var at := float(tube.get("time", 0.0)) if ad else float(report.get("time", 0.0))
	var state := int(report.get("state", -1))
	tube = {"id": id, "title": str(report.get("title", "")), "channel": str(report.get("channel", "")), "time": at,
		"length": float(report.get("length", 0.0)), "playing": state == 1 or state == 3 or ad, "ad": ad,
		"captions": bool(report.get("captions", false))}
	if ad: return
	# Wound back: what follows is heard again.
	if not _tube_lines.is_empty() and at < float(_tube_lines[-1][0]) - 5.0:
		_tube_lines = _tube_lines.filter(func(line: Array) -> bool: return float(line[0]) <= at)
	var lines: Variant = report.get("lines", [])
	_tube_up = lines is Array and not (lines as Array).is_empty()
	if not lines is Array: return
	for shown: Variant in lines:
		var text := str(shown).strip_edges()
		if text.is_empty(): continue
		var known := false
		for k in range(_tube_lines.size() - 1, maxi(-1, _tube_lines.size() - 5), -1):
			var old := str(_tube_lines[k][1])
			if text == old or old.begins_with(text):
				known = true
				break
			if text.begins_with(old):
				_tube_lines[k][1] = text
				_tube_changed = Time.get_ticks_msec() / 1000.0
				known = true
				break
		if known: continue
		_tube_lines.append([at, text])
		_tube_changed = Time.get_ticks_msec() / 1000.0
	while _tube_lines.size() > TUBE_LINES: _tube_lines.pop_front()
	# Once a line was read the video has captions, even in a gap between them (2026-11-04: the
	# first remark on a captioned video went out as "title only").
	if not _tube_lines.is_empty(): tube.captions = true

func _forget_tube() -> void:
	tube = {}
	_tube_lines.clear()
	_tube_up = false

## The caption lines said between two video times: [[seconds, text], ...] (tv_set.gd heard).
func tube_lines(from: float, to: float) -> Array:
	return _tube_lines.filter(func(line: Array) -> bool: return float(line[0]) >= from and float(line[0]) <= to)

## Somebody in the YouTube video is talking right now (a caption is up and changed lately).
func tube_talking() -> bool:
	return _tube_up and Time.get_ticks_msec() / 1000.0 - _tube_changed < TUBE_TALKING

# --- the right-click menu and downloads ----------------------------------------------------------

func _menu_open() -> bool:
	return is_instance_valid(_menu) and _menu.visible

## What was under a right click (CONTEXT_JS): the menu for it, where the click was.
func _context_menu(found: Variant = "") -> void:
	var info: Variant = JSON.parse_string(str(found))
	_menu_info = info if info is Dictionary else {}
	if not is_instance_valid(_menu):
		_menu = PopupMenu.new(); _menu.name = "PageMenu"
		_menu.theme = STYLE.theme()
		_menu.add_theme_font_size_override("font_size", BAR_FONT)
		_menu.id_pressed.connect(_menu_chosen)
		_screen.add_child(_menu)
	_menu.clear()
	var link := str(_menu_info.get("link", ""))
	var media := str(_menu_info.get("image", ""))
	var noun := "image"
	if media.is_empty():
		media = str(_menu_info.get("video", ""))
		noun = "video"
	if link.begins_with("http"):
		_menu.add_item("Open link", 1)
		_menu.add_item("Open link in a new tab", 2)
		_menu.add_item("Save link to Downloads", 3)
		_menu.add_item("Save link as…", 13)
		_menu.add_item("Copy link address", 4)
		_menu.add_separator()
	if media.begins_with("http"):
		_menu.add_item("Open %s in a new tab" % noun, 5)
		_menu.add_item("Save %s to Downloads" % noun, 6)
		_menu.add_item("Save %s as…" % noun, 14)
		_menu.add_item("Copy %s address" % noun, 7)
		_menu.add_separator()
	if not str(_menu_info.get("text", "")).is_empty(): _menu.add_item("Copy", 8)
	if bool(_menu_info.get("edit", false)): _menu.add_item("Paste", 9)
	_menu.add_item("Back", 10)
	_menu.set_item_disabled(_menu.item_count - 1, not bool(browser.call("has_previous_page")))
	_menu.add_item("Forward", 11)
	_menu.set_item_disabled(_menu.item_count - 1, not bool(browser.call("has_next_page")))
	_menu.add_item("Reload", 12)
	_menu.reset_size()
	var at := Vector2i(_menu_at)
	_menu.position = Vector2i(clampi(at.x, 0, maxi(0, size.x - _menu.size.x)), clampi(at.y, 0, maxi(0, size.y - _menu.size.y)))
	_menu.popup()

func _menu_chosen(id: int) -> void:
	if not alive(): return
	var link := str(_menu_info.get("link", ""))
	var media := str(_menu_info.get("image", ""))
	if media.is_empty(): media = str(_menu_info.get("video", ""))
	match id:
		1: go(link)
		2: new_tab(link)
		3, 6: save_to_downloads(link if id == 3 else media, "", str(_menu_info.get("agent", "")))
		4: DisplayServer.clipboard_set(link)
		5: new_tab(media)
		7: DisplayServer.clipboard_set(media)
		8: DisplayServer.clipboard_set(str(_menu_info.get("text", "")))
		9: browser.call("execute_javascript", INSERT_JS % JSON.stringify(DisplayServer.clipboard_get()))
		10: back()
		11: forward()
		12: reload()
		13, 14: _save_as(link if id == 13 else media, str(_menu_info.get("agent", "")))

## A download link the player clicked (GUARD_JS).
func _download(address: Variant = "", suggested: Variant = "", agent: Variant = "") -> void:
	save_to_downloads(str(address), str(suggested), str(agent))

## Saves `address` into the Downloads folder as `suggested` (else the server's name, else the
## address's), never over a file already there; or to `target` (Save as). Fetched by Godot,
## without the page's logins.
func save_to_downloads(address: String, suggested := "", agent := "", target := "") -> void:
	if address.begins_with("blob:") or address.begins_with("data:"):
		_blob_target = target
		if alive(): browser.call("execute_javascript", BLOB_JS % [JSON.stringify(address), JSON.stringify(suggested)])
		return
	if not address.begins_with("http"): return
	# Downloaded beside where it ends up (renamed there once complete).
	var folder := target.get_base_dir() if not target.is_empty() else OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var part := folder.path_join("watch_party_%d.part" % Time.get_ticks_usec())
	var request := HTTPRequest.new()
	request.max_redirects = 8
	request.use_threads = true
	request.download_file = part
	add_child(request)
	request.request_completed.connect(_saved.bind(request, part, address, suggested, target))
	var headers := PackedStringArray(["User-Agent: " + (agent if not agent.is_empty() else AGENT)])
	if _url.begins_with("http"): headers.append("Referer: " + _url)
	var error := request.request(address, headers)
	if error != OK:
		request.queue_free()
		notice.emit("Could not save that (error %d)" % error)
		return
	notice.emit("Saving…" if not target.is_empty() else "Saving to Downloads…")

func _saved(result: int, code: int, headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest, part: String, address: String, suggested: String, chosen: String) -> void:
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		DirAccess.remove_absolute(part)
		print("[watch_party] browser: could not save %s (result %d, HTTP %d)" % [address, result, code])
		notice.emit("Could not save that (%s)" % ("HTTP %d" % code if code >= 400 else "no connection"))
		return
	var named := suggested
	var kind := ""
	for header: String in headers:
		var lower := header.to_lower()
		if lower.begins_with("content-type:"): kind = lower.get_slice(":", 1).get_slice(";", 0).strip_edges()
		if named.is_empty() and lower.begins_with("content-disposition:") and "filename=" in lower:
			named = header.substr(lower.find("filename=") + 9).get_slice(";", 0).strip_edges().trim_prefix("\"").trim_suffix("\"")
	if named.is_empty(): named = address.get_slice("?", 0).get_slice("#", 0).get_file().uri_decode()
	var target := chosen if not chosen.is_empty() else _free_name(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), named, kind)
	# Save as asked Windows' own "replace it?" already.
	if not chosen.is_empty() and FileAccess.file_exists(target): DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(part, target) != OK:
		DirAccess.remove_absolute(part)
		notice.emit("Could not save that (the folder refused it)")
		return
	print("[watch_party] browser: saved ", target)
	notice.emit(("Saved: " if not chosen.is_empty() else "Saved to Downloads: ") + target.get_file())

## A blob or data file the page read out (BLOB_JS).
func _save_data(suggested: Variant = "", kind: Variant = "", data: Variant = "") -> void:
	var bytes := Marshalls.base64_to_raw(str(data))
	if bytes.is_empty(): return
	var target := _blob_target if not _blob_target.is_empty() else _free_name(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), str(suggested), str(kind))
	_blob_target = ""
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		notice.emit("Could not save that (the Downloads folder refused it)")
		return
	file.store_buffer(bytes)
	file.close()
	print("[watch_party] browser: saved ", target)
	notice.emit("Saved to Downloads: " + target.get_file())

## Save as (the right-click menu): Windows' save dialog, from the folder saved to last (else
## Downloads), with the mouse free until it closes; the file is saved there.
func _save_as(address: String, agent: String) -> void:
	if picking or not (address.begins_with("http") or address.begins_with("blob:") or address.begins_with("data:")): return
	if not is_instance_valid(_save_dialog):
		_save_dialog = FileDialog.new(); _save_dialog.name = "SaveForPage"
		_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_save_dialog.use_native_dialog = true
		_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_save_dialog.title = "Save as"
		_save_dialog.file_selected.connect(_save_chosen)
		_save_dialog.canceled.connect(_end_picking)
		add_child(_save_dialog)
	_save_pending = [address, agent]
	var folder := str(settings.save_folder) if settings != null else ""
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder): folder = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	_save_dialog.current_dir = folder
	var guess := address.get_slice("?", 0).get_slice("#", 0).get_file().uri_decode() if address.begins_with("http") else ""
	_save_dialog.current_file = _free_name(folder, guess, "").get_file()
	picking = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_save_dialog.popup_centered_ratio(0.6)

func _save_chosen(path: String) -> void:
	_end_picking()
	if _save_pending.is_empty(): return
	if settings != null:
		settings.save_folder = path.get_base_dir()
		settings.save()
	save_to_downloads(str(_save_pending[0]), path.get_file(), str(_save_pending[1]), path)
	_save_pending = []

## A path in `folder` for `wanted` that is free: no characters Windows refuses, an extension from
## the type when it has none, " (2)" and on when the name is taken.
static func _free_name(folder: String, wanted: String, kind: String) -> String:
	var file_name := wanted.strip_edges()
	for bad: String in ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]: file_name = file_name.replace(bad, "_")
	file_name = file_name.strip_edges().trim_suffix(".")
	if file_name.is_empty(): file_name = "download"
	if file_name.get_extension().is_empty():
		for extension: String in MIME:
			if MIME[extension] == kind:
				file_name += "." + extension
				break
	var target := folder.path_join(file_name)
	var n := 2
	while FileAccess.file_exists(target):
		target = folder.path_join("%s (%d)%s" % [file_name.get_basename(), n, ("." + file_name.get_extension()) if not file_name.get_extension().is_empty() else ""])
		n += 1
	return target

# --- picking files for the page ------------------------------------------------------------------

## The page asked for a file (GUARD_JS): Windows' own file dialog, in the last folder used (else
## the pictures folder), with the mouse free until it closes.
func _file_wanted(accept: Variant = "", multiple: Variant = false) -> void:
	if picking: return
	if not is_instance_valid(_dialog):
		_dialog = FileDialog.new(); _dialog.name = "PickForPage"
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.title = "A file for the page"
		_dialog.file_selected.connect(_picked_one)
		_dialog.files_selected.connect(_picked)
		_dialog.canceled.connect(_end_picking)
		add_child(_dialog)
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES if bool(multiple) else FileDialog.FILE_MODE_OPEN_FILE
	_dialog.filters = _filters(str(accept))
	var folder := str(settings.pick_folder) if settings != null else ""
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder): folder = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	_dialog.current_dir = folder
	picking = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_dialog.popup_centered_ratio(0.6)

func _picked_one(path: String) -> void:
	_picked(PackedStringArray([path]))

func _picked(paths: PackedStringArray) -> void:
	var list: Array = []
	for path: String in paths:
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty() or bytes.size() > PICK_MAX_BYTES:
			print("[watch_party] browser: not handed to the page (empty or over %d MB): %s" % [PICK_MAX_BYTES / 1048576, path])
			continue
		list.append({"n": path.get_file(), "t": MIME.get(path.get_extension().to_lower(), "application/octet-stream"), "d": Marshalls.raw_to_base64(bytes)})
	if not paths.is_empty() and settings != null:
		settings.pick_folder = paths[0].get_base_dir()
		settings.save()
	if not list.is_empty() and alive():
		browser.call("execute_javascript", FILES_JS % JSON.stringify(list))
		print("[watch_party] browser: handed %d file(s) to the page" % list.size())
	_end_picking()

func _end_picking() -> void:
	if not picking: return
	picking = false
	Input.mouse_mode = _mouse_before

## Dialog filters from a file input's accept list ("image/*,.webm", "image/png"...).
static func _filters(accept: String) -> PackedStringArray:
	var types: Array[String] = []
	for item: String in accept.to_lower().split(",", false):
		var wanted := item.strip_edges()
		if wanted.begins_with("."): types.append(wanted.trim_prefix("."))
		elif wanted == "image/*": types.append_array(PICTURES)
		elif wanted == "video/*": types.append_array(["webm", "mp4"])
		else:
			for extension: String in MIME:
				if MIME[extension] == wanted: types.append(extension)
	var filters := PackedStringArray()
	if not types.is_empty():
		var patterns := PackedStringArray()
		for extension: String in types:
			if not ("*." + extension) in patterns: patterns.append("*." + extension)
		filters.append("%s ; What the page takes" % ", ".join(patterns))
	filters.append("*.* ; All files")
	return filters

## What a reader sees of an HTML page: no scripts, styles or tags, spaces collapsed.
static func visible_text(html: String) -> String:
	var text := RegEx.create_from_string("(?is)<(script|style|noscript|svg|head)[^>]*>.*?</\\1>").sub(html, " ", true)
	text = RegEx.create_from_string("(?s)<[^>]+>").sub(text, " ", true)
	for pair: Array in [["&nbsp;", " "], ["&amp;", "&"], ["&quot;", "\""], ["&#39;", "'"], ["&lt;", "<"], ["&gt;", ">"]]:
		text = text.replace(pair[0], pair[1])
	return RegEx.create_from_string("\\s+").sub(text, " ", true).strip_edges()
