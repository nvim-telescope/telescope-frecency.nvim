function! frecency#FrecencyComplete(findstart, base)
  if a:findstart
    let line = getline('.')
    " don't complete if there's already a completed `:tag:` in line
    if count(line, ":") >= 2
      return -3
    endif

    " locate the start of the tag
    let start = col('.') - 1
    while start > 0 && line[start -1] != ':'
	let start -= 1
    endwhile

    return start
  else
    if pumvisible() && !empty(v:completed_item)
      return ''
    end

    let l:workspace_tags = luaeval("require'telescope'.extensions.frecency.get_workspace_tags()")
    let matches = []
    for ws_tag in l:workspace_tags
      if ":" .. ws_tag =~ '^:' .. a:base
        call add(matches, ws_tag)
      endif
    endfor

    return len(matches) != 0 ? matches : ''
  end
endfunction


  " lua require'telescope'.extensions.frecency.completefunc(action)
  " lua require'telescope'.extensions.frecency.completefunc(res)
  " require'telescope._extensions.frecency.db_client'.autocmd_handler(vim.fn.expand('<amatch>'))
