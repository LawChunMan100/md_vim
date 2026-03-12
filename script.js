(function () {
  'use strict';

  const preview = document.getElementById('preview');

  // ── URL-based configuration ───────────────────────────────────────────────────
  // mdrender.vim passes settings as query parameters, e.g.:
  //   http://localhost:PORT/?dark=1&fontsize=18&file=contents/myfile.md

  const params = new URLSearchParams(window.location.search);

  const darkEnabled = params.get('dark') === '1';
  if (darkEnabled) {
    document.body.classList.add('dark');
  }

  const fontSize = parseInt(params.get('fontsize'), 10);
  if (!isNaN(fontSize) && fontSize > 0 && fontSize <= 72) {
    document.body.style.fontSize = fontSize + 'px';
  }

  // The file being edited in Neovim (passed via ?file=).
  const watchedFile = params.get('file') || 'content.md';

  // Track the currently displayed file so link navigation works.
  let currentFile = watchedFile;

  // ── Path utilities ────────────────────────────────────────────────────────────

  // Return the directory portion of a path (with trailing slash).
  function dirOf(filePath) {
    const idx = filePath.lastIndexOf('/');
    return idx >= 0 ? filePath.slice(0, idx + 1) : '';
  }

  // Resolve a relative href against a base directory path.
  // e.g. resolvePath('contents/subdir/', '../main.md') → 'contents/main.md'
  function resolvePath(baseDir, rel) {
    const parts = (baseDir + rel).split('/');
    const resolved = [];
    for (const p of parts) {
      if (p === '..') {
        if (resolved.length > 0) { resolved.pop(); }
      } else if (p !== '.') {
        resolved.push(p);
      }
    }
    return resolved.join('/');
  }

  // ── Custom marked renderer ────────────────────────────────────────────────────
  // Preserve the raw (unresolved) href from the markdown source so that our
  // click handler can resolve it relative to the current file's directory,
  // correctly handling paths like ../something.md.

  marked.use({
    renderer: {
      link({ href, title, text }) {
        const titleAttr = title ? ` title="${title}"` : '';
        const dataAttr = href ? ` data-raw-href="${href}"` : '';
        return `<a href="${href || ''}"${titleAttr}${dataAttr}>${text}</a>`;
      }
    }
  });

  // ── Rendering ────────────────────────────────────────────────────────────────

  function render(text) {
    const baseUrl = dirOf(currentFile);
    preview.innerHTML = marked.parse(text, { baseUrl: baseUrl });
    if (window.MathJax) {
      MathJax.typesetPromise([preview]).catch((err) => console.error(err));
    }
  }

  // ── Link interception for .md navigation ─────────────────────────────────────
  // Intercept clicks on markdown links that end in .md and load them inside the
  // preview rather than navigating away.  The raw href stored in data-raw-href
  // is resolved relative to the directory of the currently displayed file so
  // that ../something.md links work correctly.

  preview.addEventListener('click', function (e) {
    const anchor = e.target.closest('a[data-raw-href]');
    if (!anchor) return;

    const rawHref = anchor.getAttribute('data-raw-href');
    if (!rawHref) return;

    // Let absolute URLs and fragment-only links open normally.
    if (/^[a-z][a-z0-9+\-.]*:/i.test(rawHref) || rawHref.startsWith('#')) return;

    if (rawHref.endsWith('.md')) {
      e.preventDefault();
      const target = resolvePath(dirOf(currentFile), rawHref);

      fetch(target + '?_=' + Date.now())
        .then(function (res) {
          if (!res.ok) { throw new Error('not found'); }
          return res.text();
        })
        .then(function (text) {
          currentFile = target;
          render(text);
        })
        .catch(function () {
          console.warn('MDRender: could not load', target);
        });
    }
  });

  // ── Poll for the watched file ─────────────────────────────────────────────────
  // The Neovim plugin writes the buffer to contents/<filename>; we fetch it
  // every 500 ms and re-render only while the user has not navigated away.

  function fetchAndRender() {
    if (currentFile !== watchedFile) { return; }

    fetch(watchedFile + '?_=' + Date.now())
      .then(function (res) {
        if (!res.ok) { throw new Error('not ready'); }
        return res.text();
      })
      .then(render)
      .catch(function () { /* file not ready yet – try again next tick */ });
  }

  setInterval(fetchAndRender, 500);
  fetchAndRender();
}());
