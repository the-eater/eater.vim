if exists("g:eater")
	finish
endif

let eater = {}
let eater.plugins = {}

let eater.path = expand('<sfile>:p')
let eater.logs = []
let eater.log_buffer = v:false
let eater.can_purge_plugins = v:false

function! eater.show_logs() dict
	let log_buffer = bufnr('eater#logs', 1)
	let self.log_buffer = log_buffer

	call setbufvar(log_buffer, '&buftype', 'nofile')
	call setbufvar(log_buffer, '&bufhidden', 'hide')
	call setbufvar(log_buffer, '&modifiable', 0)
	call setbufvar(log_buffer, '&swapfile', 0)
	call setbufvar(log_buffer, '&filetype', 'eaterlog')
	let last_line = getbufvar(log_buffer, 'eater_last_line', 0)
	let i = last_line

	if !bufloaded(log_buffer)
		let buf_selector = '<buffer=' . log_buffer . '>'
		exe 'au' 'BufReadCmd' buf_selector 'call eater.show_logs()'
		let l:curr = win_getid()
		exe '10split'
		exe 'buffer' log_buffer
		call win_gotoid(l:curr)
		return
	endif

	call setbufvar(log_buffer, '&modifiable', 1)
	while i < len(self.logs)
		let log = self.logs[i]
		let line = '[' . i . '][' . strftime('%H:%M:%S', log.ts) . '][' . log.level . '] ' . log.msg
		if has('nvim')
			call nvim_buf_set_lines(log_buffer, i, i, 0, [line])
		else
			call appendbufline(log_buffer, i, line)
		endif

		let i += 1
	endwhile

	call setbufvar(log_buffer, '&modifiable', 0)
	call setbufvar(log_buffer, 'eater_last_line', i)
endfunction

function! eater.log(msg, ...) dict
	let level = s:argv(a:000, 0, 'INFO')
	let meta = s:argv(a:000, 1, {})
	let msg = a:msg

	if type(msg) == type([])
		let msg = function('printf', msg)()
	endif

	call add(g:eater.logs, { 'ts': localtime(), 'msg': msg, 'level': level, 'meta': meta })

	if self.log_buffer
		call self.show_logs()
	endif
endfunction

function! eater.init(...) dict
	let self.runtime_dir = s:argv(a:000, 0, fnamemodify(g:eater.path, ':h:h:p'))
	let self.state_dir = self.runtime_dir . '/eater/state'
	call self.log('runtime_dir: ' . self.runtime_dir)
	call self.log('path: ' . self.path)

	if !isdirectory(self.state_dir)
		call mkdir(self.state_dir, 'p')
	endif

	command! -nargs=+ Plugin call g:eater.add_plugin(<args>)
	command! -nargs=+ Runtime call g:eater.cmd_runtime(<args>)

	exe 'runtime!' 'eater/plugins.vim'

	delcommand Runtime
	delcommand Plugin

	call self.check_plugins()

	exe 'runtime!' 'eater/keymap.vim'
	exe 'runtime!' 'eater/settings.vim'
endfunction

function! s:argv(args, arg, ...)
	if len(a:args) > a:arg
		return a:args[a:arg]
	elseif a:0 > 0
		return a:1
	else
		throw "Missing optional argument " . a:arg
	endif
endfunction

function! eater.add_plugin(name, ...) dict
	let options = s:argv(a:000, 0, {})

	let name = self.normalize_plugin_name(a:name)

	if a:name ==# name
		call self.log('Added plugin ' . a:name, 'DEBUG')
	else
		call self.log('Added plugin ' . a:name . ' normalized to ' . name, 'DEBUG')
	endif

	let self.plugins[name] = { "options": options, "from": a:name, "handle": name }
endfunction

function! eater.normalize_plugin_name(name) dict
	let name = a:name

	if name =~ '^[A-Za-z-_]\+$'
		return 'git::https://github.com/vim-scripts/' . name . '.git'
	elseif name =~ "^[^/]\\+/[^/]\\+$"
		return 'git::https://github.com/' . name . '.git'
	elseif name[0:4] == 'git::' || name[0:5] == 'file::' || name[0:8] == 'runtime::'
		return name
	elseif name =~ "\\.git$"
		return 'git::' . name
	elseif filereadable(name) and !isdirectory(name)
		return 'file::' . name
	elseif isdirectory(name)
		return 'runtime::' . name
	else
		call self.log('Uncertain about plugin name "' . name . '" assumed git, please prepend with git:: or runtime::', 'WARN')
		return 'git::' . name
	endif
endfunction

function! eater.resolve_dir(name) dict
	return fnamemodify(a:name, ':h:p')
endfunction

function! eater.check_plugins() dict
	let playbook = []
	let plugin_state_file = self.state_dir . '/plugins.json'
	let self.plugin_state = {}

	if filereadable(plugin_state_file)
		let json_blob = readfile(plugin_state_file)
		let self.plugin_state = json_decode(join(json_blob, "\n"))
	endif

	let curr_plugins = keys(self.plugins)
	let state_plugins = {}

	for plugin in keys(self.plugin_state)
		let state_plugins[plugin] = v:true
	endfor

	for plugin in curr_plugins
		if !has_key(self.plugin_state, plugin)
			call add(playbook, ['install', plugin])
		else
			call remove(state_plugins, plugin)
			let self.plugin_state[plugin].removed = v:false

			if get(self.plugins[plugin].options, 'frozen', v:false) != v:true
				let state_rev = get(self.plugin_state[plugin].options, 'rev', v:null)
				let curr_rev = get(self.plugins[plugin].options, 'rev', v:null)

				if state_rev ==# curr_rev
					continue
				endif

				call add(playbook, ['update', plugin])
			endif
		endif
	endfor

	for plugin in keys(state_plugins)
		if get(self.plugin_state[plugin], 'removed', v:false) != v:true
			call add(playbook, ['remove', plugin])
		else
			let self.can_purge_plugins = v:true
		endif
	endfor

	let self.plugin_playbook = playbook

	if len(playbook) > 0
		call self.log('Plugins have changed, run :PluginsUpdate[!] to update (actions: [' . join(map(deepcopy(playbook), { idx, item -> join(item, ' -> ') }), '], [') . '])', 'INFO')
		call self.show_logs()
	endif

	if self.can_purge_plugins == v:true
		Log 'There are plugins that can be purged, you can do this via :PluginsPurge'
	endif

	call self.init_plugins()
	call self.save_plugin_state()
endfunction

function eater.init_plugins() dict
	let rtplist = split(&runtimepath, ',')

	for plugin in values(self.plugin_state)
		if plugin.removed == v:true || plugin.installed == v:false
			continue
		endif

		if plugin.location == v:null
			continue
		endif

		let rtpath = plugin.location . '/'

		if has_key(plugin.options, 'rtp')
			let rtpath .= plugin.options.rtp . '/'
		endif

		call add(rtplist, simplify(rtpath))
	endfor

	call uniq(rtplist)

	let &runtimepath = join(rtplist, ',')
endfunction

function eater.update_plugins() dict
	for [action, plugin] in self.plugin_playbook
		let [method; name] = split(plugin, '::', 1)
		let name = join(name, '::')
		let plugin_state = {}

		call self.log(['running action %s for plugin %s', action, name], 'DEBUG')
		if action !=# 'remove'
			let plugin_state = self.plugins[plugin]
		else
			let plugin_state = self.plugin_state[plugin]
		endif

		let func_name = action . '_' . method . '_plugin'

		let res = v:null

		if has_key(self, func_name)
			let res = self[action . '_' . method . '_plugin'](name, plugin_state)
		endif

		if res != v:false
			call self['after_' . action . '_plugin'](plugin, plugin_state, res)
		endif
	endfor

	call self.save_plugin_state()
endfunction

function eater.after_remove_plugin(name, ...) dict
	let self.plugin_state[a:name].removed = v:true
endfunction

function eater.save_plugin_state() dict
	Log 'Writing plugin state to file', 'DEBUG'
	let blob = json_encode(self.plugin_state)
	let plugin_state_file = self.state_dir . '/plugins.json'
	call writefile([blob], plugin_state_file)
endfunction

function eater.after_install_plugin(name, plugin_state, location) dict
	let new_state = copy(a:plugin_state)
	call extend(new_state, { "installed": v:true, 'location': a:location, 'type': split(a:name, '::')[0] })
	let self.plugin_state[a:name] = new_state
endfunction

function eater.get_git_plugin_path(name) dict
	let matches = matchlist(a:name, '^\([a-zA-Z-_]\+@\|https\?://\)\([^:/]\+\)[:/]\([a-zA-Z_/\.-]\+\)$')

	if len(matches) == 0
		return v:false
	endif

	let git_path = matches[2] . '/' . matches[3]

	if git_path[-4:] == '.git'
		let git_path = git_path[:-5]
	endif

	return git_path
endfunction

function eater.install_git_plugin(name, options) dict
	let git_path = self.get_git_plugin_path(a:name)

	if git_path == v:false
		Log "Can't make sense from git url: " . a:name, 'ERROR'
		return v:false
	endif

	let cpath = self.state_dir . '/plugin/git/' . git_path

	if !isdirectory(cpath)
		let clone_cmd = 'git clone '

		if has_key(a:options, 'rev')
			let clone_cmd .= '-b ' . shellescape(a:options.rev) . ' '
		endif

		call system(clone_cmd . shellescape(a:name) . ' ' . shellescape(cpath))
	elseif has_key(a:options, 'deleted')
		call system('git -C ' . shellescape(cpath) . ' pull')
		if has_key(a:options, 'rev')
			call system('git -C ' . shellescape(cpath) . ' checkout ' . shellescape(a:options.rev))
		endif
	endif

	return cpath
endfunction

function eater.install_runtime_plugin(name, options) dict
	return a:name
endfunction

function eater.purge_plugins() dict
	for [name, plugin] in items(self.plugin_state)
		if has_key(plugin, 'removed') && plugin.removed == v:true
			Log ['purging %s', plugin.from]

			let func_name = 'purge_' . plugin.type . '_plugin'
			let success = v:true

			if has_key(self, func_name)
				let success = self[func_name](plugin)
			endif

			if success
				call remove(self.plugin_state, name)
			endif
		endif
	endfor

	call self.save_plugin_state()
endfunction

function eater.purge_git_plugin(plugin) dict
	if self.state_dir !=# a:plugin.location[:len(self.state_dir) - 1]
		Log ["Git plugin '%s' isn't located (%s) inside state_dir (%s), will not purge", a:plugin.from, a:plugin.location, self.state_dir], 'ERROR'
		return v:false
	endif

	call delete(a:plugin.location, 'rf')

	let parts = split(a:plugin.location[1 + len(self.state_dir):], '/')
	let i = len(parts) - 2
	let res = 0
	while i > 0 && res != -1
		let dirp = self.state_dir . '/' . join(parts[:i], '/')
		Log ['Trying to delete folder %s', dirp], 'DEBUG'
		let res = delete(dirp, 'd')
		let i -= 1
	endwhile

	return v:true
endfunction

function eater.cmd_update_plugins(bang) dict
	call self.update_plugins()

	if a:bang == '!'
		self.upgrade_plugins()
		self.purge_plugins()
	endif
endfunction

function eater.cmd_runtime(rpath, ...) dict
	call function(self.add_plugin, ['runtime::' . a:rpath] + a:000)()
endfunction

function! eater#init(...)
	call function(g:eater.init, a:000, g:eater)()
endfunction

command! -nargs=+ Log call g:eater.log(<args>)
command! ShowLog call g:eater.show_logs()
command! -bang PluginsUpdate call g:eater.cmd_update_plugins('<bang>')
command! PluginsPurge call g:eater.purge_plugins()
