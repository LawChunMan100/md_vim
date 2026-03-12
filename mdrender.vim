" mdrender.vim — Markdown live-preview plugin for (Neo)Vim
"
" Usage: add this line to your init.vim / vimrc:
"   source /path/to/mdrender.vim
"
" Then open any markdown file and run:
"   :MDRender
"
" A browser window opens showing the rendered markdown. The preview
" refreshes automatically as you type. All relative paths (images,
" links) resolve correctly because the page's <base href> is set to
" the directory of the file you are editing. No local HTTP server is
" required.

if exists('g:loaded_mdrender')
  finish
endif
let g:loaded_mdrender = 1

" Directory that contains this script (used to find lib/ and style.css).
let s:plugin_dir = expand('<sfile>:p:h')

" Paths to the temp files created for the current preview session.
let s:temp_html = ''
let s:temp_md   = ''

" ── Platform helpers ──────────────────────────────────────────────────────────

function! s:OpenBrowser(path) abort
  if has('mac') || has('macunix')
    call system('open ' . shellescape(a:path))
  elseif has('unix')
    call system('xdg-open ' . shellescape(a:path))
  elseif has('win32') || has('win64')
    execute 'silent !start "" ' . shellescape(a:path)
  else
    echoerr 'MDRender: unsupported platform'
  endif
endfunction

" Return a file:// base URL ending in '/' for the current buffer's directory.
function! s:BaseURL() abort
  let l:dir = expand('%:p:h')
  if l:dir ==# ''
    let l:dir = getcwd()
  endif
  if has('win32') || has('win64')
    return 'file:///' . substitute(l:dir, '\\', '/', 'g') . '/'
  else
    return 'file://' . l:dir . '/'
  endif
endfunction

" ── HTML generation ───────────────────────────────────────────────────────────

function! s:WritePreview() abort
  if s:temp_html ==# ''
    return
  endif

  " 1. Dump the current buffer to the temp markdown file.
  call writefile(getline(1, '$'), s:temp_md)

  " 2. Base64-encode the markdown so it embeds safely in a JS string literal.
  "    Strip all whitespace (Linux wraps at 76 chars; macOS does not).
  let l:b64 = substitute(system('base64 ' . shellescape(s:temp_md)), '[[:space:]]', '', 'g')
  if v:shell_error
    echoerr 'MDRender: base64 encoding failed – is base64 on your PATH?'
    return
  endif

  " 3. Inline CSS and marked.js from the plugin directory.
  let l:css_file = s:plugin_dir . '/style.css'
  let l:css      = filereadable(l:css_file) ? join(readfile(l:css_file), "\n") : ''

  let l:js_file  = s:plugin_dir . '/lib/marked.umd.js'
  let l:marked   = filereadable(l:js_file)  ? join(readfile(l:js_file),  "\n") : ''

  " 4. Derive metadata.
  let l:base_url = s:BaseURL()
  let l:title    = expand('%:t')
  if l:title ==# ''
    let l:title = 'Markdown Preview'
  endif

  " 5. Build the self-contained HTML page.
  "    • <base href> makes all relative assets resolve to the markdown dir.
  "    • Markdown is base64-decoded in JS and rendered by marked.js.
  "    • The page reloads every second; scroll position is preserved via
  "      sessionStorage so the view stays stable while the user edits.
  let l:lines = [
        \ '<!DOCTYPE html>',
        \ '<html lang="en">',
        \ '<head>',
        \ '  <meta charset="UTF-8">',
        \ '  <meta name="viewport" content="width=device-width, initial-scale=1.0">',
        \ '  <title>' . l:title . '</title>',
        \ '  <base href="' . l:base_url . '">',
        \ '  <style>',
        \ l:css,
        \ '  </style>',
        \ '</head>',
        \ '<body>',
        \ '  <div id="preview"></div>',
        \ '  <script>' . l:marked . '</script>',
        \ '  <script>',
        \ '    (function () {',
        \ '      "use strict";',
        \ '',
        \ '      // Restore scroll position that was saved before the last reload.',
        \ '      var savedY = sessionStorage.getItem("mdrY");',
        \ '      if (savedY !== null) { window.scrollTo(0, +savedY); }',
        \ '',
        \ '      // Decode base64 → binary → UTF-8 string.',
        \ '      var b64   = "' . l:b64 . '";',
        \ '      var bin   = atob(b64);',
        \ '      var bytes = new Uint8Array(bin.length);',
        \ '      for (var i = 0; i < bin.length; i++) { bytes[i] = bin.charCodeAt(i); }',
        \ '      var md = new TextDecoder("utf-8").decode(bytes);',
        \ '',
        \ '      // Render the markdown.',
        \ '      document.getElementById("preview").innerHTML = marked.parse(md);',
        \ '',
        \ '      // Reload after one second to pick up any buffer changes.',
        \ '      // Save the scroll position first so the view is stable.',
        \ '      setTimeout(function () {',
        \ '        sessionStorage.setItem("mdrY", window.scrollY);',
        \ '        location.reload();',
        \ '      }, 1000);',
        \ '    }());',
        \ '  </script>',
        \ '</body>',
        \ '</html>',
        \ ]

  call writefile(l:lines, s:temp_html)
endfunction

" ── :MDRender command ─────────────────────────────────────────────────────────

function! s:MDRender() abort
  " If the preview is already running, just refresh it.
  if s:temp_html !=# ''
    call s:WritePreview()
    echo 'MDRender: preview updated'
    return
  endif

  " First call – create temp files and open the browser.
  let s:temp_html = tempname() . '.html'
  let s:temp_md   = tempname() . '.md'

  call s:WritePreview()
  call s:OpenBrowser(s:temp_html)

  " Keep the preview in sync while this buffer is open.
  " TextChanged fires after a change in Normal mode (and after leaving Insert
  " mode), so the preview stays current without triggering on every keystroke.
  augroup MDRenderAutoUpdate
    autocmd!
    autocmd TextChanged,BufWritePost <buffer> call s:WritePreview()
  augroup END

  echo 'MDRender: preview opened in browser'
endfunction

command! MDRender call s:MDRender()
