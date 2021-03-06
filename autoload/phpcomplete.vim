" Vim completion script
" Language:	PHP
" Maintainer:	Mikolaj Machowski ( mikmach AT wp DOT pl )
" Maintainer:	Shawn Biddle ( shawn AT shawnbiddle DOT com )
"
"	OPTIONS:
"
"		let g:phpcomplete_relax_static_constraint = 1/0  [default 0]
"			Enables completion for non-static methods when completing for static context (::).
"			This generates E_STRICT level warning, but php calls these methods nontheless.
"
"		let g:phpcomplete_complete_for_unknown_classes = 1/0 [default 1]
"			Enables completion of variables and functions in "everything under the sun" fassion
"			when completing for an instance or static class context but the code can't tell the class
"			or locate the file that it lives in.
"			The completion list generated this way is only filtered by the completion base
"			and generally not much more accurate then simple keyword completion.
"
"		let g:phpcomplete_min_num_of_chars_for_namespace_completion = n [default 1]
"			This option controls the number of characters the user needs to type before
"			the tags will be searched for namespaces and classes in typed out namespaces in
"			"use ..." context. Setting this to 0 is not recommended because that means the code
"			have to scan every tag, and vim's taglist() function runs extremly slow with a
"			"match everything" pattern.
"
"	TODO:
"	- Switching to HTML (XML?) completion (SQL) inside of phpStrings
"	- allow also for XML completion <- better do html_flavor for HTML
"	  completion
"	- outside of <?php?> getting parent tag may cause problems. Heh, even in
"	  perfect conditions GetLastOpenTag doesn't cooperate... Inside of
"	  phpStrings this can be even a bonus but outside of <?php?> it is not the
"	  best situation

if !exists('g:phpcomplete_relax_static_constraint')
	let g:phpcomplete_relax_static_constraint = 0
endif

if !exists('g:phpcomplete_complete_for_unknown_classes')
	let g:phpcomplete_complete_for_unknown_classes = 1
endif

if !exists('g:phpcomplete_min_num_of_chars_for_namespace_completion')
	let g:phpcomplete_min_num_of_chars_for_namespace_completion = 1
endif

function! phpcomplete#CompletePHP(findstart, base) " {{{
	if a:findstart
		unlet! b:php_menu
		" Check if we are inside of PHP markup
		let pos = getpos('.')
		let phpbegin = searchpairpos('<?', '', '?>', 'bWn',
				\ 'synIDattr(synID(line("."), col("."), 0), "name") =~? "string\|comment"')
		let phpend   = searchpairpos('<?', '', '?>', 'Wn',
				\ 'synIDattr(synID(line("."), col("."), 0), "name") =~? "string\|comment"')

		if phpbegin == [0,0] && phpend == [0,0]
			" We are outside of any PHP markup. Complete HTML
			let htmlbegin = htmlcomplete#CompleteTags(1, '')
			let cursor_col = pos[2]
			let base = getline('.')[htmlbegin : cursor_col]
			let b:php_menu = htmlcomplete#CompleteTags(0, base)
			return htmlbegin
		else
			" locate the start of the word
			let line = getline('.')
			let start = col('.') - 1
			let curline = line('.')
			let compl_begin = col('.') - 2
			while start >= 0 && line[start - 1] =~ '[\\a-zA-Z_0-9\x7f-\xff$]'
				let start -= 1
			endwhile
			let b:compl_context = getline('.')[0:compl_begin]
			return start

			" We can be also inside of phpString with HTML tags. Deal with
			" it later (time, not lines).
		endif

	endif
	" If exists b:php_menu it means completion was already constructed we
	" don't need to do anything more
	if exists("b:php_menu")
		return b:php_menu
	endif

	if !exists('g:php_builtin_functions')
		call phpcomplete#LoadData()
	endif

	" a:base is very short - we need context
	if exists("b:compl_context")
		let context = b:compl_context
		unlet! b:compl_context
	endif

	let scontext = substitute(context, '\$\?[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*$', '', '')

	if context =~? '^\s*use\s\+'
		return phpcomplete#CompleteUse(a:base)
	endif

	if scontext =~ '\(\s*new\|extends\)\s\+$'
		return phpcomplete#CompleteClassName(a:base)
	elseif scontext =~ '\(->\|::\)$'
		" {{{
		" Get name of the class
		let classname = phpcomplete#GetClassName(scontext)

		" Get location of class definition, we have to iterate through all
		if classname != ''
			let classlocation = phpcomplete#GetClassLocation(classname)
		else
			let classlocation = ''
		endif

		if classlocation != ''
			if classlocation == 'VIMPHP_BUILTINOBJECT' && has_key(g:php_builtin_classes, classname)
				return phpcomplete#CompleteBuiltInClass(scontext, classname, a:base)
			endif

			if filereadable(classlocation)
				let classfile = readfile(classlocation)
				let classcontent = ''
				let classcontent .= "\n".phpcomplete#GetClassContents(classfile, classname)
				let sccontent = split(classcontent, "\n")
				let classAccess = expand('%:p') == fnamemodify(classlocation, ':p') ? '\\(public\\|private\\|protected\\)' : 'public'

				return phpcomplete#CompleteUserClass(scontext, a:base, sccontent, classAccess)
			endif
		endif

		return phpcomplete#CompleteUnknownClass(a:base, scontext)
	 " }}}
	endif

	if a:base =~ '^\$'
		return phpcomplete#CompleteVariable(a:base)
	else
		return phpcomplete#CompleteGeneral(a:base)
	endif
endfunction
" }}}

function! phpcomplete#CompleteUse(base) " {{{
	" completes builtin class names regadless of g:phpcomplete_min_num_of_chars_for_namespace_completion
	" completes namespaces from tags
	"   * requires patched ctags
	" completes classnames from tags within the already typed out namespace using the "namespace" field of tags
	"   * requires patched ctags

	let res = []
	if a:base =~? '^\'
		let leading_slash = '\'
		let base = substitute(a:base, '^\', '', '')
	else
		let leading_slash = ''
		let base = a:base
	endif

	let namespace_match_pattern  = substitute(base, '\\', '\\\\', 'g')
	let classname_match_pattern = matchstr(base, '[^\\]\+$')
	let namespace_for_class = substitute(substitute(namespace_match_pattern, '\\\\', '\\', 'g'), '\\*'.classname_match_pattern.'$', '', '')

	if len(namespace_match_pattern) >= g:phpcomplete_min_num_of_chars_for_namespace_completion
		if len(classname_match_pattern) >= g:phpcomplete_min_num_of_chars_for_namespace_completion
			let tags = taglist('^\('.namespace_match_pattern.'\|'.classname_match_pattern.'\)')
		else
			let tags = taglist('^'.namespace_match_pattern)
		endif

		for tag in tags
			if tag.kind ==? 'n' && tag.name =~? '^'.namespace_match_pattern
				call add(res, {'word': leading_slash.tag.name, 'kind': 'n', 'menu': tag.filename, 'info': tag.filename })
			elseif has_key(tag, 'namespace') && tag.kind ==? 'c' && tag.namespace ==? namespace_for_class
				call add(res, {'word': leading_slash.namespace_for_class.'\'.tag.name, 'kind': 'c', 'menu': tag.filename, 'info': tag.filename })
			endif
		endfor
	endif

	let builtin_classnames = filter(keys(copy(g:php_builtin_classnames)), 'v:val =~? "^'.classname_match_pattern.'"')
	for classname in builtin_classnames
		call add(res, {'word': '\'.classname, 'kind': 'c'})
	endfor

	return res
endfunction
" }}}

function! phpcomplete#CompleteGeneral(base) " {{{
	let res = []
	" Complete everything else -
	"  + functions,  DONE
	"  + keywords of language DONE
	"  + defines (constant definitions), DONE
	"  + extend keywords for predefined constants, DONE
	"  + classes (after new), DONE
	"  + limit choice after -> and :: to funcs and vars DONE

	" Internal solution for finding functions in current file.
	let file = getline(1, '$')
	call filter(file,
				\ 'v:val =~ "function\\s\\+&\\?[a-zA-Z_\\x7f-\\xff][a-zA-Z_0-9\\x7f-\\xff]*\\s*("')
	let jfile = join(file, ' ')
	let int_values = split(jfile, 'function\s\+')
	let int_functions = {}
	for i in int_values
		let f_name = matchstr(i,
					\ '^&\?\zs[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\ze')
		let f_args = matchstr(i,
					\ '^&\?[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\s*(\zs.\{-}\ze)\_s*\({\|$\)')
		let int_functions[f_name.'('] = f_args.')'
	endfor


	" Prepare list of functions from tags file
	let ext_functions = {}
	let ext_constants = {}
	let ext_classes   = {}
	let tags = taglist('^'.a:base)
	for tag in tags
		if tag.kind ==? 'f'
			let item = tag.name
			if has_key(tag, 'signature')
				let prototype = tag.signature[1:-2]
			else
				let prototype = matchstr(tag.cmd,
							\ 'function\s\+&\?[^[:space:]]\+\s*(\s*\zs.\{-}\ze\s*)\s*{\?')
			endif
			let ext_functions[item.'('] = prototype.') - '.tag['filename']
		elseif tag.kind ==? 'd'
			let ext_constants[tag.name] = ''
		elseif tag.kind ==? 'c'
			let ext_classes[tag.name] = ''
		endif
	endfor

	" All functions
	call extend(int_functions, ext_functions)
	call extend(int_functions, g:php_builtin_functions)

	" Internal solution for finding constants in current file
	let file = getline(1, '$')
	call filter(file, 'v:val =~ "define\\s*("')
	let jfile = join(file, ' ')
	let int_values = split(jfile, 'define\s*(\s*')
	let int_constants = {}
	for i in int_values
		let c_name = matchstr(i, '\(["'']\)\zs[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\ze\1')
		if c_name != ''
			let int_constants[c_name] = '' " c_value
		endif
	endfor

	" Prepare list of constants from built-in constants
	let builtin_constants = {}
	for [constant, info] in items(g:php_constants)
		if constant =~# '^'.a:base
			let builtin_constants[constant] = info
		endif
	endfor

	" Treat keywords as constants
	for [constant, info] in items(g:php_keywords)
		if constant =~? '^'.a:base
			let ext_constants[constant] = info
		endif
	endfor

	" All constants
	call extend(int_constants, ext_constants)

	let all_values = {}

	" One big dictionary of functions
	call extend(all_values, int_functions)

	" Add constants from the current file
	call extend(all_values, int_constants)

	" Add built-in constants
	call extend(all_values, builtin_constants)

	" Add external classes
	call extend(all_values, ext_classes)

	"add built-in classes
	call extend(all_values, g:php_builtin_classnames)

	for m in sort(keys(all_values))
		if m =~ '^'.a:base
			call add(res, m)
		endif
	endfor

	let int_list = res

	let final_list = []
	for i in int_list
		if has_key(int_functions, i)
			let final_list +=
						\ [{'word':i,
						\	'info':i.int_functions[i],
						\	'menu':int_functions[i],
						\	'kind':'f'}]
		elseif has_key(ext_classes, i) || has_key(g:php_builtin_classnames, i)
			let final_list += [{'word':i, 'kind':'c'}]
		elseif has_key(int_constants, i) || has_key(builtin_constants, i)
			let final_list += [{'word':i, 'kind': 'd'}]
		else
			let final_list += [{'word':i}]
		endif
	endfor

	return final_list
endfunction
" }}}

function! phpcomplete#CompleteUnknownClass(base, scontext) " {{{
	let res = []

	if g:phpcomplete_complete_for_unknown_classes != 1
		return []
	endif

	if a:base =~ '^\$'
		let adddollar = '$'
	else
		let adddollar = ''
	endif

	let file = getline(1, '$')

	" Internal solution for finding object properties in current file.
	if a:scontext =~ '::'
		let variables = filter(deepcopy(file),
					\ 'v:val =~ "^\\s*\\(static\\|static\\s\\+\\(public\\|var\\)\\|\\(public\\|var\\)\\s\\+static\\)\\s\\+\\$"')
	elseif a:scontext =~ '->'
		let variables = filter(deepcopy(file),
					\ 'v:val =~ "^\\s*\\(public\\|var\\)\\s\\+\\$"')
	endif
	let jvars = join(variables, ' ')
	let svars = split(jvars, '\$')
	let int_vars = {}
	for i in svars
		let c_var = matchstr(i,
					\ '^\zs[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\ze')
		if c_var != ''
			let int_vars[adddollar.c_var] = ''
		endif
	endfor

	" Internal solution for finding functions in current file.
	call filter(deepcopy(file),
			\ 'v:val =~ "function\\s\\+&\\?[a-zA-Z_\\x7f-\\xff][a-zA-Z_0-9\\x7f-\\xff]*\\s*("')
	let jfile = join(file, ' ')
	let int_values = split(jfile, 'function\s\+')
	let int_functions = {}
	for i in int_values
		let f_name = matchstr(i,
				\ '^&\?\zs[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\ze')
		let f_args = matchstr(i,
				\ '^&\?[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\s*(\zs.\{-}\ze)\_s*\({\|$\)')

		let int_functions[f_name.'('] = f_args.')'
	endfor

	" collect external functions from tags
	let ext_functions = {}
	let tags = taglist('^'.substitute(a:base, '^\$', '', ''))
	for tag in tags
		if tag.kind ==? 'f'
			let item = tag.name
			if has_key(tag, 'signature')
				let prototype = tag.signature[1:-2]
			else
				let prototype = matchstr(tag.cmd,
						\ 'function\s\+&\?[^[:space:]]\+\s*(\s*\zs.\{-}\ze\s*)\s*{\?')
			endif
			let ext_functions[item.'('] = prototype.') - '.tag['filename']
		endif
	endfor

	let all_values = {}
	call extend(all_values, int_functions)
	call extend(all_values, ext_functions)
	call extend(all_values, int_vars) " external variables are already in
	call extend(all_values, g:php_builtin_object_functions)

	for m in sort(keys(all_values))
		if m =~ '\(^\|::\)'.a:base
			call add(res, m)
		endif
	endfor

	let start_list = res

	let final_list = []
	for i in start_list
		if has_key(int_vars, i)
			let class = ' '
			if all_values[i] != ''
				let class = i.' class '
			endif
			let final_list += [{'word':i, 'info':class.all_values[i], 'kind':'v'}]
		else
			let final_list +=
					\ [{'word':substitute(i, '.*::', '', ''),
					\	'info':i.all_values[i],
					\	'menu':all_values[i],
					\	'kind':'f'}]
		endif
	endfor
	return final_list
endfunction
" }}}

function! phpcomplete#CompleteVariable(base) " {{{
	let res = []

	" Internal solution for current file.
	let file = getline(1, '$')
	let jfile = join(file, ' ')
	let int_vals = split(jfile, '\ze\$')
	let int_vars = {}
	for i in int_vals
		if i =~ '^\$[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\s*=\s*new'
			let val = matchstr(i,
						\ '^\$[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*')
		else
			let val = matchstr(i,
						\ '^\$[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*')
		endif
		if val != ''
			let int_vars[val] = ''
		endif
	endfor

	call extend(int_vars, g:php_builtin_vars)

	" ctags has support for PHP, use tags file for external variables
	let ext_vars = {}
	let tags = taglist('^'.substitute(a:base, '^\$', '', ''))
	for tag in tags
		if tag.kind ==? 'v'
			let item = tag.name
			let m_menu = ''
			if tag.cmd =~ tag['name'].'\s*=\s*new\s\+'
				let m_menu = matchstr(tag.cmd,
							\ '=\s*new\s\+\zs[a-zA-Z_0-9\x7f-\xff]\+\ze')
			endif
			let ext_vars['$'.item] = m_menu
		endif
	endfor

	call extend(int_vars, ext_vars)

	for m in sort(keys(int_vars))
		if m =~ '^\'.a:base
			call add(res, m)
		endif
	endfor

	let int_list = res

	let int_dict = []
	for i in int_list
		if int_vars[i] != ''
			let class = ' '
			if int_vars[i] != ''
				let class = i.' class '
			endif
			let int_dict += [{'word':i, 'info':class.int_vars[i], 'menu':int_vars[i], 'kind':'v'}]
		else
			let int_dict += [{'word':i, 'kind':'v'}]
		endif
	endfor

	return int_dict
endfunction
" }}}

function! phpcomplete#CompleteClassName(base) " {{{
	let res = []
	" Complete class name
	" Internal solution for finding classes in current file.
	let file = getline(1, '$')
	call filter(file,
			\ 'v:val =~? "class\\s\\+[a-zA-Z_\\x7f-\\xff][a-zA-Z_0-9\\x7f-\\xff]*\\s*"')

	let fnames = join(map(tagfiles(), 'escape(v:val, " \\#%")'))
	let jfile = join(file, ' ')
	let int_values = split(jfile, 'class\s\+')
	let int_classes = {}
	for i in int_values
		let c_name = matchstr(i, '^[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*')
		if c_name != ''
			let int_classes[c_name] = ''
		endif
	endfor

	" Prepare list of classes from tags file
	let ext_classes = {}
	let tags = taglist('^'.a:base)
	for tag in tags
		if tag.kind ==? 'c'
			let ext_classes[tag.name] = ''
		endif
	endfor

	let classes = sort(keys(int_classes))
	let classes += sort(keys(ext_classes))
	let classes += keys(g:php_builtin_classes)

	for m in classes
		if m =~ '^'.a:base
			call add(res, m)
		endif
	endfor

	let final_menu = []
	for i in res
		let menu = ''
		if (has_key(g:php_builtin_classes, i) && has_key(g:php_builtin_classes[i].methods, '__construct'))
			let menu = g:php_builtin_classes[i]['methods']['__construct']['signature']
		endif
		let final_menu += [{'word':i, 'kind':'c', 'menu':menu}]
	endfor

	return final_menu
endfunction
" }}}

function! phpcomplete#CompleteUserClass(scontext, base, sccontent, classAccess) " {{{
	let final_list = []
	let res  = []
	let res2 = []

	" limit based on context to static or normal methods
	if a:scontext =~ '::'
		if g:phpcomplete_relax_static_constraint == 1
			let functions = filter(deepcopy(a:sccontent),
						\ 'v:val =~ "^\\s*\\(static\\s\\+\\(' . a:classAccess . '\\)*\\|\\(' . a:classAccess . '\\s\\+\\)*static\\)\\s\\+function"')
			let functions += filter(deepcopy(a:sccontent),
						\ 'v:val =~ "^\\s*\\(' . a:classAccess . '\\s\\+\\)*function"')
		else
			let functions = filter(deepcopy(a:sccontent),
						\ 'v:val =~ "^\\s*\\(static\\s\\+\\(' . a:classAccess . '\\)*\\|\\(' . a:classAccess . '\\s\\+\\)*static\\)\\s\\+function"')
		endif
	elseif a:scontext =~ '->'
		let functions = filter(deepcopy(a:sccontent),
					\ 'v:val =~ "^\\s*\\(' . a:classAccess . '\\s\\+\\)*function"')
	endif

	let sfuncs = split(join(functions, ' '), 'function\s\+')
	let c_functions = {}
	for i in sfuncs
		let f_name = matchstr(i,
					\ '^&\?\zs[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\ze')
		let f_args = matchstr(i,
					\ '^&\?[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\s*(\zs.\{-}\ze)\_s*\({\|$\)')
		if f_name != ''
			let c_functions[f_name.'('] = f_args
		endif
	endfor

	" limit based on context to static or normal attributes
	if a:scontext =~ '::'
		let variables = filter(deepcopy(a:sccontent),
					\ 'v:val =~ "^\\s*\\(static\\|static\\s\\+\\(' . a:classAccess . '\\|var\\)\\|\\(' . a:classAccess . '\\|var\\)\\s\\+static\\)\\s\\+\\$"')
	elseif a:scontext =~ '->'
		let variables = filter(deepcopy(a:sccontent),
					\ 'v:val =~ "^\\s*\\(' . a:classAccess . '\\|var\\)\\s\\+\\$"')
	endif
	let jvars = join(variables, ' ')
	let svars = split(jvars, '\$')
	let c_variables = {}
	for i in svars
		let c_var = matchstr(i,
					\ '^\zs[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\ze')
		if c_var != ''
			let c_variables[c_var] = ''
		endif
	endfor

	let constants = filter(deepcopy(a:sccontent),
				\ 'v:val =~ "^\\s*const\\s\\+"')

	let jcons = join(constants, ' ')
	let scons = split(jcons, 'const')

	let c_constants = {}
	for i in scons
		let c_con = matchstr(i,
					\ '^\s*\zs[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\ze')
		if c_con != ''
			let c_constants[c_con] = ''
		endif
	endfor

	let all_values = {}
	call extend(all_values, c_functions)
	call extend(all_values, c_variables)
	call extend(all_values, c_constants)

	for m in sort(keys(all_values))
		if m =~ '^'.a:base && m !~ '::'
			call add(res, m)
		elseif m =~ '::'.a:base
			call add(res2, m)
		endif
	endfor

	let start_list = res + res2

	let final_list = []
	for i in start_list
		if has_key(c_variables, i)
			let class = ' '
			if all_values[i] != ''
				let class = i.' class '
			endif
			let final_list +=
						\ [{'word': a:scontext =~ '::' ? '$'.i : i,
						\	'info':class.all_values[i],
						\	'menu':class.all_values[i],
						\	'kind':'v'}]
		elseif has_key(c_constants, i)
			let final_list +=
						\ [{'word':i,
						\	'info':i.all_values[i],
						\	'menu':all_values[i],
						\	'kind':'d'}]
		else
			let final_list +=
						\ [{'word':substitute(i, '.*::', '', ''),
						\	'info':i.all_values[i].')',
						\	'menu':all_values[i].')',
						\	'kind':'f'}]
		endif
	endfor

	return final_list
endfunction
" }}}

function! phpcomplete#CompleteBuiltInClass(scontext, classname, base) " {{{
	let class_info = g:php_builtin_classes[a:classname]
	let res = []
	let search = matchstr(a:base, '\(->\|::\)\zs.*$\ze')
	if a:scontext =~ '->$' " complete for everything instance related
		" methods
		for [method_name, method_info] in items(class_info.methods)
			if a:base == '' || method_name =~? '^'.a:base
				call add(res, {'word':method_name.'(', 'kind': 'f', 'menu': method_info.signature, 'info': method_info.signature })
			endif
		endfor
		" properties
		for [property_name, property_info] in items(class_info.properties)
			if a:base == '' || property_name =~? '^'.a:base
				call add(res, {'word':property_name, 'kind': 'v', 'menu': property_info.type, 'info': property_info.type })
			endif
		endfor
	elseif a:scontext =~ '::$' " complete for everything static
		" methods
		for [method_name, method_info] in items(class_info.static_methods)
			if a:base == '' || method_name =~? '^'.a:base
				call add(res, {'word':method_name.'(', 'kind': 'f', 'menu': method_info.signature, 'info': method_info.signature })
			endif
		endfor
		" properties
		for [property_name, property_info] in items(class_info.static_properties)
			if a:base == '' || property_name =~? '^'.a:base
				call add(res, {'word':property_name, 'kind': 'v', 'menu': property_info.type, 'info': property_info.type })
			endif
		endfor
		" constants
		for [constant_name, constant_info] in items(class_info.constants)
			if a:base == '' || constant_name =~? '^'.a:base
				call add(res, {'word':constant_name, 'kind': 'd', 'menu': constant_info, 'info': constant_info})
			endif
		endfor
	endif
	return res
endfunction
" }}}

function! phpcomplete#GetClassName(scontext) " {{{
	" Get class name
	" Class name can be detected in few ways:
	" @var $myVar class
	" in the same line (php 5.4 (new Class)-> syntax)
	" line above
	" or line in tags file

	let class_name_pattern = '[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*'

	if a:scontext =~? '\$this->' || a:scontext =~? '\(self\|static\)::'
		let i = 1
		while i < line('.')
			let line = getline(line('.')-i)

			" Don't complete self:: or $this if outside of a class
			" (assumes correct indenting)
			if line =~ '^}'
				return ''
			endif

			if line =~? '^\s*abstract\s*class'
				let classname = matchstr(line, '^\s*abstract\s*class\s*\zs'.class_name_pattern.'\ze')
				return classname
			elseif line =~? '^\s*class'
				let classname = matchstr(line, '^\s*class\s*\zs'.class_name_pattern.'\ze')
				return classname
			else
				let i += 1
				continue
			endif
		endwhile
	elseif a:scontext =~? '(\s*new\s\+'.class_name_pattern.'\s*)->'
		let classname = matchstr(a:scontext, 'new\s\+\zs'.class_name_pattern.'\ze')
		return classname
	else
		" check Constant lookup
		let constant_object = matchstr(a:scontext, '\zs'.class_name_pattern.'\ze::')
		if constant_object != ''
			return constant_object
		endif

		"extract the variable name from the context
		let object = matchstr(a:scontext, '\zs'.class_name_pattern.'\ze\(::\|->\)')

		" scan the file backwards from the current line
		let i = 1
		while i < line('.')
			let line = getline(line('.')-i)

			" do in-file lookup of $var = new Class
			if line =~# '^\s*\$'.object.'\s*=\s*new\s\+'.class_name_pattern
				let classname = matchstr(line, '\$'.object.'\s*=\s*new \zs'.class_name_pattern.'\ze')
				return classname
			endif

			" in file lookup for /* @var $foo Class */
			if line =~# '@var\s\+\$'.object.'\s\+'.class_name_pattern
				let classname = matchstr(line, '@var\s\+\$'.object.'\s\+\zs'.class_name_pattern.'\ze')
				return classname
			endif

			" in-file lookup for Class::getInstance()
			if line =~# '^\s*\$'.object.'\s*=&\?\s*\s\+'.class_name_pattern.'::getInstance\+'
				let classname = matchstr(line, '\$'.object.'\s*=&\?\s*\zs'.class_name_pattern.'\ze::getInstance\+')
				return classname
			endif

			" do in-file lookup for static method invocation of a built-in class, like: $d = DateTime::createFromFormat()
			if line =~# '^\s*\$'.object.'\s*=&\?\s*\s\+'.class_name_pattern.'::[a-zA-Z_0-9\x7f-\xff]\+('
				let classname  = matchstr(line, '^\s*\$'.object.'\s*=&\?\s*\s\+\zs'.class_name_pattern.'\ze::[a-zA-Z_0-9\x7f-\xff]\+(')
				let methodname = matchstr(line, '^\s*\$'.object.'\s*=&\?\s*\s\+'.class_name_pattern.'::\zs[a-zA-Z_0-9\x7f-\xff]\+\ze(')
				if has_key(g:php_builtin_classes, classname) && has_key(g:php_builtin_classes[classname].static_methods, methodname)
					return g:php_builtin_classes[classname].static_methods[methodname].return_type
				else
					break
				endif
			endif

			" in-file lookup for typehinted function arguments
			if line =~# '[fF][uU][nN][cC][tT][iI][oO][nN]\s*[^(]\+\s*(.\{-}'.class_name_pattern.'\s\+\$'.object
				let f_args = matchstr(line, '^&\?[a-zA-Z_\x7f-\xff][a-zA-Z_0-9\x7f-\xff]*\s*(\zs.\{-}\ze)\_s*\({\|$\)')
				let args = split(f_args, '\s*\zs,\ze\s*')
				for arg in args
					if arg =~# '\$'.object.'\(,\|$\)'
						let classname = matchstr(arg, '\s*\zs'.class_name_pattern.'\ze\s\+\$'.object)
						return classname
					endif
				endfor
			endif

			let i += 1
		endwhile

		" OK, first way failed, now check tags file(s)
		let tags = taglist('^'.substitute(object, '^\$', '', ''))
		if len(tags) == 0
			return
		else
			for tag in tags
				if tag.kind ==? 'v' && tag.cmd =~? '=\s*new\s\+\zs'.class_name_pattern.'\ze'
					let classname = matchstr(tag.cmd, '=\s*new\s\+\zs'.class_name_pattern.'\ze')
					return classname
				endif
			endfor
		endif
	endif
endfunction
" }}}

function! phpcomplete#GetClassLocation(classname) " {{{
	" Check classname may be name of built in object
	if has_key(g:php_builtin_classes, a:classname)
		return 'VIMPHP_BUILTINOBJECT'
	endif

	" do in-file lookup for class definition
	let i = 1
	while i < line('.')
		let line = getline(line('.')-i)
		if line =~ '^\s*class ' . a:classname  . '\(\s\+\|$\)'
			return expand('%:p')
		else
			let i += 1
			continue
		endif
	endwhile
	" Get class location
	let tags = taglist('^'.a:classname.'$')
	for tag in tags
		if tag.kind ==? 'c'
			return tag.filename
		endif
	endfor

endfunction
" }}}

function! phpcomplete#GetClassContents(file, name) " {{{
	let cfile = join(a:file, "\n")
	" We use new buffer and (later) normal! because
	" this is the most efficient way. The other way
	" is to go through the looong string looking for
	" matching {}

	" remember the window we started at
	let phpcomplete_original_window = winnr()

	below 1new
	0put =cfile
	let endline = search('{')
	call search('class\s\+'.a:name)
	let cfline = line('.')
	let content = join(getline(cfline, endline),"\n")
	" Catch extends
	if content =~ 'extends'
		let extends_class = matchstr(content, 'class\_s\+'.a:name.'\_s\+extends\_s\+\zs[a-zA-Z_0-9\x7f-\xff]\+\ze')
	else
		let extends_class = ''
	endif
	call search('{')
	normal! %

	let classcontent = join(getline(cfline, line('.')), "\n")

	bw! %

	" go back to original window
	exe phpcomplete_original_window.'wincmd w'

	if extends_class != ''
		let classlocation = phpcomplete#GetClassLocation(extends_class)
		if filereadable(classlocation)
			let classfile = readfile(classlocation)
			let classcontent .= "\n".phpcomplete#GetClassContents(classfile, extends_class)
		endif
	endif

	return classcontent
endfunction
" }}}

function! phpcomplete#LoadData() " {{{
" Keywords/reserved words, all other special things
" Later it is possible to add some help to values, or type of
" defined variable
runtime! misc/php_keywords.vim

" Built in functions
" You can regenerate this list with the bin/extract_functions.php
runtime! misc/php_builtin_functions.vim

" Built in class methods
" You can regenerate this list with the bin/extract_functions.php
runtime! misc/php_builtin_classes.vim

" When the classname not found or found but the tags dosen't contain that
" class we will try to complate any method of any builtin class. To speed up
" that lookup we compile a 'ClassName::MethodName':'info' dictionary from the
" builtin class informations
let g:php_builtin_object_functions = {}
" When completing for 'everyting imaginable' (no class context, not a
" variable) we need a list of built-in classes in a format of {'classname':''}
" for performance reasons we precompile this too
let g:php_builtin_classnames = {}
for [classname, class_info] in items(g:php_builtin_classes)
	let g:php_builtin_classnames[classname] = ''
	for [method_name, method_info] in items(class_info.methods)
		let g:php_builtin_object_functions[classname.'::'.method_name.'('] = method_info.signature
	endfor
	for [method_name, method_info] in items(class_info.static_methods)
		let g:php_builtin_object_functions[classname.'::'.method_name.'('] = method_info.signature
	endfor
endfor

" Constants defined in PHP and it's extension
" You can regenerate this list with the bin/extract_functions.php
runtime! misc/php_constants.vim


" Add control structures (they are outside regular pattern of PHP functions)
let php_control = {
			\ 'include(': 'string filename | resource',
			\ 'include_once(': 'string filename | resource',
			\ 'require(': 'string filename | resource',
			\ 'require_once(': 'string filename | resource',
			\ }
call extend(g:php_builtin_functions, php_control)


" Built-in variables " {{{
let g:php_builtin_vars ={
			\ '$GLOBALS':'',
			\ '$_SERVER':'',
			\ '$_GET':'',
			\ '$_POST':'',
			\ '$_COOKIE':'',
			\ '$_FILES':'',
			\ '$_ENV':'',
			\ '$_REQUEST':'',
			\ '$_SESSION':'',
			\ '$HTTP_SERVER_VARS':'',
			\ '$HTTP_ENV_VARS':'',
			\ '$HTTP_COOKIE_VARS':'',
			\ '$HTTP_GET_VARS':'',
			\ '$HTTP_POST_VARS':'',
			\ '$HTTP_POST_FILES':'',
			\ '$HTTP_SESSION_VARS':'',
			\ '$php_errormsg':'',
			\ '$this':'',
			\ }
" }}}

endfunction
" }}}
" vim: foldmethod=marker:noexpandtab:ts=4:sts=4:tw=4
