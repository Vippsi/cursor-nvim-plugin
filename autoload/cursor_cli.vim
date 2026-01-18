" autoload/cursor_cli.vim
" ===================================================================
" Cursor CLI Plugin - Autoload Functions (Streaming)
" Provides Cursor IDE-like functionality using the Cursor CLI
"
" Neovim streaming via jobstart() + on_stdout callbacks.
" IMPORTANT: uses `pty = v:true` so cursor-agent flushes output incrementally.
"
" Optional globals:
"   let g:cursor_cli_command = 'cursor-agent'
"   let g:cursor_cli_model = 'opus-4.5-thinking'     " or 'auto', etc.
"   let g:cursor_cli_output_format = 'stream-json'   " 'stream-json' | 'json' | 'text'
"   let g:cursor_cli_open = 'botright split'
"   let g:cursor_cli_height = 15
"   let g:cursor_cli_debug_raw = 0                   " set to 1 to append raw lines
"   let g:cursor_cli_force_stdbuf = ''               " e.g. 'stdbuf' or 'gstdbuf'
"
" ===================================================================

let s:jobs = {}

" Check if cursor CLI is available
function! cursor_cli#available() abort
  let l:command = get(g:, 'cursor_cli_command', 'cursor-agent')
  return executable(l:command) || executable('cursor-agent')
endfunction

" -------------------------------------------------------------------
" Public entrypoint (non-streaming; reliable parsing)
" -------------------------------------------------------------------
function! cursor_cli#exec(prompt) abort
  if !cursor_cli#available()
    echohl ErrorMsg
    echo "Cursor CLI not found. Install with: curl https://cursor.com/install -fsS | bash"
    echohl None
    return ""
  endif

  let l:command = get(g:, 'cursor_cli_command', 'cursor-agent')
  let l:fmt = get(g:, 'cursor_cli_output_format', 'json')
  let l:model = get(g:, 'cursor_cli_model', '')

  let l:args = [l:command, '--print']
  if l:fmt !=# 'text'
    call extend(l:args, ['--output-format', l:fmt])
  endif
  if !empty(l:model)
    call extend(l:args, ['--model', l:model])
  endif
  call add(l:args, a:prompt)

  echo "Cursor AI working..."
  redraw

  let l:start_time = localtime()
  let l:lines = systemlist(l:args)
  let l:end_time = localtime()

  if v:shell_error != 0
    echohl ErrorMsg
    echo "Cursor AI failed (exit " . v:shell_error . "):"
    echohl None
    if !empty(l:lines)
      echo join(l:lines, "\n")
    endif
    return ""
  endif

  if empty(l:lines)
    echohl WarningMsg
    echo "Cursor AI returned empty response"
    echohl None
    return ""
  endif

  let l:result = cursor_cli#parse_cursor_output(l:lines, l:fmt)
  if empty(l:result)
    let l:result = join(l:lines, "\n")
  endif

  let l:duration = l:end_time - l:start_time
  echo "✅ Cursor AI completed in " . l:duration . "s"
  return l:result
endfunction

" -------------------------------------------------------------------
" Streaming entrypoint: opens a buffer and streams text as it arrives
" -------------------------------------------------------------------
function! cursor_cli#exec_stream(prompt) abort
  if !has('nvim')
    echohl ErrorMsg
    echo "Streaming mode requires Neovim."
    echohl None
    return -1
  endif

  if !cursor_cli#available()
    echohl ErrorMsg
    echo "Cursor CLI not found. Install with: curl https://cursor.com/install -fsS | bash"
    echohl None
    return -1
  endif

  let l:command = get(g:, 'cursor_cli_command', 'cursor-agent')
  let l:model = get(g:, 'cursor_cli_model', '')
  let l:fmt = get(g:, 'cursor_cli_output_format', 'stream-json')
  if l:fmt !=# 'stream-json'
    let l:fmt = 'stream-json'
  endif

  " Optional: stdbuf wrapper if you want extra forcing of line buffering
  let l:stdbuf = get(g:, 'cursor_cli_force_stdbuf', '')

  if !empty(l:stdbuf)
    let l:args = [l:stdbuf, '-oL', '-eL', l:command, '--print', '--output-format', l:fmt]
  else
    let l:args = [l:command, '--print', '--output-format', l:fmt]
  endif

  if !empty(l:model)
    call extend(l:args, ['--model', l:model])
  endif
  call add(l:args, a:prompt)

  " Create/open result buffer
  let l:open_cmd = get(g:, 'cursor_cli_open', 'botright split')
  let l:height = get(g:, 'cursor_cli_height', 15)
  execute l:open_cmd
  execute 'resize ' . l:height

  let l:bufnr = cursor_cli#create_result_buffer('Stream', "Cursor AI working...\n\n", 'enew')

  let l:start_time = localtime()

  " KEY: pty=true for streaming flush
  let l:jobid = jobstart(l:args, {
        \ 'pty': v:true,
        \ 'stdout_buffered': v:false,
        \ 'stderr_buffered': v:false,
        \ 'on_stdout': function('cursor_cli#_on_stdout'),
        \ 'on_stderr': function('cursor_cli#_on_stderr'),
        \ 'on_exit': function('cursor_cli#_on_exit'),
        \ })

  if l:jobid <= 0
    call cursor_cli#_append_to_buf(l:bufnr, ["\n❌ Failed to start cursor-agent job.\n"])
    return -1
  endif

  let s:jobs[l:jobid] = {
        \ 'bufnr': l:bufnr,
        \ 'start_time': l:start_time,
        \ 'partial': '',
        \ 'seen_text': 0,
        \ 'final_result': '',
        \ 'done': 0,
        \ }

  call cursor_cli#_set_buf_var(l:bufnr, 'cursor_cli_jobid', l:jobid)
  call cursor_cli#_append_to_buf(l:bufnr, ["(job " . l:jobid . ")\n\n"])

  echo "Cursor AI streaming... (job " . l:jobid . ")"
  return l:jobid
endfunction

" Cancel an active streaming job
function! cursor_cli#cancel(jobid) abort
  if !has_key(s:jobs, a:jobid)
    echohl WarningMsg
    echo "No active Cursor job " . a:jobid
    echohl None
    return
  endif
  call jobstop(a:jobid)
  echo "Stopped Cursor job " . a:jobid
endfunction

" -------------------------------------------------------------------
" Parsing helpers
" -------------------------------------------------------------------
function! cursor_cli#parse_cursor_output(lines, fmt) abort
  if a:fmt ==# 'text' || empty(a:fmt)
    return join(a:lines, "\n")
  endif

  if a:fmt ==# 'json'
    let l:raw = join(a:lines, "\n")
    try
      let l:json = json_decode(l:raw)
      if type(l:json) == v:t_dict && has_key(l:json, 'result')
        return l:json.result
      endif
    catch
    endtry
    return ""
  endif

  if a:fmt ==# 'stream-json'
    for l:line in a:lines
      if l:line =~# '"type":"result"'
        try
          let l:json = json_decode(l:line)
          if has_key(l:json, 'result')
            return l:json.result
          endif
        catch
        endtry
      endif
    endfor

    let l:parts = []
    for l:line in a:lines
      let l:texts = cursor_cli#_extract_text_from_stream_line(l:line)
      if !empty(l:texts)
        call extend(l:parts, l:texts)
      endif
    endfor
    return join(l:parts, '')
  endif

  return join(a:lines, "\n")
endfunction

function! cursor_cli#_extract_text_from_stream_line(line) abort
  let l:out = []
  if a:line !~# '^\s*{'
    return l:out
  endif

  try
    let l:json = json_decode(a:line)
  catch
    return l:out
  endtry

  if type(l:json) != v:t_dict || !has_key(l:json, 'type')
    return l:out
  endif

  if l:json.type ==# 'assistant'
    if has_key(l:json, 'message') && type(l:json.message) == v:t_dict
      if has_key(l:json.message, 'content') && type(l:json.message.content) == v:t_list
        for l:item in l:json.message.content
          if type(l:item) == v:t_dict && has_key(l:item, 'text')
            call add(l:out, l:item.text)
          endif
        endfor
      endif
    endif
  endif

  return l:out
endfunction

" -------------------------------------------------------------------
" Job callbacks (Neovim)
" -------------------------------------------------------------------
function! cursor_cli#_on_stdout(jobid, data, event) abort
  if !has_key(s:jobs, a:jobid)
    return
  endif

  let l:st = s:jobs[a:jobid]
  if l:st.done
    return
  endif

  for l:chunk in a:data
    if l:chunk ==# ''
      continue
    endif

    " If a PTY is used, some CLIs may send \r carriage returns
    let l:chunk = substitute(l:chunk, "\r", "", "g")

    " Debug raw chunks if requested
    if get(g:, 'cursor_cli_debug_raw', 0)
      call cursor_cli#_append_to_buf(l:st.bufnr, ["\nRAW: " . l:chunk . "\n"])
    endif

    " stream-json should be one JSON object per line; handle cases where
    " Neovim delivers multiple lines in one chunk.
    let l:lines = split(l:chunk, "\n")
    for l:line in l:lines
      if l:line ==# ''
        continue
      endif
      call cursor_cli#_consume_stream_line(a:jobid, l:line)
    endfor
  endfor
endfunction

function! cursor_cli#_consume_stream_line(jobid, line) abort
  if !has_key(s:jobs, a:jobid)
    return
  endif
  let l:st = s:jobs[a:jobid]

  if a:line !~# '^\s*{'
    " Non-JSON: append raw (useful for errors / warnings)
    call cursor_cli#_append_to_buf(l:st.bufnr, [a:line . "\n"])
    return
  endif

  try
    let l:json = json_decode(a:line)
  catch
    " If JSON decode fails, show raw so you can debug
    call cursor_cli#_append_to_buf(l:st.bufnr, [a:line . "\n"])
    return
  endtry

  if type(l:json) != v:t_dict || !has_key(l:json, 'type')
    return
  endif

  " First meaningful event clears placeholder
  if !l:st.seen_text
    let l:st.seen_text = 1
    call cursor_cli#_replace_buf(l:st.bufnr, [""])
  endif

  if l:json.type ==# 'result'
    if has_key(l:json, 'result')
      let l:st.final_result = l:json.result
      let l:st.done = 1
      call cursor_cli#_replace_buf(l:st.bufnr, split(l:st.final_result, "\n"))
      call cursor_cli#_append_to_buf(l:st.bufnr, ["\n"])
    endif
    return
  endif

  if l:json.type ==# 'assistant'
    let l:texts = cursor_cli#_extract_text_from_stream_line(a:line)
    if !empty(l:texts)
      call cursor_cli#_append_to_buf(l:st.bufnr, l:texts)
    endif
    return
  endif
endfunction

function! cursor_cli#_on_stderr(jobid, data, event) abort
  if !has_key(s:jobs, a:jobid)
    return
  endif
  let l:st = s:jobs[a:jobid]
  for l:line in a:data
    if l:line ==# ''
      continue
    endif
    call cursor_cli#_append_to_buf(l:st.bufnr, ["\n[stderr] " . l:line . "\n"])
  endfor
endfunction

function! cursor_cli#_on_exit(jobid, code, event) abort
  if !has_key(s:jobs, a:jobid)
    return
  endif

  let l:st = s:jobs[a:jobid]
  let l:duration = localtime() - l:st.start_time

  if a:code != 0 && empty(l:st.final_result)
    call cursor_cli#_append_to_buf(l:st.bufnr, ["\n❌ Cursor AI exited with code " . a:code . " after " . l:duration . "s\n"])
  elseif empty(l:st.final_result) && !l:st.done
    call cursor_cli#_append_to_buf(l:st.bufnr, ["\n(ended after " . l:duration . "s)\n"])
  else
    call cursor_cli#_append_to_buf(l:st.bufnr, ["\n\n✅ Done (" . l:duration . "s)\n"])
  endif

  call remove(s:jobs, a:jobid)
  echo "✅ Cursor AI finished (job " . a:jobid . ", " . l:duration . "s)"
endfunction

" -------------------------------------------------------------------
" Buffer helpers
" -------------------------------------------------------------------
function! cursor_cli#create_result_buffer(name, content, ...) abort
  let l:how = a:0 > 0 ? a:1 : 'split'

  if l:how !=# 'enew'
    execute l:how . ' __Cursor' . a:name . '__'
  else
    execute 'enew'
    execute 'file __Cursor' . a:name . '__'
  endif

  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal wrap
  setlocal linebreak
  setlocal filetype=markdown

  %delete _
  call setline(1, split(a:content, '\n'))
  normal! gg

  return bufnr('%')
endfunction

function! cursor_cli#_append_to_buf(bufnr, lines) abort
  if !bufexists(a:bufnr)
    return
  endif

  let l:win = bufwinid(a:bufnr)
  if l:win != -1
    call win_execute(l:win, 'setlocal modifiable')
    call win_execute(l:win, 'silent! keepjumps $')
    call win_execute(l:win, 'call append(line("$"), ' . string(a:lines) . ')')
    call win_execute(l:win, 'silent! keepjumps $')
    call win_execute(l:win, 'setlocal nomodifiable')
  else
    call setbufvar(a:bufnr, '&modifiable', 1)
    call appendbufline(a:bufnr, '$', a:lines)
    call setbufvar(a:bufnr, '&modifiable', 0)
  endif
endfunction

function! cursor_cli#_replace_buf(bufnr, lines) abort
  if !bufexists(a:bufnr)
    return
  endif
  let l:win = bufwinid(a:bufnr)
  if l:win != -1
    call win_execute(l:win, 'setlocal modifiable')
    call win_execute(l:win, '%delete _')
    call win_execute(l:win, 'call setline(1, ' . string(a:lines) . ')')
    call win_execute(l:win, 'silent! keepjumps gg')
    call win_execute(l:win, 'setlocal nomodifiable')
  else
    call setbufvar(a:bufnr, '&modifiable', 1)
    call setbufline(a:bufnr, 1, a:lines)
    let l:lnum = len(a:lines) + 1
    while l:lnum <= line('$', a:bufnr)
      call deletebufline(a:bufnr, l:lnum)
    endwhile
    call setbufvar(a:bufnr, '&modifiable', 0)
  endif
endfunction

function! cursor_cli#_set_buf_var(bufnr, name, value) abort
  if bufexists(a:bufnr)
    call setbufvar(a:bufnr, a:name, a:value)
  endif
endfunction

" -------------------------------------------------------------------
" Context helpers
" -------------------------------------------------------------------
function! cursor_cli#get_file_context() abort
  let l:context = ""
  if expand('%') != ""
    let l:filetype = expand('%:e')
    let l:filename = expand('%:t')
    let l:context = printf(" (Context: working on %s file %s)", l:filetype, l:filename)
  endif
  return l:context
endfunction

function! cursor_cli#create_prompt_with_context(base_prompt) abort
  let l:context = cursor_cli#get_file_context()
  return a:base_prompt . l:context
endfunction
