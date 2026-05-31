// Page-level R / Python code toggle for Data chapters.
// Sets data-codelang ("r" default, or "py") on <html>; CSS shows/hides
// .code-r / .code-py blocks accordingly. Choice persists in localStorage.
function setCodeLang(lang) {
  document.documentElement.setAttribute('data-codelang', lang);
  try { localStorage.setItem('codelang', lang); } catch (e) {}
  document.querySelectorAll('.code-toggle').forEach(function (b) {
    b.textContent = lang === 'py' ? 'Python | R' : 'R | Python';
  });
}

function toggleCodeLang() {
  var cur = document.documentElement.getAttribute('data-codelang') || 'r';
  setCodeLang(cur === 'r' ? 'py' : 'r');
}

(function () {
  var saved = 'r';
  try { saved = localStorage.getItem('codelang') || 'r'; } catch (e) {}
  setCodeLang(saved);
})();
