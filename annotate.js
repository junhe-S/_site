// Draw connector lines + interactive hover highlighting
(function() {
  function drawLines() {
    document.querySelectorAll('.annotate-block').forEach(function(block) {
      var svg = block.querySelector('.anno-lines');
      if (!svg || window.innerWidth <= 1300) { svg && (svg.innerHTML = ''); return; }

      svg.innerHTML = '';

      var blockRect = block.getBoundingClientRect();

      var leftCards = block.querySelector('.annotate-left');
      var rightCards = block.querySelector('.annotate-right');
      var leftExt = 0, rightExt = 0;
      if (leftCards) {
        leftExt = blockRect.left - leftCards.getBoundingClientRect().left + 10;
      }
      if (rightCards) {
        rightExt = rightCards.getBoundingClientRect().right - blockRect.right + 10;
      }

      svg.style.left = (-leftExt) + 'px';
      svg.style.width = (blockRect.width + leftExt + rightExt) + 'px';
      svg.style.height = block.scrollHeight + 'px';

      block.querySelectorAll('mark.anno-hl').forEach(function(hl) {
        var cardId = hl.getAttribute('data-card');
        var card = document.getElementById(cardId);
        if (!card) return;

        var side = card.getAttribute('data-side');
        var hlRect = hl.getBoundingClientRect();
        var cardRect = card.getBoundingClientRect();
        var color = getComputedStyle(hl).getPropertyValue('--hl-color').trim();

        var svgOriginX = blockRect.left - leftExt;
        var svgOriginY = blockRect.top;

        var x1, y1, x2, y2;
        y1 = hlRect.top + hlRect.height / 2 - svgOriginY;
        y2 = cardRect.top + cardRect.height / 2 - svgOriginY;

        if (side === 'left') {
          x1 = hlRect.left - svgOriginX;
          x2 = cardRect.right - svgOriginX;
        } else {
          x1 = hlRect.right - svgOriginX;
          x2 = cardRect.left - svgOriginX;
        }

        var dx = (x2 - x1) * 0.45;
        var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        path.setAttribute('d',
          'M ' + x1 + ' ' + y1 +
          ' C ' + (x1 + dx) + ' ' + y1 + ' ' + (x2 - dx) + ' ' + y2 + ' ' + x2 + ' ' + y2
        );
        path.setAttribute('fill', 'none');
        path.setAttribute('stroke', color || '#7C6AEF');
        path.setAttribute('stroke-width', '1.5');
        path.setAttribute('stroke-dasharray', '4 3');
        path.setAttribute('opacity', '0.4');
        path.setAttribute('data-card', cardId);
        svg.appendChild(path);

        var c1 = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        c1.setAttribute('cx', x1); c1.setAttribute('cy', y1);
        c1.setAttribute('r', '2.5'); c1.setAttribute('fill', color || '#7C6AEF');
        c1.setAttribute('opacity', '0.55');
        c1.setAttribute('data-card', cardId);
        svg.appendChild(c1);

        var c2 = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        c2.setAttribute('cx', x2); c2.setAttribute('cy', y2);
        c2.setAttribute('r', '2.5'); c2.setAttribute('fill', color || '#7C6AEF');
        c2.setAttribute('opacity', '0.55');
        c2.setAttribute('data-card', cardId);
        svg.appendChild(c2);
      });
    });
  }

  function setupHover() {
    // Hover word → highlight card + line
    document.querySelectorAll('mark.anno-hl').forEach(function(hl) {
      var cardId = hl.getAttribute('data-card');
      hl.addEventListener('mouseenter', function() { activate(cardId); });
      hl.addEventListener('mouseleave', function() { deactivate(cardId); });
    });

    // Hover card → highlight word + line
    document.querySelectorAll('.anno-card').forEach(function(card) {
      var cardId = card.id;
      card.addEventListener('mouseenter', function() { activate(cardId); });
      card.addEventListener('mouseleave', function() { deactivate(cardId); });
    });
  }

  function activate(cardId) {
    var card = document.getElementById(cardId);
    var hl = document.querySelector('mark[data-card="' + cardId + '"]');
    if (card) card.classList.add('anno-active');
    if (hl) hl.classList.add('anno-active');
    // Brighten connector line
    document.querySelectorAll('svg [data-card="' + cardId + '"]').forEach(function(el) {
      el.setAttribute('opacity', '1');
      if (el.tagName === 'path') el.setAttribute('stroke-width', '2.5');
    });
  }

  function deactivate(cardId) {
    var card = document.getElementById(cardId);
    var hl = document.querySelector('mark[data-card="' + cardId + '"]');
    if (card) card.classList.remove('anno-active');
    if (hl) hl.classList.remove('anno-active');
    document.querySelectorAll('svg [data-card="' + cardId + '"]').forEach(function(el) {
      if (el.tagName === 'path') {
        el.setAttribute('opacity', '0.4');
        el.setAttribute('stroke-width', '1.5');
      } else {
        el.setAttribute('opacity', '0.55');
      }
    });
  }

  function init() {
    setTimeout(function() { drawLines(); setupHover(); }, 150);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
  window.addEventListener('resize', function() { drawLines(); setupHover(); });
})();
