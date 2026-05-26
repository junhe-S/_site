function toggleTheme() {
  const html = document.documentElement;
  const btn = document.querySelector('.theme-toggle');
  if (html.getAttribute('data-theme') === 'light') {
    html.removeAttribute('data-theme');
    btn.textContent = '🌞';
    localStorage.setItem('theme', 'dark');
  } else {
    html.setAttribute('data-theme', 'light');
    btn.textContent = '🌙';
    localStorage.setItem('theme', 'light');
  }
}

(function() {
  var saved = localStorage.getItem('theme');
  if (saved === 'light') {
    document.documentElement.setAttribute('data-theme', 'light');
    document.addEventListener('DOMContentLoaded', function() {
      document.querySelector('.theme-toggle').textContent = '🌙';
    });
  }
})();
