/* Release pages: language + theme toggles and copy buttons.
   The language is picked before paint by the inline <head> script
   (?lang= → localStorage → navigator.language → en); this file wires the buttons. */
(function(){
  var root = document.documentElement;
  var $ = function(s){ return document.querySelector(s); };
  var L = {
    en: {dark:'dark', light:'light', copy:'copy', copied:'copied', failed:'select and copy'},
    es: {dark:'oscuro', light:'claro', copy:'copiar', copied:'copiado', failed:'selecciona y copia'}
  };
  function lang(){ return root.lang === 'es' ? 'es' : 'en'; }
  function t(k){ return L[lang()][k]; }

  var mq = window.matchMedia ? matchMedia('(prefers-color-scheme: dark)') : null;
  function isDark(){ var a = root.getAttribute('data-theme'); return a ? a === 'dark' : !!(mq && mq.matches); }
  function paint(){
    var l = lang();
    var en = $('#lang-en'), es = $('#lang-es'), th = $('#theme');
    if (en) en.setAttribute('aria-pressed', l === 'en');
    if (es) es.setAttribute('aria-pressed', l === 'es');
    if (th) th.textContent = isDark() ? t('light') : t('dark');
    document.querySelectorAll('[data-copy]').forEach(function(b){ if (!b.hasAttribute('data-busy')) b.textContent = t('copy'); });
    var ti = root.getAttribute('data-title-' + l); if (ti) document.title = ti;
    var u = new URL(location.href);
    if (u.searchParams.has('lang') && u.searchParams.get('lang') !== l){ u.searchParams.set('lang', l); try { history.replaceState(null, '', u); } catch(e){} }
  }
  function setLang(l){ root.lang = l; try { localStorage.setItem('ne-lang', l); } catch(e){} paint(); }

  var en = $('#lang-en'), es = $('#lang-es'), th = $('#theme');
  if (en) en.onclick = function(){ setLang('en'); };
  if (es) es.onclick = function(){ setLang('es'); };
  if (th) th.onclick = function(){
    var next = isDark() ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('ne-theme', next); } catch(e){}
    paint();
  };
  if (mq && mq.addEventListener) mq.addEventListener('change', paint);

  /* copy buttons: <button data-copy> inside .ne-code copies the <pre> text without "$ " prompts */
  document.querySelectorAll('[data-copy]').forEach(function(b){
    b.onclick = function(){
      var box = b.closest('.ne-code'), pre = box && box.querySelector('pre');
      if (!pre) return;
      var clone = pre.cloneNode(true);
      clone.querySelectorAll('.ne-p,.ne-c').forEach(function(n){ n.remove(); });
      var text = clone.textContent.split('\n').map(function(s){ return s.replace(/\s+$/, ''); }).filter(Boolean).join('\n');
      function done(k){ b.setAttribute('data-busy', ''); b.textContent = t(k); setTimeout(function(){ b.removeAttribute('data-busy'); b.textContent = t('copy'); }, 1600); }
      if (navigator.clipboard && navigator.clipboard.writeText){
        navigator.clipboard.writeText(text).then(function(){ done('copied'); }, function(){ done('failed'); });
      } else { done('failed'); }
    };
  });

  paint();
})();
