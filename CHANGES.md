Changes
=======

## Version 1.2.0

Release: 2022-07-22
* Provides `jsErrorDecoder` value and `JSError` type to represent any erroneous result of executing a JavaScript function (issue #3)
* Minor package documentation improvements

**Upgrading from 1.1.0:** This is a minior release and there are no breaking changes. If you implemented error handling using a custom JSON decoder, you should consider switching to now-available `jsErrorDecoder`.

## Version 1.1.0

Released: 2022-07-20
* Fixes a bug representing all JS errors as `InteropError NotInstalled` (issue #5).
* Implemented a function converting `InteropError`s into a descriptive string to simplify creation of helpful error messages (issue #4).

## Version 1.0.3

First officially released version (through [discourse.elm-lang.org](https://discourse.elm-lang.org/t/elm-taskport-wrap-calls-to-javascript-functions-in-a-browser-or-node-js-as-elm-tasks/8509/5)) supporting all major browsers and Node.js.