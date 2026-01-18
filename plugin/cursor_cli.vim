" plugin/cursor_cli.vim
" ===================================================================
" Cursor CLI Plugin for Neovim
" Commands + UX wrappers around autoload/cursor_cli.vim
"
" Version: 1.1 (streaming)
" ===================================================================

if exists('g:loaded_cursor_cli') || !has('nvim')
  finish
endif
let g:loaded_cursor_cli = 1

" Configuration defaults (safe)
let g:cursor_cli_command = get(g:, 'cursor_cli_command', 'cursor-agent')
let g:cursor_cli_model = get(g:, 'cursor_cli_model', 'opus-4.5-thinking')
let g:cursor_cli_output_format = get(g:, 'cursor_cli_output_format', 'stream-json')

let g:cursor_cli_open = get(g:, 'cursor_cli_open', 'botright split')
let g:cursor_cli_height = get(g:, 'cursor_cli_height', 15)
let g:cursor_cli_debug_raw = get(g:, 'cursor_cli_debug_raw', 0)

" -------------------------------------------------------------------
" Helpers
" -------------------------------------------------------------------
function! s:prompt_with_context(question) abort
  return cursor_cli#create_prompt_with_context(a:question)
endfunction

function! s:run(prompt) abort
  if get(g:, 'cursor_cli_output_format', 'stream-json') ==# 'stream-json'
    return cursor_cli#exec_stream(a:prompt)
  endif

  let l:resp = cursor_cli#exec(a:prompt)
  if !empty(l:resp)
    call cursor_cli#create_result_buffer('Chat', l:resp)
  endif
  return 0
endfunction

function! s:get_visual_or_line(first, last) abort
  if a:first == a:last && col("'<") == col("'>")
    return [getline('.'), line('.'), line('.')]
  endif
  return [join(getline(a:first, a:last), "\n"), a:first, a:last]
endfunction

" -------------------------------------------------------------------
" Main Functions
" -------------------------------------------------------------------
function! CursorChat() abort
  let l:q = input('💬 Ask Cursor AI: ')
  if empty(l:q)
    return
  endif
  call s:run(s:prompt_with_context(l:q))
endfunction

function! CursorExplain() range abort
  let l:code = join(getline(a:firstline, a:lastline), "\n")
  if empty(trim(l:code))
    echo "No code selected to explain"
    return
  endif

  let l:prompt = printf("Explain this %s code from %s:\n\n%s", expand('%:e'), expand('%:t'), l:code)
  call s:run(s:prompt_with_context(l:prompt))
endfunction

function! CursorReview() abort
  let l:file = expand('%:p')
  if empty(l:file) || !filereadable(l:file)
    echo "No readable file to review"
    return
  endif

  let l:file_content = join(readfile(l:file), "\n")
  let l:prompt = printf(
        \ "Review this %s code for best practices, bugs, and improvements:\n\nFile: %s\n\n%s",
        \ expand('%:e'), expand('%:t'), l:file_content
        \ )
  call s:run(s:prompt_with_context(l:prompt))
endfunction

function! CursorGenerate() abort
  let l:current_line = getline('.')
  let l:default = l:current_line =~ '^\s*[#/"\*].*' ? l:current_line : ''
  let l:instruction = input('🚀 Generate code: ', l:default)
  if empty(l:instruction)
    return
  endif

  let l:prompt = printf(
        \ "Generate %s code for: %s\n\nFile context: %s (%s)\n\nProvide only the code without explanations:",
        \ expand('%:e'), l:instruction, expand('%:t'), &filetype
        \ )

  " Force non-streaming json so we can insert the final exact output
  let l:old_fmt = get(g:, 'cursor_cli_output_format', 'stream-json')
  let g:cursor_cli_output_format = 'json'
  let l:result = cursor_cli#exec(s:prompt_with_context(l:prompt))
  let g:cursor_cli_output_format = l:old_fmt

  if !empty(l:result)
    call append(line('.'), split(l:result, "\n"))
    echo printf("✅ Generated %d lines of code!", len(split(l:result, "\n")))
  endif
endfunction

function! CursorEdit() range abort
  let l:instruction = input('✏️  Edit instruction: ')
  if empty(l:instruction)
    return
  endif

  let [l:original_code, l:start_line, l:end_line] = s:get_visual_or_line(a:firstline, a:lastline)

  let l:prompt = printf(
        \ "Edit this %s code according to the instruction.\n\nFile: %s\nInstruction: %s\n\nOriginal code:\n%s\n\nProvide only the edited code:",
        \ expand('%:e'), expand('%:t'), l:instruction, l:original_code
        \ )

  let l:old_fmt = get(g:, 'cursor_cli_output_format', 'stream-json')
  let g:cursor_cli_output_format = 'json'
  let l:result = cursor_cli#exec(s:prompt_with_context(l:prompt))
  let g:cursor_cli_output_format = l:old_fmt

  if empty(l:result)
    echo "❌ No edit returned"
    return
  endif

  call cursor_cli#create_result_buffer('Diff', "ORIGINAL:\n" . l:original_code . "\n\nEDITED:\n" . l:result, 'vnew')
  echo "Apply changes? (y/n): "
  let l:choice = nr2char(getchar())

  if l:choice ==# 'y'
    execute l:start_line . ',' . l:end_line . 'delete'
    call append(l:start_line - 1, split(l:result, "\n"))
    echo "✅ Changes applied!"
  else
    silent! bwipeout __CursorDiff__
    echo "❌ Changes discarded"
  endif
endfunction

function! CursorOptimize() range abort
  let l:code = join(getline(a:firstline, a:lastline), "\n")
  if empty(trim(l:code))
    echo "No code selected to optimize"
    return
  endif

  let l:prompt = printf(
        \ "Optimize this %s code for better performance and readability:\n\nFile: %s\n\nOriginal code:\n%s\n\nProvide only the optimized code:",
        \ expand('%:e'), expand('%:t'), l:code
        \ )

  let l:old_fmt = get(g:, 'cursor_cli_output_format', 'stream-json')
  let g:cursor_cli_output_format = 'json'
  let l:result = cursor_cli#exec(s:prompt_with_context(l:prompt))
  let g:cursor_cli_output_format = l:old_fmt

  if empty(l:result)
    echo "❌ No optimization returned"
    return
  endif

  call cursor_cli#create_result_buffer('Optimization', "ORIGINAL:\n" . l:code . "\n\nOPTIMIZED:\n" . l:result, 'vnew')
  echo "Apply optimization? (y/n): "
  let l:choice = nr2char(getchar())

  if l:choice ==# 'y'
    execute a:firstline . ',' . a:lastline . 'delete'
    call append(a:firstline - 1, split(l:result, "\n"))
    echo "✅ Code optimized!"
  else
    silent! bwipeout __CursorOptimization__
    echo "❌ Optimization discarded"
  endif
endfunction

function! CursorFix() range abort
  let l:code = join(getline(a:firstline, a:lastline), "\n")
  if empty(trim(l:code))
    echo "No code selected to fix"
    return
  endif

  let l:prompt = printf(
        \ "Fix any errors or bugs in this %s code:\n\nFile: %s\n\nCode with issues:\n%s\n\nProvide only the corrected code:",
        \ expand('%:e'), expand('%:t'), l:code
        \ )

  let l:old_fmt = get(g:, 'cursor_cli_output_format', 'stream-json')
  let g:cursor_cli_output_format = 'json'
  let l:result = cursor_cli#exec(s:prompt_with_context(l:prompt))
  let g:cursor_cli_output_format = l:old_fmt

  if empty(l:result)
    echo "❌ No fix returned"
    return
  endif

  call cursor_cli#create_result_buffer('Fix', "ORIGINAL:\n" . l:code . "\n\nFIXED:\n" . l:result, 'vnew')
  echo "Apply fix? (y/n): "
  let l:choice = nr2char(getchar())

  if l:choice ==# 'y'
    execute a:firstline . ',' . a:lastline . 'delete'
    call append(a:firstline - 1, split(l:result, "\n"))
    echo "✅ Code fixed!"
  else
    silent! bwipeout __CursorFix__
    echo "❌ Fix discarded"
  endif
endfunction

function! CursorRefactor() range abort
  echo "Refactor options:"
  echo "1. Extract function"
  echo "2. Rename variable"
  echo "3. Add comments"
  echo "4. Simplify logic"
  echo "5. Custom instruction"

  let l:choice = nr2char(getchar())
  let l:instruction = ""

  if l:choice ==# '1'
    let l:instruction = 'Extract this code into a well-named function'
  elseif l:choice ==# '2'
    let l:instruction = 'Rename variables to be more descriptive'
  elseif l:choice ==# '3'
    let l:instruction = 'Add helpful comments to explain the code'
  elseif l:choice ==# '4'
    let l:instruction = 'Simplify the logic while maintaining functionality'
  elseif l:choice ==# '5'
    let l:instruction = input('Custom refactor instruction: ')
    if empty(l:instruction)
      return
    endif
  else
    echo "Invalid choice"
    return
  endif

  let l:code = join(getline(a:firstline, a:lastline), "\n")
  if empty(trim(l:code))
    echo "No code selected"
    return
  endif

  let l:prompt = printf(
        \ "Refactor this %s code: %s\n\nFile: %s\n\nOriginal code:\n%s\n\nProvide only the refactored code:",
        \ expand('%:e'), l:instruction, expand('%:t'), l:code
        \ )

  let l:old_fmt = get(g:, 'cursor_cli_output_format', 'stream-json')
  let g:cursor_cli_output_format = 'json'
  let l:result = cursor_cli#exec(s:prompt_with_context(l:prompt))
  let g:cursor_cli_output_format = l:old_fmt

  if empty(l:result)
    echo "❌ No refactor returned"
    return
  endif

  call cursor_cli#create_result_buffer('Refactor', "ORIGINAL:\n" . l:code . "\n\nREFACTORED:\n" . l:result, 'vnew')
  echo "Apply refactor? (y/n): "
  let l:apply = nr2char(getchar())

  if l:apply ==# 'y'
    execute a:firstline . ',' . a:lastline . 'delete'
    call append(a:firstline - 1, split(l:result, "\n"))
    echo "✅ Code refactored!"
  else
    silent! bwipeout __CursorRefactor__
    echo "❌ Refactor discarded"
  endif
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

function! CursorStop() abort
  let l:jobid = getbufvar(bufnr('%'), 'cursor_cli_jobid', -1)
  if l:jobid == -1
    echo "No Cursor job associated with this buffer"
    return
  endif
  call cursor_cli#cancel(l:jobid)
endfunction

" -------------------------------------------------------------------
" Commands
" -------------------------------------------------------------------
command! CursorChat call CursorChat()
command! -range CursorEdit <line1>,<line2>call CursorEdit()
command! CursorGenerate call CursorGenerate()
command! -range CursorExplain <line1>,<line2>call CursorExplain()
command! CursorReview call CursorReview()
command! -range CursorOptimize <line1>,<line2>call CursorOptimize()
command! -range CursorFix <line1>,<line2>call CursorFix()
command! -range CursorRefactor <line1>,<line2>call CursorRefactor()

command! CursorStatus echo cursor_cli#available() ? "✅ Cursor CLI available" : "❌ Cursor CLI not found"
command! CursorTest call CursorTest()

command! -nargs=1 CursorStream call cursor_cli#exec_stream(<q-args>)
command! CursorStop call CursorStop()
