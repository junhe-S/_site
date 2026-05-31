// EN / 中文 prose toggle. Only appears on pages that contain bilingual blocks
// (.lang.zh + .lang.en). Headings and formulas are shared and never toggled.
(function () {
  function init() {
    var hasBilingual = document.querySelector('.lang.en') && document.querySelector('.lang.zh');
    if (!hasBilingual) return;

    var saved = localStorage.getItem('lang');
    if (saved === 'en') document.documentElement.setAttribute('data-lang', 'en');

    var btn = document.createElement('button');
    btn.className = 'lang-toggle';
    function label() {
      return document.documentElement.getAttribute('data-lang') === 'en' ? '中文' : 'EN';
    }
    btn.textContent = label();
    btn.setAttribute('aria-label', 'Toggle language');
    btn.addEventListener('click', function () {
      if (document.documentElement.getAttribute('data-lang') === 'en') {
        document.documentElement.removeAttribute('data-lang');
        localStorage.setItem('lang', 'zh');
      } else {
        document.documentElement.setAttribute('data-lang', 'en');
        localStorage.setItem('lang', 'en');
      }
      btn.textContent = label();
      // Re-typeset/re-measure isn't needed; MathJax output is shared and stays put.
      window.dispatchEvent(new Event('resize'));   // nudge any annotation arrows
    });

    // Place the toggle at the right end of the article title (not the navbar).
    var h1 = document.querySelector('.article-header h1') ||
             document.querySelector('article h1') ||
             document.querySelector('h1');
    if (h1) {
      h1.classList.add('has-lang-toggle');
      h1.appendChild(btn);
    } else {
      document.body.appendChild(btn);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
