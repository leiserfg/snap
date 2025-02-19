(module snap.view.input {require {size snap.view.size
                                  tbl snap.common.tbl
                                  buffer snap.common.buffer
                                  window snap.common.window
                                  register snap.common.register}})

(fn layout [config]
  "Creates the input layout"
  (let [{: width : height : row : col} (config.layout)]
    {:width (if config.has-views (math.floor (* width size.view-width)) width)
     :height 1
     :row (- (+ row height) size.padding)
     : col
     :focusable true}))

(defn create [config]
  "Creates the input view"
  (let [bufnr (buffer.create)
        layout (layout config)
        winnr (window.create bufnr layout)]
    (vim.api.nvim_buf_set_option bufnr :buftype :prompt)
    (vim.fn.prompt_setprompt bufnr config.prompt)
    (vim.api.nvim_command :startinsert)

    (fn get-filter []
      (let [contents (tbl.first (vim.api.nvim_buf_get_lines bufnr 0 1 false))]
        (if contents (contents:sub (+ (length config.prompt) 1)) "")))

    ;; Track exit
    (var exited false)

    (fn on-exit []
      (when (not exited)
        (set exited true)
        (config.on-exit)))

    (fn on-enter [type]
      (config.on-enter type)
      (config.on-exit))

    (fn on-next []
      (config.on-next)
      (config.on-exit))

    (fn on-tab []
      (config.on-select-toggle)
      (config.on-next-item))

    (fn on-shifttab []
      (config.on-select-toggle)
      (config.on-prev-item))

    (fn on-ctrla []
      (config.on-select-all-toggle))

    (fn on_lines []
      (config.on-update (get-filter)))

    (fn on_detach []
      (register.clean bufnr))

    ;; Enter and exit
    ;; e.g. we want to support opening in splits etc
    (register.buf-map bufnr [:n :i] [:<CR>] on-enter)
    (register.buf-map bufnr [:n :i] [:<C-q>] on-next)
    (register.buf-map bufnr [:n :i] [:<C-x>] (partial on-enter "split"))
    (register.buf-map bufnr [:n :i] [:<C-v>] (partial on-enter "vsplit"))
    (register.buf-map bufnr [:n :i] [:<C-t>] (partial on-enter "tab"))
    (register.buf-map bufnr [:n :i] [:<Esc> :<C-c>] on-exit)

    ;; Selection
    (register.buf-map bufnr [:n :i] [:<Tab>] on-tab)
    (register.buf-map bufnr [:n :i] [:<S-Tab>] on-shifttab)
    (register.buf-map bufnr [:n :i] [:<C-a>] on-ctrla)

    ;; Up & down are reversed when view is revered
    (register.buf-map bufnr [:n :i] (if config.reverse [:<Down> :<C-j>] [:<Up> :<C-k>]) config.on-prev-item)
    (register.buf-map bufnr [:n :i] (if config.reverse [:<Up> :<C-k>]  [:<Down> :<C-j>]) config.on-next-item)
    (register.buf-map bufnr [:n :i] [:<C-p>] config.on-prev-item)
    (register.buf-map bufnr [:n :i] [:<C-n>] config.on-next-item)

    ;; Up & down are reversed when view is revered
    (register.buf-map bufnr [:n :i] (if config.reverse [:<PageDown>] [:<PageUp>]) config.on-prev-page)
    (register.buf-map bufnr [:n :i] (if config.reverse [:<PageUp>]  [:<PageDown>]) config.on-next-page)
    (register.buf-map bufnr [:n :i] [:<C-b>] config.on-prev-page)
    (register.buf-map bufnr [:n :i] [:<C-f>] config.on-next-page)

    ;; Views
    (register.buf-map bufnr [:n :i] [:<C-d>] config.on-viewpagedown)
    (register.buf-map bufnr [:n :i] [:<C-u>] config.on-viewpageup)

    (vim.api.nvim_command
      (string.format
        "autocmd! WinLeave <buffer=%s> %s"
        bufnr
        (register.get-autocmd-call (tostring bufnr) on-exit)))

    (vim.api.nvim_buf_attach bufnr false {: on_lines : on_detach})

    {: bufnr : winnr}))
