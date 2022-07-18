elm-taskport
============

TaskPort is an Elm module allowing to call JavaScript APIs from Elm using the Task abstraction. The same repository contains the source for the Elm package, as well as the source for the JavaScript NPM companion package.

This module works in Chrome, Firefox, Safari, and Node.js.

Motivation
----------

[The Elm Architecture](https://guide.elm-lang.org/architecture/) (aka TEA) forces applications to only change state through creating effectful commands (`Cmd`), which upon completion yield a message (`Msg`), which in turn is passed into the application's `update` function to determine the changes to application state, as well as what further commands are required, if any. This paradigm makes the application state easy to reason about and prevents hard-to-find bugs.

However, there are situation when multiple effectful actions have to be carried out one after the other with some logic applied to the results in-between, but at the same time, the application state does not need to change until the sequence of actions is completed. For example, making a sequence of API calls over HTTP with some transformations applied to the intermediate results. If implemented using TEA paradigm, this would lead to unnecessarily fine-grained messages and increased complexity of the application model that needs to handle partially completed sequences of actions.

Fortunately, Elm provides a very useful [Task module](https://package.elm-lang.org/packages/elm/core/latest/Task) that allows effectful actions to be chained together, and their results transformed before being passed to the next effectful action in a pure functional way. The most notable example of this is [Http.task](https://package.elm-lang.org/packages/elm/http/latest/Http#task) function, which allows very complex yet practical interactions with HTTP-based APIs to be concisely expressed in Elm.

Of course, not every API is available over HTTP. One could imagine a mechanism to extend Elm langauge to allow any effectful action to be wrapped into a `Task` to be executed in a controlled way. Unfortunately, Elm's existing JavaScript interoperability mechanisms are limited to one-way ports system, and do not allow creation of tasks.

This module aims to solve this problem by allowing any JavaScript function to be wrapped into a `Task` and use full expresiveness of the `Task` module to chain their execution with other tasks in a way that remains TEA-compliant and type-safe.

Usage
-----

Before TaskPort can be used in Elm, it must be set up on JavaScript side. There are a few steps that need to be done.

### 1. Include TaskPort JavaScript companion package
There are two ways to go about doing this depending on what is more appropriate for your application.

For browser-based Elm applications that don't have much of HTML/JavaScript code, TaskPort can be included using a `<script>` tag.

```html
<script src="https://unpkg.com/elm-taskport@MODULE_VERSION/dist/taskport.min.js"></script>
```

Substitute the actual version of the Elm package instead of `MODULE_VERSION`. The module will check that both sides use the correct version to prevent subtle and hard-to-find bugs. Of course, developers can choose to distribute the JS file with the rest of the application. In this case, simply save it locally, add to your codebase, and modify the path above accordingly.

For browser-based applications which use a bundler like Webpack, TaskPort can be included as an NPM companion module.

```sh
npm add --save elm-taskport # or yarn add elm-taskport --save
```

This will bring all necessary TaskPort files files into `node_modules` directory.

For Node.js applications the process is similar, but you would also need to make `XMLHttpRequest` available in Node.js environment.

```sh
npm add --save elm-taskport xmlhttprequest # or yarn add elm-taskport xmlhttprequest --save
```

Once that is done, you can include and install TaskPort in your `app.js` or `app.ts` file.

```js
import TaskPort from 'elm-taskport';
```

### 2. Install TaskPort

For browser-based Elm applications add a script to your HTML file to enable TaskPort in your environment.

```html
<script>
    TaskPort.install();

    // it may be the same script block where you initialise your Elm application 
</script>
```

In order to use TaskPort in Node.js, it must be installed alongside bringing `XMLHttpRequest` into Node global scope.

```js
import XMLHttpRequest from 'xmlhttprequest';
// use the below line instead in building a CommonJS module
// const { XMLHttpRequest } = require('xmlhttprequest');

global.XMLHttpRequest = function() {
  XMLHttpRequest.call(this);
  TaskPort.install(this);
}

// initialize your Elm application by calling Elm.Module.init
```

### 3. Register JavaScript functions for the interop

Once TypePort is installed, you need to let it know what interop calls to expect and what to do when they are invoked.

```js
TaskPort.register("functionName", (args) => {
    return /* value or a Promise */
});
```

The type of `args` is determined entirely by the client Elm code, or, to be more precise, by the `argsEncoder` parameter passed to `TaskPort.call` function. Refer to [the Elm module documentation](https://package.elm-lang.org/packages/lobanov/elm-taskport/latest/) for details. This means that it is safe to deconstruct `args` as an object or a list if that is how the arguments are encoded.

The function body can do anything a regular JavaScript function can do. The TaskPort interop logic will call `Promise.resolve()` on the returned value, so the function can return either a `Promise` or a simple value. For this reason, the function can be `async` and use `await` keyword.

Note that you have to register interop functions before you call the Elm `init` if the application's `init` function returns `Cmd` using interop calls. Otherwise, you can register interop functions after you application was initialised.

### 4. Make interop calls in your Elm code

For simple no-argument calls use `TaskPort.callNoArgs`.
```elm
type Msg = GotWidgetsCount (Result String Int)

TaskPort.callNoArgs "getWidgetsCount" Json.Decode.int Json.Decode.string
    |> Task.attempt GotWidgetsCount
```

For functions that take arguments use `TaskPort.call`.

```elm
type Msg = GotWidgetName (Result String String)

TaskPort.callNoArgs "getWidgetNameByIndex" Json.Decode.string Json.Decode.string Json.Encode.int 0
    |> Task.attempt GotWidgetName
```

You can use `Task.andThen`, `Task.sequence`, and other functions to chain multiple calls.

```elm
type Msg = GotWidgets (Result String (List String))

TaskPort.callNoArgs "getWidgetsCount" Json.Decode.int Json.Decode.string
    |> Task.andThen
        (\count ->
            List.range 0 (count - 1)
                |> List.map Json.Encode.int
                |> List.map (TaskPort.call "getWidgetNameByIndex" Json.Decode.string Json.Decode.string)
                |> Task.sequence
        )
```
