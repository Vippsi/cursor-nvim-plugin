" plugin/cursor_cli.vim
" ===================================================================
" Cursor CLI Plugin for Neovim - Commands
" ===================================================================

if exists('g:loaded_cursor_cli') || !has('nvim')
  finish
endif
let g:loaded_cursor_cli = 1

let g:cursor_cli_command = get(g:, 'cursor_cli_command', 'cursor-agent')
let g:cursor_cli_model = get(g:, 'cursor_cli_model', 'opus-4.5-thinking')
let g:cursor_cli_output_format = get(g:, 'cursor_cli_output_format', 'stream-json')
let g:cursor_cli_open = get(g:, 'cursor_cli_open', 'botright split')
let g:cursor_cli_height = get(g:, 'cursor_cli_height', 15)

function! CursorChat() abort
  let l:q = input('💬 Ask Cursor AI (one-shot): ')
  if empty(l:q)
    return
  endif
  call cursor_cli#exec_stream(cursor_cli#create_prompt_with_context(l:q))
endfunction

function! CursorTest() abort
  echo "Testing Cursor CLI connection..."
  let l:old_fmt = get(g:, 'cursor_cli_output_format', 'stream-json')
  let g:cursor_cli_output_format = 'json'
  let l:result = cursor_cli#exec("Just say 'Hello from Cursor!' - this is a test")
  let g:cursor_cli_output_format = l:old_fmt
  if !empty(l:result)
    echo "✅ Test successful! Response: " . l:result[:100] . (len(l:result) > 100 ? "..." : "")
  else
    echo "❌ Test failed - check :messages for errors"
  endif
endfunction

function! CursorREPL() abort
  call cursor_cli#repl_open()
endfunction

function! CursorREPLToggle() abort
  call cursor_cli#repl_toggle()
endfunction

function! CursorREPLSend(...) abort
  if a:0 > 0
    call cursor_cli#repl_send(a:1)
    return
  endif
  let l:line = getline('.')
  if empty(trim(l:line))
    let l:line = input('Send to Cursor REPL: ')
  endif
  if empty(trim(l:line))
    return
  endif
  call cursor_cli#repl_send(l:line)
endfunction

command! CursorStatus echo cursor_cli#available() ? "✅ Cursor CLI available" : "❌ Cursor CLI not found"
command! CursorTest call CursorTest()

" One-shot streaming scratch output
command! CursorChat call CursorChat()
command! -nargs=1 CursorStream call cursor_cli#exec_stream(<q-args>)

" REPL
command! CursorREPL call CursorREPL()
command! CursorREPLToggle call CursorREPLToggle()
command! -nargs=? CursorREPLSend call CursorREPLSend(<f-args>)
