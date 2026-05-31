// Draw connector arrows from margin cards to the \cssId-tagged parts of an
// annotated equation, once MathJax has typeset the page.
(function () {
  function whenMathReady(cb) {
    if (window.MathJax && MathJax.startup && MathJax.startup.promise) {
      MathJax.startup.promise.then(function () { setTimeout(cb, 60); });
    } else {
      setTimeout(function () { whenMathReady(cb); }, 200);
    }
  }

  function draw() {
    document.querySelectorAll('.mathanno-block').forEach(function (block) {
      var svg = block.querySelector('.mathanno-lines');
      if (!svg) return;
      svg.innerHTML = '';
      if (window.innerWidth <= 1300) return;   // cards stack below; no arrows

      var b = block.getBoundingClientRect();
      var cards = block.querySelector('.mathanno-cards');
      var ext = cards ? (cards.getBoundingClientRect().right - b.right + 12) : 0;
      svg.style.width = (b.width + Math.max(ext, 0)) + 'px';
      svg.style.height = block.scrollHeight + 'px';

      block.querySelectorAll('.mathanno-card').forEach(function (card) {
        var tid = card.getAttribute('data-target');
        if (!tid) return;
        var tgt = document.getElementById(tid);
        if (!tgt) return;

        var tr = tgt.getBoundingClientRect();
        var cr = card.getBoundingClientRect();
        var ox = b.left, oy = b.top;
        var x1 = tr.right - ox, y1 = tr.top + tr.height / 2 - oy;   // equation part
        var x2 = cr.left - ox, y2 = cr.top + cr.height / 2 - oy;    // card
        var dx = (x2 - x1) * 0.45;

        var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        path.setAttribute('d',
          'M ' + x1 + ' ' + y1 +
          ' C ' + (x1 + dx) + ' ' + y1 + ' ' + (x2 - dx) + ' ' + y2 + ' ' + x2 + ' ' + y2);
        path.setAttribute('fill', 'none');
        path.setAttribute('stroke', '#b3392f');
        path.setAttribute('stroke-width', '1.4');
        path.setAttribute('stroke-dasharray', '4 3');
        path.setAttribute('opacity', '0.5');
        svg.appendChild(path);

        var dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        dot.setAttribute('cx', x1); dot.setAttribute('cy', y1);
        dot.setAttribute('r', '2.5'); dot.setAttribute('fill', '#b3392f');
        dot.setAttribute('opacity', '0.6');
        svg.appendChild(dot);
      });
    });
  }

  whenMathReady(draw);
  var t;
  window.addEventListener('resize', function () {
    clearTimeout(t); t = setTimeout(draw, 120);
  });
})();
