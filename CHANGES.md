Changes
=======

## Version 2.0.0

Released: 2022-07-28

This release contains a few breaking API changes for TaskPort module aimed at improving developer experience and instilling emerging best practice as a default:
1. All versions of `call` function now accept the details of the call using a record to improve code readability. The only parameter that is passed outside of the record is the actual call parameter encoded into JSON for the interop call with a given `argsEncoder`.
2. All versions of `call` function now decode errors returned by JavaScript code as a `JSError` value. For non-standard error objects, there is an escape hatch of `ErrorValue` variant, which contains a JSON value as-is.
3. Variants of the `InteropError` type have changed. In the unlikely case you have built a logic to deal with the variants, it would need to be updated to use new names.

**Upgrading from 1.2.x:**
1. Change all invocations of `call` and `callNoArgs` to use record syntax and remove `errorDecoder` parameter. See package documentation for examples.
2. If you have custom JavaScript error decoder, it will no longer work, as TaskPort always decodes JS Error as a value of type `JSError`. You need to change your error handling code to use `JSError`. If your JavaScript code returns non-standard errors, use the escape hatch of `ErrorValue` variant.

Other changes:
* Added support for function namespaces allowing Elm package developer to avoid function name clashes and helping to keep JS and Elm code in sync.
* Removed embedded Elm test suite, as all the same cases are covered end-to-end.
* Added an ability to control if TaskPort will log JS and interop errors to the JS console.

## Version 1.2.1

Released: 2022-07-23
* Fixes an error in using TaskPort with Tauri ([PR #10](https://github.com/lobanov/elm-taskport/pull/10) -- thanks @miniBill)

## Version 1.2.0

Released: 2022-07-22
* Provides `jsErrorDecoder` value and `JSError` type to represent any erroneous result of executing a JavaScript function (issue #3)
* Minor package documentation improvements

**Upgrading from 1.1.0:** This is a minior release and there are no breaking changes. If you implemented error handling using a custom JSON decoder, you should consider switching to now-available `jsErrorDecoder`.

## Version 1.1.0

Released: 2022-07-20
* Fixes a bug representing all JS errors as `InteropError NotInstalled` (issue #5).
* Implemented a function converting `InteropError`s into a descriptive string to simplify creation of helpful error messages (issue #4).

## Version 1.0.3

First officially released version (through [discourse.elm-lang.org](https://discourse.elm-lang.org/t/elm-taskport-wrap-calls-to-javascript-functions-in-a-browser-or-node-js-as-elm-tasks/8509/5)) supporting all major browsers and Node.js.