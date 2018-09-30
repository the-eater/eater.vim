syntax clear
syntax region eaterlogLine start=/^/ end=/\(\n|\$\)/ contains=eaterlogNr,eaterlogTime,eaterlogLevel
syntax region eaterlogLevel start=/\[/ end=/\]/ contains=eaterlogError,eaterlogWarning,eaterlogDebug nextgroup=eaterlogMsg skipwhite oneline contained
syntax region eaterlogTime start=/\[/ end=/\]/ contains=eaterlogTimeM nextgroup=eaterlogLevel skipwhite oneline contained
syntax region eaterlogNr start=/\[/ end=/\]/ contains=eaterlogNumber nextgroup=eaterlogTime skipwhite oneline contained

syntax match eaterlogNumber contained /[0-9]\+/
syntax match eaterlogTimeM contained /[0-9]\+:[0-9]\+:[0-9]\+/
syntax keyword eaterlogError contained ERROR
syntax keyword eaterlogError contained ERR
syntax keyword eaterlogWarning contained WARNING
syntax keyword eaterlogWarning contained  WARN
syntax keyword eaterlogDebug contained  DEBUG
syntax keyword eaterlogDebug contained  DBG


hi link eaterlogLevel NonText
hi link eaterlogTime NonText
hi link eaterlogNr NonText
hi link eaterlogNumber Number
hi link eaterlogTimeM Statement
hi link eaterlogError ErrorMsg
hi link eaterlogWarning WarningMsg
hi link eaterlogDebug Question