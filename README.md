# Snap

A fast finder system for neovim >0.5.

## Demo

The following shows finding files and grepping in the large `gcc` codebase.

https://user-images.githubusercontent.com/51294/120878813-f958f600-c612-11eb-9730-deefd39fb36e.mov


## Installation

### With Packer

```
use { 'camspiers/snap' }
```

or with `fzy`:

```
use { 'camspiers/snap', rocks = {'fzy'}}
```

#### Semi-Optional Dependencies

To use the following `snap` components you need the specified dependencies, however not all coponents are needed, for example you should probably choose between `fzy` and `fzf` as your primary consumer.

| Component            | Dependency                        |
| -------------------- | --------------------------------- |
| `consumer.fzy`       | `fzy` via luarocks                |
| `consumer.fzf`       | `fzf` available on command line   |
| `producer.ripgrep.*` | `rg` available on commmand line   |
| `producer.fd.*`      | `fd` available on commmand line   |
| `producer.git.file`  | `git` available on commmand line  |
| `preview.*`          | `file` available on commmand line |

They are semi-optional because you can mix and match them depending on which technology you want to use.

## Basic Example

The following is a basic example to give a taste of the API. It creates a highly performant live grep `snap`.

```lua
snap.run {
  producer = snap.get'producer.ripgrep.vimgrep',
  select = snap.get'select.vimgrep'.select,
  multiselect = snap.get'select.vimgrep'.multiselect,
  views = {snap.get'preview.vimgrep'}
}
```

Or given this can easily create the ability to ripgrep your entire filesystem with a result for every character, you can set a reasonable upper limit to 10,000 matches:

```lua
snap.run {
  producer = snap.get'consumer.limit'(10000, snap.get'producer.ripgrep.vimgrep'),
  select = snap.get'select.vimgrep'.select,
  multiselect = snap.get'select.vimgrep'.multiselect,
  views = {snap.get'preview.vimgrep'}
}
```

## Usage

`snap` comes with inbuilt producers and consumers to enable easy creation of finders.

### Find Files

Uses built in `fzy` filter + score, and `ripgrep` for file finding.

```lua
snap.run {
  producer = snap.get'consumer.fzy'(snap.get'producer.ripgrep.file'),
  select = snap.get'select.file'.select,
  multiselect = snap.get'select.file'.multiselect,
  views = {snap.get'preview.file'}
}
```

or using `fzf`:

```lua
snap.run {
  producer = snap.get'consumer.fzf'(snap.get'producer.ripgrep.file'),
  select = snap.get'select.file'.select,
  multiselect = snap.get'select.file'.multiselect,
  views = {snap.get'preview.file'}
}
```

### Live Ripgrep

```lua
snap.run {
  producer = snap.get'producer.ripgrep.vimgrep',
  select = snap.get'select.vimgrep'.select,
  multiselect = snap.get'select.vimgrep'.multiselect,
  views = {snap.get'preview.vimgrep'}
}
```

### Find Buffers

```lua
snap.run {
  producer = snap.get'consumer.fzy'(snap.get'producer.vim.buffer'),
  select = snap.get'select.file'.select,
  multiselect = snap.get'select.file'.multiselect,
  views = {snap.get'preview.file'}
}
```

### Find Old Files

```lua
snap.run {
  producer = snap.get'consumer.fzy'(snap.get'producer.vim.oldfiles'),
  select = snap.get'select.file'.select,
  multiselect = snap.get'select.file'.multiselect,
  views = {snap.get'preview.file'}
}
```

### Find Git Files

```lua
snap.run {
  producer = snap.get'consumer.fzy'(snap.get'producer.git.file'),
  select = snap.get'select.file'.select,
  multiselect = snap.get'select.file'.multiselect,
  views = {snap.get'preview.file'}
}
```

### Key Bindings

#### Select

When a single item is selected, calls the provided `select` function with the cursor result as the selection.

When multiple items are selection, calls the provider `multiselect` function.

- `<CR>`

Alternatives:

- `<C-x>` opens in new split
- `<C-v>` opens in new vsplit
- `<C-t>` opens in new tab

#### Exit

Closes `snap`

- `<Esc>`
- `<C-c>`

#### Next

Move cursor to the next selection.

- `<Down>`
- `<C-n>`
- `<C-j>`

#### Previous

Move cursor to the previous selection.

- `<Up>`
- `<C-p>`
- `<C-k>`

#### Multiselect (enabled when `multiselect` is provided)

Add current cursor result to selection list.

- `<Tab>`

Remove current cursor result from selection list.

- `<S-Tab>`

Select all

- `<C-a>`

#### Results Page Down

Moves the results cursor down a page.

- `<C-b>`

#### Results Page Up

Moves the results cursor up a page.

- `<C-f>`

#### View Page Down

Moves the cursor of the first view down a page (if more than one exists).

- `<C-d>`

#### View Page Up

Moves the cursor of the first view up a page (if more than one exists).

- `<C-u>`

### Creating Mappings

`snap` registers no mappings, autocmds, or commands, and never will.

You can register your mappings in the following way:

```lua
local snap = require'snap'
snap.register.map({"n"}, {"<Leader>f"}, function ()
  snap.run {
    producer = snap.get'consumer.fzy'(snap.get'producer.ripgrep.file'),
    select = snap.get'select.file'.select,
    multiselect = snap.get'select.file'.multiselect
  }
end)
```

An exmaple that configures a variety of in-built snaps is available here:

https://gist.github.com/camspiers/686395ab3bda4a0d00684d72acc24c23


## How Snap Works

`snap` uses a non-blocking design to ensure the UI is always responsive to user input.

To achieve this it employs coroutines, and while that might be a little daunting, the following walk-through illustrates the primary concepts.

Our example's goal is to run the `ls` command, filter the results in response to input, and print the selected value.

### Producer

A producers API looks like this:

```typescript
type Producer = (request: Request) => yield<Yieldable>;
```

The producer is a function that takes a request and yields results (see below for the range of `Yieldable` types).

In the following `producer`, we run the `ls` command and progressively `yield` its output.

```lua
local snap = require'snap'
local io = snap.get'common.io'

-- Runs ls and yields lua tables containing each line
local function producer (request)
  -- Runs the slow-mode getcwd function
  local cwd = snap.sync(vim.fn.getcwd)
  -- Iterates ls commands output using snap.io.spawn
  for data, err, kill in io.spawn("ls", {}, cwd) do
    -- If the filter updates while the command is still running
    -- then we kill the process and yield nil
    if request.canceled() then
      kill()
      coroutine.yield(nil)
    -- If there is an error we yield nil
    elseif (err ~= "") then
      coroutine.yield(nil)
    -- If the data is empty we yield an empty table
    elseif (data == "") then
      coroutine.yield({})
    -- If there is data we split it by newline
    else
      coroutine.yield(vim.split(data, "\n", true))
    end
  end
end
```

### Consumer

A consumers type looks like this:

```typescript
type Consumer = (producer: Producer) => Producer;
```

A consumer is a function that takes a producer and returns a producer.

As our goal here is to filter, we iterate over our passed producer and only yield values that match `request.filter`.

```lua
-- Takes in a producer and returns a producer
local function consumer (producer)
  -- Return producer
  return function (request)
    -- Iterates over the producers results
    for results in snap.consume(producer, request) do
      -- If we have a table then we want to filter it
      if type(results) == "table" then
        -- Yield the filtered table
        coroutine.yield(vim.tbl_filter(
          function (value)
            return string.find(value, request.filter, 0, true)
          end,
          results
        ))
      -- If we don't have a table we finish by yielding nil
      else
        coroutine.yield(nil)
      end
    end
  end
end
```

### Producer + Consumer

The following combines our above `consumer` and `producer`, itself creating a new producer, and passes this to `snap` to run:

```lua
snap.run {
  producer = consumer(producer),
  select = print
}
```

From the above we have seen the following distinct concepts of `snap`:

- Producer + consumer pattern
- Yielding a lua `table` of strings
- Yielding `nil` to exit
- Using `snap.io.spawn` iterate over the data of a process
- Using `snap.sync` to run slow-mode nvim functions
- Using `snap.consume` to consume another producer
- Using the `request.filter` value
- Using the `request.canceled()` signal to kill processes


## API

### Meta Result

Results can be decorated with additional information (see `with_meta`), these results are represented by the `MetaResult` type.

```typescript
// A table that tostrings as result

type MetaResult = {
  // The result string value
  result: string;

  // A metatable __tostring implementation
  __tostring: (result: MetaResult) => string;

  // More optional properties, e.g. score
  ...
};
```

### Yieldable

Coroutines in `snap` can yield 4 different types, each with a distinct meaning outlined below.

```typescript
type Yieldable = table<string> | table<MetaResult> | function | nil;
```

#### Yielding `table<string>`

For each `table<string>` yielded (or returned as the last value of `producer`) from a `producer`, `snap` will accumulate the values of the table and display them in the results buffer.

```lua
local function producer(message)
  coroutine.yield({"Result 1", "Result 1"})
  -- the nvim UI can respond to input between these yields
  coroutine.yield({"Result 3", "Result 4"})
end
```

This `producer` function results in a table of 4 values displayed, but given there are two yields, in between these yields `nvim` has an oppurtunity to process more input.

One can see how this functionality allows for results of spawned processes to progressively yield thier results while avoiding blocking user input, and enabling the cancelation of said spawned processes.

#### Yielding `table<MetaResult>`

Results at times need to be decorated with additional information, e.g. a sort score.

`snap` makes use of tables (with an attached metatable implementing `__tostring`) to represent results with meta data.

The following shows how to add results with additional information. And because `snap` automatically sorts results with `score` meta data, the following with be ordered accordingly.

```lua
local function producer(message)
  coroutine.yield({
    snap.with_meta("Higher rank", "score", 10),
    snap.with_meta("Lower rank", "score", 1),
    snap.with_meta("Mid rank", "score", 5)
  })
end
```

#### Yielding `function`

Given that `producer` is by design run when `fast-mode` is true. One needs an ability to at times get the result of a blocking `nvim` function, such as many of `nvim` basic functions, e.g. `vim.fn.getcwd`. As such `snap` provides the ability to `yield` a function, have its execution run with `vim.schedule` and its resulting value returned.

```lua
local function producer(message)
  -- Yield a function to get its result
  local cwd = snap.sync(vim.fn.getcwd)
  -- Now we have the cwd we can do something with it
end
```

#### Yielding `nil`

Yielding nil signals to `snap` that there are not more results, and the coroutine is dead. `snap` will finish processing the `coroutine` when nil is encounted.

```lua
local function producer(message)
  coroutine.yield({"Result 1", "Result 1"})
  coroutine.yield(nil)
  -- Doesn't proces this, as coroutine is dead
  coroutine.yield({"Result 3", "Result 4"})
end
```

### Request

This is the request that is passed to a `producer`.

```typescript
type Request = {
  filter: string;
  winnr: number;
  canceled: () => boolean;
};
```

### ViewRequest

This is the request that is passed to view producers.

```typescript
type ViewRequest = {
  selection: string;
  bufnr: number;
  winnr: number;
  canceled: () => boolean;
};
```

### Producer

```typescript
type Producer = (request: Request) => yield<Yieldable>;
```

The full type of producer is actually:

```typescript
type ProducerWithDefault = {default: Producer} | Producer;
```

Because we support passing a table if it has a `default` field that is a producer. This enables producer modules to export a default producer, while also making orther related producers available, e.g. ones with additional configuration.

See: https://github.com/camspiers/snap/blob/main/fnl/snap/producer/ripgrep/file.fnl

### Consumer

```typescript
type Consumer = (producer: Producer) => Producer;
```

### ViewProducer

```typescript
type ViewProducer = (request: ViewRequest) => yield<function | nil>;
```

### `snap.run`

```typescript
{
  // Get the results to display
  producer: Producer;

  // Called on select
  select: (selection: string) => nil;

  // Optional prompt displayed to the user
  prompt?: string;

  // Optional function that enables multiselect
  multiselect?: (selections: table<string>) => nil;

  // Optional function configuring the results window
  layout?: () => {
    width: number;
    height: number;
    row: number;
    col: number;
  };

  // Optional initial filter
  initial_filter?: string;

  // Optional views
  views?: table<ViewProducer>
};
```

## Advanced API (for developers)

### `snap.meta_result`

Turns a result into a meta result.

```typescript
(result: string | MetaResult) => MetaResult
```

### `snap.with_meta`

Adds a meta field to a result.

```typescript
(result: string | MetaResult, field: string, value: any) => MetaResult
```

### `snap.has_meta`

Checks if a result has a meta field.

```typescript
(result: string | MetaResult, field: string) => boolean
```

### `snap.resume`

Resumes a passed coroutine while handling non-fast API requests.

TODO

### `snap.sync`

Yield a slow-mode function and get it's result.

```typescript
(fnc: () => T) => T
```

### `snap.consume`

Consumes a producer providing an iterator of its yielded results

```typescript
(producer: Producer, request: Request) => iterator<Yieldable>
```

### Layouts

#### `snap.layouts.centered`
#### `snap.layouts.bottom`
#### `snap.layouts.top`

### Producers

#### `snap.producer.vim.buffer`

Produces vim buffers.

#### `snap.producer.vim.oldfiles`

Produces vim oldfiles.

#### `snap.producer.luv.file`

Luv (`vim.loop`) based file producer.

```
NOTE: Requires no external dependencies.
```

#### `snap.producer.luv.directory`

Luv (`vim.loop`) based directory producer.

```
NOTE: Requires no external dependencies.
```

#### `snap.producer.ripgrep.file`

Ripgrep based file producer.

#### `snap.producer.ripgrep.vimgrep`

Ripgrep based grep producer in `vimgrep` format.

#### `snap.producer.fd.file`

Fd based file producer.

#### `snap.producer.fd.directory`

Fd based directory producer.

#### `snap.producer.git.file`

Git file producer.

### Consumers

#### `snap.consumer.cache`

General cache for producers whose values don't change in response to `request`.

#### `snap.consumer.limit`

General limit, will stop consuming a producer when a specified limit is reached.

#### `snap.consumer.fzy`

The workhorse consume for filtering producers that don't themselves filter.

NOTE: Requests `fzy`, e.g. `use_rocks 'fzy'`

#### `snap.consumer.fzy.filter`

A component piece of fzy that only filters.

#### `snap.consumer.fzy.score`

A component piece of fzy that only attaches score meta data.

#### `snap.consumer.fzy.positions`

A component piece of fzy that only attaches position meta data.

#### `snap.consumer.fzf`

Runs filtering through fzf, only supports basic positions highlighting for now.

### Selectors

#### `snap.select.file`

Opens a file in a buffer in the last used window.

```
NOTE: Provides both `select` and `multiselect`.
```

#### `snap.select.vimgrep`

If a single file is selected then simply opens the file at appropriate position.

If multiple files are selected then it adds them to the quickfix list, and opens the first.

```
NOTE: Provides both `select` and `multiselect`.
```

#### `snap.select.cwd`

Changes directory in response to selection. 

```
NOTE: Only provides `select`.
```

### Previewers

#### `snap.preview.file`

Creates a basic file previewer.

```
NOTE: Experimental, and relies on `file` program in path.
```

# Contributing

Snap is written in fennel, a language that compiles to Lua. See https://fennel-lang.org/

To install build dependencies:

```bash
make deps
```

To compile lua:

```bash
make compile
```

# Roadmap

- [x] Lua file producer
- [x] Preview system
- [x] More configurable layout system, including arbitrary windows
- [x] Configurable loading screen
- [x] FZF score/filter consumer
- [ ] More producers for vim concepts
- [ ] Lua filter consumer
- [ ] Tests

