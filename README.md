elm-taskport
============

TaskPort is an Elm package allowing to call JavaScript APIs from Elm using the Task abstraction. The same repository contains the source for the Elm package, as well as the source for the JavaScript NPM companion package.

This package works in Chrome, Firefox, Safari, and Node.js.

If you are upgarding from a previous version, see [CHANGES](https://github.com/lobanov/elm-taskport/blob/main/CHANGES.md).

For the impatient, jump straight to [Installation](#installation) or [Usage](#usage).

Motivation
----------

[The Elm Architecture](https://guide.elm-lang.org/architecture/) (aka TEA) forces applications to only change state through creating effectful commands (`Cmd`), which upon completion yield a message (`Msg`), which in turn is passed into the application's `update` function to determine the changes to application state, as well as what further commands are required, if any. This paradigm makes the application state easy to reason about and prevents hard-to-find bugs.

However, there are situation when multiple effectful actions have to be carried out one after the other with some logic applied to the results in-between, but at the same time, the application state does not need to change until the sequence of actions is completed. For example, making a sequence of API calls over HTTP with some transformations applied to the intermediate results. If implemented using TEA paradigm, this would lead to unnecessarily fine-grained messages and increased complexity of the application model that needs to handle partially completed sequences of actions.

Fortunately, Elm provides a very useful [Task module](https://package.elm-lang.org/packages/elm/core/latest/Task) that allows effectful actions to be chained together, and their results transformed before being passed to the next effectful action in a pure functional way. The most notable example of this is [Http.task](https://package.elm-lang.org/packages/elm/http/latest/Http#task) function, which allows very complex yet practical interactions with HTTP-based APIs to be concisely expressed in Elm.

Of course, not every API is available over HTTP. One could imagine a mechanism to extend Elm langauge to allow any effectful action to be wrapped into a `Task` to be executed in a controlled way. Unfortunately, Elm's existing JavaScript interoperability mechanisms are limited to one-way ports system, and do not allow creation of tasks.

This package aims to solve this problem by allowing any JavaScript function to be wrapped into a `Task` and use full expresiveness of the `Task` module to chain their execution with other tasks in a way that remains TEA-compliant and type-safe.

Installation
------------

Note that these instructions apply to Elm application development. If you are authoring an Elm package that would be used in many applications, the approach is different. In such case, jump to section [Using TaskPort in Elm packages](#using-taskport-in-elm-packages)

Before TaskPort can be used in Elm, it must be set up on the JavaScript side. There are a few steps that need to be done.

### 1. Include JavaScript companion code
There are two ways to go about doing this depending on what is more appropriate for your application.

For browser-based Elm applications that don't have much of HTML/JavaScript code, TaskPort can be included using a `<script>` tag.

```html
<script src="https://unpkg.com/elm-taskport@ELM_PACKAGE_VERSION/dist/taskport.min.js"></script>
```

Substitute the actual version of the TaskPort package instead of `ELM_PACKAGE_VERSION`. The code is checking that Elm and JS are on the same version to prevent things blowing up. If dependency on [unpkg CDN](https://unpkg.com) makes your nervous, you can choose to distribute the JS file with the rest of your application. In this case, simply save it locally, add to your codebase, and modify the path in the `<script>` tag accordingly.

For browser-based applications which use a bundler like Webpack, TaskPort JavaScript code can be downloaded as an NPM package.

```sh
npm add --save elm-taskport # or yarn add elm-taskport --save
```

This will bring all necessary JavaScript files files into `node_modules/elm-taskport` directory.

If you are developing an Elm application in an environment that does not have `XMLHttpRequest` in the global namespace (e.g. Node.js), you would need to provide that as well, because that's required for TaskPort to work. TaskPort is tested with [xmlhttprequest](https://www.npmjs.com/package/xmlhttprequest) NPM package version 1.8.0, which is recommended.

```sh
npm add --save xmlhttprequest@1.8.0 # or yarn add xmlhttprequest@1.8.0 --save
```

Once that is done, you can include TaskPort in your main JavaScript or TypeScript file.

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

In order to use TaskPort in an environment that does not have `XMLHttpRequest` in the global namespace (e.g. Node.js), it must be provided before Elm runtime is initialized.

```js
import XMLHttpRequest from 'xmlhttprequest';
// use the below line instead if building a CommonJS module
// const { XMLHttpRequest } = require('xmlhttprequest');

global.XMLHttpRequest = function() {
  XMLHttpRequest.call(this);
  TaskPort.install(this);
}

// initialize your Elm application by calling Elm.<<main module>>.init
```

### 3. Register JavaScript functions for the interop

Once TypePort is installed, you need to let it know what interop calls to expect and what to do when they are invoked.

```js
TaskPort.register("functionName", (args) => {
    return /* value or a Promise */
});
```

The type of `args` is determined entirely by the client Elm code, or, to be more precise, by the `argsEncoder` parameter passed to `TaskPort.call` function. Refer to [the Elm package documentation](https://package.elm-lang.org/packages/lobanov/elm-taskport/latest/) for details. This means that it is safe to deconstruct `args` as an object or a list if that is how the arguments are encoded.

The function body can do anything a regular JavaScript function can do. The TaskPort interop logic will call `Promise.resolve()` on the returned value, so the function can return either a `Promise` or a simple value. For this reason, the function can be `async` and use `await` keyword.

Note that you have to register interop functions before you call the Elm `init` if the application's `init` function returns `Cmd` using interop calls. Otherwise, you can register interop functions after you application was initialised.

Usage
-----

TaskPort wraps each call of JavaScript functions into a [Task](https://package.elm-lang.org/packages/elm/core/latest/Task#Task), which is Elm's abstraction for an effectful operation, and which allows them to be chained together to achieve complex side effects, such as making multiple API calls, or interacting with the runtime environment.

`Task` itself only represent a potential operation. In order for it to be executed, it needs to be converted to a command (instance of [Cmd](https://package.elm-lang.org/packages/elm/core/latest/Platform-Cmd#Cmd)) and given to the Elm runtime. In most cases you would pass the task representing the JS interop call into [Task.attempt](https://package.elm-lang.org/packages/elm/core/latest/Task#attempt) function to turn it into a `Cmd`. You would normally do this in your application's `update` or `init` function. See [the Elm Architecture](https://guide.elm-lang.org/architecture/) to learn more about these functions and the application lifecycle.

### Basic usage

For simple no-argument calls use `TaskPort.callNoArgs`.
```elm
type Msg = GotWidgetsCount (Result (TaskPort.Error TaskPort.JSError) Int)

TaskPort.callNoArgs "getWidgetsCount" Json.Decode.int TaskPort.jsErrorDecoder
    |> Task.attempt GotWidgetsCount
```

For functions that take arguments use `TaskPort.call`.

```elm
type Msg = GotWidgetName (Result (TaskPort.Error TaskPort.JSError) String)

TaskPort.callNoArgs "getWidgetNameByIndex" Json.Decode.string TaskPort.jsErrorDecoder Json.Encode.int 0
    |> Task.attempt GotWidgetName
```

You can use `Task.andThen`, `Task.sequence`, and other functions to chain multiple calls.

```elm
type Msg = GotWidgets (Result (TaskPort.Error TaskPort.JSError) (List String))

TaskPort.callNoArgs "getWidgetsCount" Json.Decode.int TaskPort.jsErrorDecoder
    |> Task.andThen
        (\count ->
            List.range 0 (count - 1)
                |> List.map Json.Encode.int
                |> List.map (TaskPort.call "getWidgetNameByIndex" Json.Decode.string TaskPort.jsErrorDecoder)
                |> Task.sequence
        )
    |> Task.attempt GotWidgets
```

### Handling errors

Upon completion of the interop call, Elm runtime will invoke your `update` function with a message containing the result of the operation. If the task representing the interop call was not manipulated or chained with before passing it to the Elm runtime, the message will contain a [Result](https://package.elm-lang.org/packages/elm/core/latest/Result#Result), which will be one of two things:
* A `Result.Ok` with a response returned from the JS function decoded via `bodyDecoder` argument  passed to the `call` (or `callNoArgs`).
* A `Result.Err` with an instance of `TaskPort.Error` representing an error returned from or thrown by the JS function.

You can use full machinery of the [Result module](https://package.elm-lang.org/packages/elm/core/latest/Result) to handle the result of the operation. For example, if you are not interested in the details of the error, you could convert it to a maybe using `Result.toMaybe` function.

`TaskPort.Error` is a variant data type that could be either:
* A `TaskPort.InteropError` with information about the failure of the interop mechanism itself. This is of errors indicating a failure of the interop mechanism itself.
* A `TaskPort.CallError` with a representation of the error returned from or thrown by the JS code. The value contained in this variant is decoded via `errorDecoder` argument passed to the `call` (or `callNoArgs`).

Interop errors are generally not recoverable, but you can use them to allow the application to fail gracefully, or at least provide useful context for debugging. The latter is aided by the helper function `TaskPort.interopErrorToString`.

TaskPort provides `TaskPort.jsErrorDecoder` value, which is a JSON decoder for errors that may be returned from JS interop calls. It models various error types, so it's likely you would never need to implement your own decoder. If you specify it as a parameter for `TaskPort.call` or `TaskPort.callNoArgs`, you would get `TaskPort.JSError` value in case of a failure, which you can explore and interact with using a variety of helper methods. See the documentation for `TaskPort.JSError` for more information. **Specifying any `errorDecoder` other than `TaskPort.jsErrorDecoder` is deprecated, and this paramter will be removed in future.**

Using TaskPort in Elm packages
------------------------------

If you are looking to use TaskPort in an Elm package which could be used by many Elm applications, you have to be mindful of the fact that currently there is no standard mechanism to bundle JavaScript code with an Elm package. This effectively means that it's the responsibility of the developer, who would be using your package in their Elm application, to obtain and deploy correct JavaScript code required for your Elm package to work. As an Elm package developer, you have no direct control over that. Your Elm package documentation should explain how to obtain and deploy the correct version of the JavaScript code similarly to how this page does it (see [Installation](#installation)). However, it is also prudent to implement a safeguard that would detect incompatibility between the JavaScript code and the Elm package and provide a helpful diagnostic message.

Another problem to watch out for is the potential for clashing names with JavaScript interop functions registered by another Elm packages and the application itself. Interop function name clashes between two Elm packages would be particularly problematic for an application developer, as they would have no control over the function names.

TaskPort provides an out-of-the-box support for Elm package developers with *function namespaces*, which is a mechanism preventing interop function name clashes, as well as a safeguard ensuring Elm and JavaScript interop code is in sync. Elm package developers should register their interop JavaScript functions in their package's namespace and provide a version number for the namespace, and TaskPort will keep registered functions separate and eagerly check if JavaScript code has the same version as the Elm package expects it to be.

The following sections explain how to use TaskPort function namespaces. You can also check out [lobanov/elm-localstorage](https://github.com/lobanov/elm-localstorage) package for an example of using this mechanism.

### Registering JavaScript interop functions in a namespace

It is recommended to create a single `install` function that would register all JavaScript interop functions required for the package to work. That function would call `TaskPort.createNamespace()` function to create a new namespace, and register interop functions required by your Elm package in it.

TaskPort expects function namespaces to be called after Elm package names, but does not enforce any versioning schema. In most cases you would want to use your Elm package version number, but if you are wrapping a third-party JavaScript API, it may be sufficient to just use the API version.

```js
export function install(TaskPort) {
    const ns = TaskPort.createNamespace("author/elm-package", "v1");
    // TaskPort will refer to this function using it's fully qualified name author/elm-package/functionName
    ns.register("functionName", function(args) => { /* function body */ });
}
```

### Calling namespaced interop functions from Elm

Instead of using `call` or `callNoArgs` functions directly, Elm packages should use namespace-aware versions of those functions: `callNS` and `callNoArgsNS` respectively. Note that Elm packages are unlikely need to go beyond creating a `Task` for the interop call (potentially chained with other tasks with `Task.andThen`) and returning them to the application code.

```elm
import Task exposing (Task)
import TaskPort exposing (Error, JSError, callNS, callNoArgsNS, inNamespace)

getWidgetsCount : Task (Error JSError) Int
getWidgetsCount = callNoArgsNS
    { function = "getWidgetsCount" |> inNamespace "author/elm-package" "v1"
    , bodyDecoder = Json.Decode.int,
    , errorDecoder = TaskPort.jsErrorDecoder
    }

getWidgetNameByIndex : Int -> Task (Error JSError) String
getWidgetNameByIndex widgetIndex = callNS
    { function = "getWidgetNameByIndex" |> inNamespace "author/elm-package" "v1"
    , bodyDecoder = Json.Decode.string,
    , errorDecoder = TaskPort.jsErrorDecoder,
    , argsEncoder = Json.Encode.int
    }
    widgetIndex

-- more useful in this case would be to chain calls together
getWidgetNames : Task (Error JSError) (List String)
getWidgetNames = getWidgetsCount
    |> andThen
        (\count ->
            List.range 0 (count - 1)
                |> List.map getWidgetNameByIndex
                |> Task.sequence
        )
```

Elm application developer using a package providing this hypothetical API would merely need to pass a `Task` created by one of these functions into `Task.attempt` without knowing the details of the underlying JavaScript API.

```elm
import WidgetModules -- Elm package exposing the above functions
import TaskPort exposing (Error, JSError)

type Msg = GotWidgets (Result (Error JSError) (List String))

Task.attempt GotWidgets WidgetModules.getWidgetNames -- produces a Cmd
```
