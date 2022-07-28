elm-taskport
============

TaskPort is an Elm package allowing to call JavaScript APIs from Elm using the Task abstraction. The same repository contains the source for the Elm package, as well as the source for the JavaScript NPM companion package.

This package works in Chrome, Firefox, Safari, and Node.js.

If you are upgarding from a previous version, see [CHANGES](https://github.com/lobanov/elm-taskport/blob/main/CHANGES.md).

For the impatient, jump straight to [Installation](#installation) or [Usage](#usage).

If you are developing an Elm package and want to use TaskPort to call JavaScript APIs, jump to [Using TaskPort in Elm packages](#using-taskport-in-elm-packages).

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

This will bring all necessary JavaScript files files into `node_modules/elm-taskport` directory. Once that is done, you can include TaskPort in your main JavaScript or TypeScript file.

```js
import TaskPort from 'elm-taskport';
// use the following line instead of using a CommonJS target
// const TaskPort = require('elm-taskport');
```

If you are developing an Elm application in an environment that does not have `XMLHttpRequest` in the global namespace (e.g. Node.js), you would need to provide that as well, because that's required for TaskPort to work. TaskPort is tested with [xmlhttprequest](https://www.npmjs.com/package/xmlhttprequest) NPM package version 1.8.0, which is recommended.

```sh
npm add --save elm-taskport xmlhttprequest@1.8.0 # or yarn add elm-taskport xmlhttprequest@1.8.0 --save
```

### 2. Install TaskPort

For browser-based Elm applications add a script to your HTML file to enable TaskPort in your environment.

```html
<script>
    TaskPort.install(); // can pass a settings object as a parameter, see below

    // it may be the same script block where you initialise your Elm application 
</script>
```

In order to use TaskPort in an environment that does not have `XMLHttpRequest` in the global namespace (e.g. Node.js), it must be provided before Elm runtime is initialized. Note that this requires a CommonJS target and `require` directive, as Elm compiler itself cannot yet generate JS code that is compatible with ECMAScript modules.

```js
const TaskPort = require('elm-taskport');
const { XMLHttpRequest } = require('xmlhttprequest');

global.XMLHttpRequest = function() {
  XMLHttpRequest.call(this);
  TaskPort.install({}, this); // can pass a settings object as the first parameter, see below
}

// initialize your Elm application here by calling Elm.<<main module>>.init
```

Note that `XMLHttpRequest` instance is passed as the second parameter to the `install` function. This is necessary in Node.js because there is no `XMLHttpRequest` in the global context. If this parameter is omitted, TaskPort attempts to install itself to a prototype of `XMLHttpRequest` in the global namespace, which works in all browsers. 

### 3. Configure TaskPort (optional)

The first parameter of TaskPort `install` function is an object that provides additional configuration. At the moment the following properties are supported.

* `logCallErrors` (boolean, default: `false`) whether TaskPort should log errors thrown by JavaScript functions to the console.
* `logInteropErrors` (boolean, default: `true`) whether TaskPort should log errors occuring in the interop mechanism to the console.

Example use of settings parameter:

```html
<script>
    TaskPort.install({ logCallErrors: true, logInteropErrors: false });
</script>
```

### 4. Register JavaScript functions for the interop

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
-- TaskPort.Task is an alias for Task TaskPort.Error a
getWidgetsCount : TaskPort.Task Int
getWidgetsCount = TaskPort.callNoArgs 
    { function = "getWidgetsCount"
    , valueDecoder = Json.Decode.int
    }

-- TaskPort.Result is an alias for Result TaskPort.Error a
type Msg = GotWidgetsCount (TaskPort.Result Int)

Task.attempt GotWidgetsCount getWidgetsCount
```

For functions that take arguments use `TaskPort.call`.

```elm
getWidgetNameByIndex : Int -> TaskPort.Task String
getWidgetNameByIndex = TaskPort.call
    { function = "getWidgetNameByIndex"
    , valueDecoder = Json.Decode.string
    , argsEncoder = Json.Encode.int
    } -- notice currying to return a function taking Int and producing a Task

type Msg = GotWidgetName (TaskPort.Result String)

Task.attempt GotWidgetName <| getWidgetNameByIndex 0
```

You can use `Task.andThen`, `Task.sequence`, and other functions to chain multiple calls.

```elm
type Msg = GotWidgets (TaskPort.Result (List String))

getWidgetsCount
    |> Task.andThen
        (\count ->
            List.range 0 (count - 1)
                |> List.map getWidgetNameByIndex
                |> Task.sequence
        )
    |> Task.attempt GotWidgets
```

### Handling errors

Upon completion of the interop call, Elm runtime will invoke your `update` function with a message containing the result of the operation. If the task representing the interop call was not manipulated or chained with before passing it to the Elm runtime, the message will contain a [Result](https://package.elm-lang.org/packages/elm/core/latest/Result#Result), which will be one of two things:
* A `Result.Ok` with a response returned from the JS function decoded via `valueDecoder` parameter passed to the `call` (or `callNoArgs`).
* A `Result.Err` with an instance of `TaskPort.Error` representing a problem that occured whilst attempting the interop call.

You can use full machinery of the [Result module](https://package.elm-lang.org/packages/elm/core/latest/Result) to handle the result of the operation. For example, if you are not interested in the details of the error, you could convert it to a maybe using `Result.toMaybe` function.

`TaskPort.Error` is a variant data type that could be either:
* An `InteropError` with information about the failure of the interop mechanism itself. This is of errors indicating a failure of the interop mechanism itself.
* A `JSError` with a representation of the error returned from or thrown by the JavaScript code.

Interop errors are generally not recoverable, but you can use them to allow the application to fail gracefully, or at least provide useful context for debugging. The latter is aided by the helper function `TaskPort.interopErrorToString`.

TaskPort uses `JSError` type to represent an error thrown by the JavaScript code. JavaScript itself is very lenient regarding its errors. Any value could be thrown, and, if the JS code is asynchronous, the `Promise` can reject with any value. TaskPort always attempts to decode erroneous results returned from iterop calls using `ErrorObject` variant followed by `JSErrorRecord` structure, which contains standard fields for JavaScript `Error` object, but if that isn't possible, it resorts to `ErrorValue` variant followed by the JSON value as-is.

In most cases you would pass values of this type to `errorToString` to create a useful diagnostic information, but you might also have a need to handle certain types of errors in a particular way. To make that easier, `ErrorObject` variant lifts up the name of the JavaScript `Error` object to aid pattern-match for error types. You may do something like this:

```elm
case error of
    JSError (ErrorObject "VerySpecificError" _) -> -- handle a particular subtype of Error thrown by the JS code
    _ -> -- respond to the error in a generic way, e.g show a diagnostic message
```

Using TaskPort in Elm packages
------------------------------

If you are looking to use TaskPort in an Elm package which could be used by many Elm applications, you have to be mindful of the fact that currently there is no standard mechanism to bundle JavaScript code with an Elm package. This effectively means that it's the responsibility of the developer, who would be using your package in their Elm application, to obtain and deploy correct JavaScript code required for your Elm package to work. As an Elm package developer, you have no direct control over that. Your Elm package documentation should explain how to obtain and deploy the correct version of the JavaScript code similarly to how this page does it (see [Installation](#installation)). However, it is also prudent to implement a safeguard that would detect incompatibility between the JavaScript code and the Elm package and provide a helpful diagnostic message.

Another problem to watch out for is the potential for clashing names with JavaScript interop functions registered by another Elm packages and the application itself. Interop function name clashes between two Elm packages would be particularly problematic for an application developer, as they would have no control over the function names.

TaskPort provides an out-of-the-box support for Elm package developers with *function namespaces*, which is a mechanism preventing interop function name clashes, as well as a safeguard ensuring Elm and JavaScript interop code is in sync. Elm package developers should register their interop JavaScript functions in their package's namespace and provide a version number for the namespace, and TaskPort will keep registered functions separate and eagerly check if JavaScript code has the same version as the Elm package expects it to be.

The following sections explain how to use TaskPort function namespaces. You can also check out [lobanov/elm-localstorage](https://github.com/lobanov/elm-localstorage) package for an example of using this mechanism.

### Registering JavaScript interop functions in a namespace

It is recommended to create a single `install` function that would register all JavaScript interop functions required for the package to work. That function would call `TaskPort.createNamespace()` function to create a new namespace, and register interop functions required by your Elm package in it. It is further recommended that the `install` function takes the TaskPort object as a parameter rather than attempting to find it in the global namespace, because the latter won't be compatible with the Node environment.

Note that if you are using a bundler like WebPack to create a minified build of the JavaScript code for your Elm package for direct inclusion via a script tag, make sure you don't bundle TaskPort itself (in WebPack use [externals](https://webpack.js.org/configuration/externals/)). Otherwise, application developers would be unable to use another Elm package relying on TaskPort or use TaskPort in the application.

TaskPort expects function namespaces to be called after Elm package names, i.e. `author-name/package-name`, but does not enforce any versioning schema. In most cases you would want to use your Elm package version number, but if you are wrapping a third-party JavaScript API and or interop code is not changing very often, it may be sufficient to use a separate JS API version to improve developer experience of your Elm package by simplifying the upgrades.

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
import TaskPort exposing (Task, callNS, callNoArgsNS, inNamespace)

-- TaskPort.Task is an alias for Task TaskPort.Error a

getWidgetsCount : Task Int
getWidgetsCount = callNoArgsNS
    { function = "getWidgetsCount" |> inNamespace "author/elm-package" "v1"
    , bodyDecoder = Json.Decode.int,
    }

getWidgetNameByIndex : Int -> Task String
getWidgetNameByIndex = callNS
    { function = "getWidgetNameByIndex" |> inNamespace "author/elm-package" "v1"
    , bodyDecoder = Json.Decode.string,
    , argsEncoder = Json.Encode.int
    } -- notice currying here and returning a function taking Int and producing a Task

-- more useful in this case would be to chain calls together
getWidgetNames : Task (List String)
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
import TaskPort exposing (Result)

-- TaskPort.Result is an alias for Result TaskPort.Error a

type Msg = GotWidgets (Result (List String))

Task.attempt GotWidgets WidgetModules.getWidgetNames -- produces a Cmd
```

Getting support
---------------

For questions or general enquiries feel free to tag or DM `@lobanov` on [Elm Slack](https://elmlang.slack.com/).

For issues or suggestions please raise an issue on GitHub.

PRs are welcome.
