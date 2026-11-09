class BrowserExtensionsCatalog {
  static const String adBlockScript = '''
(function() {
  function applyAdBlock() {
    var selectors = [
      '.ad', '.ads', '.ad-banner', '.advertisement',
      '[class*="ad-box"]', '[class*="ad_box"]', '[class*="sponsored"]',
      '[id*="google_ads"]', 'ins.adsbygoogle', '[aria-label="advertisement"]',
      'iframe[src*="doubleclick.net"]', 'iframe[src*="googlesyndication.com"]',
      'iframe[src*="adservice"]'
    ];
    var nodes = document.querySelectorAll(selectors.join(','));
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].style.setProperty('display', 'none', 'important');
    }
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', applyAdBlock);
  } else {
    applyAdBlock();
  }
  setInterval(applyAdBlock, 1500);
})();
''';

  static const String darkModeScript = '''
(function() {
  if (document.getElementById('void-dark-mode-extension')) return;
  var style = document.createElement('style');
  style.id = 'void-dark-mode-extension';
  style.textContent = 'html { filter: invert(90%) hue-rotate(180deg) !important; background-color: #121212 !important; } img, video, canvas, svg, iframe, embed, object { filter: invert(100%) hue-rotate(180deg) !important; }';
  (document.head || document.documentElement).appendChild(style);
})();
''';

  static const String toggleErudaScript = '''
(function() {
  if (window.eruda) {
    if (window._voidErudaActive) {
      window.eruda.hide();
      window._voidErudaActive = false;
    } else {
      window.eruda.show();
      window._voidErudaActive = true;
    }
  } else {
    var s = document.createElement('script');
    s.src = 'https://cdn.jsdelivr.net/npm/eruda';
    s.onload = function() {
      if (window.eruda) {
        eruda.init();
        eruda.show();
        window._voidErudaActive = true;
      }
    };
    s.onerror = function() {
      var box = document.getElementById('__void_devtools_box');
      if (box) {
        box.style.display = box.style.display === 'none' ? 'block' : 'none';
        return;
      }
      box = document.createElement('div');
      box.id = '__void_devtools_box';
      box.style.cssText = 'position:fixed;bottom:0;left:0;right:0;height:45vh;background:#1e1e1e;color:#00ff66;z-index:9999999;font-family:monospace;font-size:12px;padding:8px;overflow:auto;border-top:2px solid #555;box-shadow:0 -4px 12px rgba(0,0,0,0.5);';
      box.innerHTML = '<div style="display:flex;justify-content:space-between;border-bottom:1px solid #444;padding-bottom:4px;margin-bottom:6px;font-weight:bold;color:#fff;"><span>VOID Chromium DevTools</span><span style="cursor:pointer;" onclick="this.parentNode.parentNode.style.display=\\'none\\'">[X Close]</span></div><div id="__void_devtools_logs"></div><div style="display:flex;margin-top:6px;"><input id="__void_devtools_input" style="flex:1;background:#2a2a2a;color:#fff;border:1px solid #555;padding:4px;" placeholder="Execute JavaScript..."><button style="background:#007acc;color:#fff;border:none;padding:4px 8px;margin-left:4px;" onclick="var inp=document.getElementById(\\'__void_devtools_input\\'); try { var res = eval(inp.value); console.log(res); } catch(e) { console.error(e); }">Run</button></div>';
      document.body.appendChild(box);
      function logMsg(type, args) {
        var logs = document.getElementById('__void_devtools_logs');
        if (!logs) return;
        var p = document.createElement('div');
        p.style.cssText = type === 'error' ? 'color:#ff5555;' : type === 'warn' ? 'color:#ffaa00;' : 'color:#00ff66;';
        p.textContent = '[' + type.toUpperCase() + '] ' + Array.from(args).map(function(x) { return typeof x === 'object' ? JSON.stringify(x) : x; }).join(' ');
        logs.appendChild(p);
        logs.scrollTop = logs.scrollHeight;
      }
      var _log = console.log, _warn = console.warn, _err = console.error;
      console.log = function() { _log.apply(console, arguments); logMsg('log', arguments); };
      console.warn = function() { _warn.apply(console, arguments); logMsg('warn', arguments); };
      console.error = function() { _err.apply(console, arguments); logMsg('error', arguments); };
      console.log('VOID DevTools fallback active. Chromium inspectable bridge initialized.');
    };
    (document.head || document.documentElement).appendChild(s);
  }
})();
''';
}
