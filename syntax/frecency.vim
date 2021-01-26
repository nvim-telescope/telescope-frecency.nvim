if exists('b:current_syntax') | finish|  endif

syntax match WorkspaceFilter /:.\{-}:/
hi def link WorkspaceFilter TelescopeQueryFilter

