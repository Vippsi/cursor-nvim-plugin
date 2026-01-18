" ===================================================================
" Cursor CLI Plugin - Autoload Functions (Streaming)
" Provides Cursor IDE-like functionality using the Cursor CLI
"
" Updated to support TRUE streaming into a Vim buffer using jobstart()
" with on_stdout callbacks + --output-format stream-json.
"
" Works best in Neovim (jobstart callbacks). For Vim8 you can adapt to job_start().
"
" Optional globals:
"   let g:cursor_cli_command = 'cursor-agent'
"   let g:cursor_cli_model = 'opus-4.5-thinking'  " or 'auto', etc.
"   let g:cursor_cli_output_format = 'stream-json' " 'stream-json' | 'json' | 'text'
"   let g:cursor_cli_open = 'botright split'       " where to open results
"   let g:cursor_cli_height = 15                   " split height
"
" ===================================================================

let s:jobs = {}

" Check if cursor CLI is available
function! cursor_cli#available() abort
  let l:command = get(g:, 'cursor_cli_command', 'cursor-agent')
  return executable(l:command) || executable('cursor-agent')
endfunction

" -------------------------------------------------------------------
" Public entrypoint (non-streaming, reliable parsing)
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
    echo "Streaming mode requires Neovim (jobstart() + on_stdout)."
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

  " Streaming expects stream-json
  if l:fmt !=# 'stream-json'
    let l:fmt = 'stream-json'
  endif

  let l:args = [l:command, '--print', '--output-format', l:fmt]
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

  " Start job
  let l:start_time = localtime()

  let l:jobid = jobstart(l:args, {
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

" Cancel an active streaming job (if you want a command mapping)
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
    " Try final result line first
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

    " Fallback: concatenate assistant text
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
  " Returns a list of text fragments extracted from a single JSONL line
  let l:out = []
  if a:line !~# '^\s*{'
    return l:out
  endif

  try
    let l:json = json_decode(a:line)
  catch
    return l:out
  endtry

  " Cursor CLI stream-json commonly emits objects with "type"
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

  " data is a list of lines; the last element can be '' due to newline handling
  for l:chunk in a:data
    if l:chunk ==# ''
      continue
    endif

    " Handle partial lines (just in case)
    let l:line = l:st.partial . l:chunk
    let l:st.partial = ''

    " stream-json should be one JSON object per line.
    " If we ever receive concatenated lines, split on \n.
    let l:lines = split(l:line, "\n")
    if len(l:lines) > 1
      " keep last as partial if it doesn't look complete
      for l:i in range(0, len(l:lines)-1)
        call cursor_cli#_consume_stream_line(a:jobid, l:lines[l:i])
      endfor
    else
      call cursor_cli#_consume_stream_line(a:jobid, l:line)
    endif
  endfor
endfunction

function! cursor_cli#_consume_stream_line(jobid, line) abort
  if !has_key(s:jobs, a:jobid)
    return
  endif
  let l:st = s:jobs[a:jobid]

  " Try parse JSON
  if a:line !~# '^\s*{'
    " Non-JSON: append raw (useful for debugging)
    call cursor_cli#_append_to_buf(l:st.bufnr, [a:line . "\n"])
    return
  endif

  try
    let l:json = json_decode(a:line)
  catch
    " Not parseable yet
    call cursor_cli#_append_to_buf(l:st.bufnr, [a:line . "\n"])
    return
  endtry

  if type(l:json) != v:t_dict || !has_key(l:json, 'type')
    return
  endif

  " If we haven't printed anything yet, remove the "working..." placeholder
  if !l:st.seen_text
    let l:st.seen_text = 1
    call cursor_cli#_replace_buf(l:st.bufnr, [""])
  endif

  if l:json.type ==# 'result'
    if has_key(l:json, 'result')
      let l:st.final_result = l:json.result
      let l:st.done = 1

      " Replace buffer with final result (clean)
      call cursor_cli#_replace_buf(l:st.bufnr, split(l:st.final_result, "\n"))
      call cursor_cli#_append_to_buf(l:st.bufnr, ["\n"])
    endif
    return
  endif

  " Stream assistant text content
  if l:json.type ==# 'assistant'
    let l:texts = cursor_cli#_extract_text_from_stream_line(a:line)
    if !empty(l:texts)
      " Append without adding extra newlines unless the model includes them
      call cursor_cli#_append_to_buf(l:st.bufnr, l:texts)
    endif
    return
  endif

  " Other event types: ignore (or append for debugging)
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
    " Sometimes you might not get a result object; keep what streamed
    call cursor_cli#_append_to_buf(l:st.bufnr, ["\n(ended after " . l:duration . "s)\n"])
  else
    call cursor_cli#_append_to_buf(l:st.bufnr, ["\n\n✅ Done (" . l:duration . "s)\n"])
  endif

  " Remove from job table
  call remove(s:jobs, a:jobid)

  echo "✅ Cursor AI finished (job " . a:jobid . ", " . l:duration . "s)"
endfunction

" -------------------------------------------------------------------
" Buffer helpers
" -------------------------------------------------------------------
function! cursor_cli#create_result_buffer(name, content, ...) abort
  " a:1 optionally indicates how to create/open the buffer.
  " If passed 'enew', uses current window.
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

  " Clear buffer and set content
  %delete _
  call setline(1, split(a:content, '\n'))
  normal! gg

  return bufnr('%')
endfunction

function! cursor_cli#_append_to_buf(bufnr, lines) abort
  if !bufexists(a:bufnr)
    return
  endif

  " Append at end; keep cursor at end
  let l:win = bufwinid(a:bufnr)
  if l:win != -1
    call win_execute(l:win, 'setlocal modifiable')
    call win_execute(l:win, 'silent! keepjumps $')
    call win_execute(l:win, 'call append(line("$"), ' . string(a:lines) . ')')
    call win_execute(l:win, 'silent! keepjumps $')
    call win_execute(l:win, 'setlocal nomodifiable')
  else
    " Buffer not visible; still append
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
    " best effort: delete extra lines if any
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
" Context helpers (unchanged)
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
