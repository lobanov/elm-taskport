module TaskPort exposing 
  ( Error(..), InteropError(..), JSError(..), JSErrorRecord
  , Namespace, Version, FunctionName, QualifiedName(..)
  , ignoreValue
  , interopErrorToString, jsErrorToString, errorToString, jsErrorDecoder
  , call, callNoArgs
  , callNS, callNoArgsNS
  , tests
  )

{-| This module allows to invoke JavaScript functions using the Elm's Task abstraction,
which is convenient for chaining multiple API calls without introducing the complexity
in the model of an Elm application.

# Setting up
Before TypePort can be used in Elm, it must be set up on JavaScript side.
Refer to the [README](https://github.com/lobanov/elm-taskport/blob/main/README.md) for comprehensive instructions.

# Usage
@docs FunctionName, call, callNoArgs, ignoreValue

# Error handling
@docs Error, JSError, JSErrorRecord, InteropError, jsErrorDecoder, interopErrorToString, jsErrorToString, errorToString

# Package development
@docs QualifiedName, Namespace, Version, callNS, callNoArgsNS

# Tests
We are exposing tests suite to help test module's implementation details.
@docs tests

-}

import Task
import Json.Encode as JE
import Json.Decode as JD
import Http
import Test exposing (..)
import Expect
import Dict

moduleVersion : String
moduleVersion = "1.2.1"


{-| Alias for `String` type representing a namespace for JavaScript interop functions.
Namespaces are typically used by Elm package developers, and passed as a paramter to `QualifiedName`.
Valid namespace string would match the following regular expression: `/^[\w-]+\/[\w-]+$/.

The following are valid namespaces: `elm/core`, `lobanov/elm-taskport`, `rtfeldman/elm-iso8601-date-strings`.
-}
type alias Namespace = String

{-| Alias for `String` type representing a version of a namespace for JavaScript interop functions.
Namespaces are typically used by Elm package developers, and passed as a parameter to `QualifiedName`.
TaskPort enforces semantic version formal MAJOR.MINOR.PATCH, but does not enforce any
semantics. Most likely, Elm package developers will use Elm package version.
-}
type alias Version = String

{-| Alias for `String` type representing a name of a JavaScript function.
Valid function names only contain alphanumeric characters.
-}
type alias FunctionName = String

{-| Represents the name of a function that may optionally be qualified with a versioned namespace.
-}
type QualifiedName = DefaultNS FunctionName | WithNS Namespace Version FunctionName

{-| A structured error describing exactly how the interop call failed. You can use
this to determine the best way to react to and recover from the problem.

CallError prefix is for errors explicitly sent from the JavaScript side. The error information
will be specific to the interop use case, and it should be reconsituted from a JSON payload.

InteropError prefix is for the failures of the interop mechanism itself.
-}
type Error x
    = InteropError InteropError
    | CallError x

{-| Subcategory of errors indicating a failure of the interop mechanism itself.
These errors are generally not receoverable, but you can use them to allow the application to fail gracefully,
or at least provide useful context for debugging, for which you can use helper function `interopErrorToString`.
-}
type InteropError
  = FunctionNotFound
  | NotInstalled
  | VersionMismatch
  | CannotDecodeResponse JD.Error String
  | CannotDecodeError JD.Error String
  | RuntimeError String

{-| In most cases instances of `InteropError` indicate a catastrophic failure in the
application environment and thus cannot be recovered from. This function allows
Elm application to fail gracefully by displaying an error message to the user,
that would help application developer to debug the issue.

It produces multiple lines of output, so you may want to peek at it with
something like this:

    import Html

    errorToHtml : TaskPort.Error -> Html.Html msg
    errorToHtml error =
      Html.pre [] [ Html.text (TaskPort.interopErrorToString error) ]
-}
interopErrorToString : InteropError -> String
interopErrorToString error =
  case error of
    FunctionNotFound -> "FunctionNotFound: attempted to call unknown function."
    NotInstalled -> "NotInstalled: TaskPort JS component is not installed."
    VersionMismatch -> "VersionMismatch: TaskPort JS component version is different from the Elm package version."
    CannotDecodeResponse err body
      -> "CannotDecodeResponse: unable to decode function response.\n"
      ++ "Response:\n" ++ body ++ "\n\n"
      ++ "Error:\n" ++ (JD.errorToString err)
    CannotDecodeError err body
      -> "CannotDecodeError: unable to decode function error.\n"
      ++ "Response:\n" ++ body ++ "\n\n"
      ++ "Error:\n" ++ (JD.errorToString err)
    RuntimeError message -> "RuntimeError: " ++ message


{-| Generic type representing all possibilities that could be returned from an interop call.
JavaScript is very lenient regarding its errors. Any value could be thrown, and, if the JS code
is asynchronous, the `Promise` can reject with any value. TaskPort always attempts to decode erroneous
results returned from iterop calls using `ErrorObject` variant and `JSErrorRecord` structure, which
contains standard fields for JavaScript `Error` object, but if itsn't possible, it will resorts to
`ErrorValue` variant followed by the JSON value as-is. 

In most cases you would pass values of this type to `jsErrorToString` to create
a useful diagnostic information, but you might also have a need to handle certain types
of errors in a particular way. To make that easier, `ErrorObject` variant lifts up the error
name to aid pattern-match for error types. You may do something like this:

    case error of
        CallError (ErrorObject "VerySpecificError" _) -> -- handle a particular subtype of Error thrown by the JS code
        _ -> -- respond to the error in a generic way, e.g show a diagnostic message
-}
type JSError = ErrorObject String JSErrorRecord | ErrorValue JE.Value

{-| Structure describing an object conforming to JavaScript standard for `Error`.
Unless you need to handle very specific failure condition in a particular way, you are unlikely
to use this type.

The structure contains the following fields:
* `name` represents the type of the `Error` object, e.g. `ReferenceError`
* `message` is a free-form string typically passed as a parameter to the error constructor
* `stackLines` is a platform-specific stack trace for the error
* `cause` optional nested error object, which is first attempted to be decoded as a `JSErrorRecord`, but
falls back to `JSError.ErrorValue` if that's impossible.
-}
type alias JSErrorRecord =
  { name : String
  , message : String
  , stackLines : List String
  , cause : Maybe JSError
  }

{-| Generates a human-readable and hopefully helpful string with diagnostic information
describing a `JSError`. It produces multiple lines of output, so you may want to peek at it with
something like this:

    import Html

    errorToHtml : TaskPort.JSError -> Html.Html msg
    errorToHtml error =
      Html.pre [] [ Html.text (TaskPort.jsErrorToString error) ]
-}
jsErrorToString : JSError -> String
jsErrorToString error =
  case error of
    ErrorValue v -> "JSON object:\n" ++ (JE.encode 4 v)
    ErrorObject name o 
      -> name ++ ": " ++ o.message ++ "\n"
      ++ (String.join "\n" o.stackLines)
      ++ Maybe.withDefault "" (Maybe.map (\cause -> "\nCaused by:\n" ++ jsErrorToString cause) o.cause)

{-| JSON decoder that constructs a `JSError` value from erroneous results returned by an interop call.
You would pass it to `TaskPort.call` or `TaskPort.callNoArgs`.
-}
jsErrorDecoder : JD.Decoder JSError
jsErrorDecoder = 
  JD.oneOf
    [ JD.map2 ErrorObject
      (JD.field "name" JD.string)
      jsErrorRecordDecoder
    , JD.map ErrorValue JD.value
    ]

jsErrorRecordDecoder : JD.Decoder JSErrorRecord
jsErrorRecordDecoder =
  JD.map4 JSErrorRecord
    (JD.field "name" JD.string)
    (JD.field "message" JD.string)
    (JD.field "stackLines" (JD.list JD.string))
    (JD.field "cause" (JD.oneOf
      [ JD.null Nothing
      , JD.map Just <| JD.lazy (\_ -> jsErrorDecoder)
      ]
    ))

{-| Convenience method for creating a user-presentable string describing an error
which occured during an interop call in case use `jsErrorDecoder` in your interop calls.
-}
errorToString : Error JSError -> String
errorToString error =
  case error of
    InteropError e -> interopErrorToString e
    CallError e -> jsErrorToString e


{-| JSON decoder that can be used with as a `bodyDecoder` parameter when calling JavaScript functions
that are not expected to return a value, or where the return value can be safely ignored.
-}
ignoreValue : JD.Decoder ()
ignoreValue = JD.succeed ()

{-| Creates a Task encapsulating an asyncronous invocation of a particular JavaScript function.
This function will usually be wrapped into a more specific one, which will partially apply it
providing the encoder and the decoders but curry the last parameter, so that it could invoked where necessary
as a `args -> Task` function.

Because interop calls can fail, produced task would likely need to be piped into a `Task.attempt` or handled further using `Task.onError`.

Here is a simple example that creates a `Cmd` invoking a registered JavaScript function called `ping`
and produces a message `GotPong` with a `Result`, containing either an `Ok` variant with a string (determined by the first decoder argument),
or an `Err`, containing a `TaskPort.Error` describing what went wrong.

    type Msg = GotWidgetName (Result String String)

    TaskPort.call "getWidgetNameByIndex" Json.Decode.string TaskPort.jsErrorDecoder Json.Encode.int 0
        |> Task.attempt GotWidgetName

The `Task` abstraction allows to effectively compose chains of tasks without creating many intermediate variants in the Msg type, and
designing the model to deal with partially completed call chain. The following example shows how this might be used
when working with a hypothetical 'chatty' JavaScript API, requiring to call `getWidgetsCount` function to obtain a number
of widgets, and then call `getWidgetName` with each widget's index to obtain its name.

    type Msg = GotWidgets (Result String (List String))
    
    TaskPort.callNoArgs "getWidgetsCount" Json.Decode.int TaskPort.jsErrorDecoder
        |> Task.andThen
            (\count ->
                List.range 0 (count - 1)
                    |> List.map Json.Encode.int
                    |> List.map (TaskPort.call "getWidgetNameByIndex" Json.Decode.string TaskPort.jsErrorDecoder)
                    |> Task.sequence
            )
        |> Task.attempt GotWidgets

The resulting task has type `Task (TaskPort.Error String) (List String)`, which could be attempted as a single command,
which, if successful, provides a handy `List String` with all widget names.

**Note that specifying any `errorDecoder` other than `TaskPort.jsErrorDecoder` is deprecated, and this paramter will be removed in future.**
-}
call : String -> (JD.Decoder body) -> (JD.Decoder error) -> (args -> JE.Value) -> args -> Task.Task (Error error) body
call functionName bodyDecoder errorDecoder argsEncoder args = callNS
  { function = DefaultNS functionName
  , bodyDecoder = bodyDecoder
  , errorDecoder = errorDecoder
  }
  (argsEncoder args)

{-| Special version of the `call` that reduces amount of boilerplate code required when calling JavaScript functions
that don't take any parameters. It is eqivalent of passing `Json.Encoder.null` into the `call`.

    type Msg = GotWidgetsCount (Result String Int)

    TaskPort.callNoArgs "getWidgetsCount" Json.Decode.int TaskPort.jsErrorDecoder
        |> Task.attempt GotWidgetsCount

**Note that specifying any `errorDecoder` other than `TaskPort.jsErrorDecoder` is deprecated, and this paramter will be removed in future.**
-}
callNoArgs : String -> (JD.Decoder body) -> (JD.Decoder error) -> Task.Task (Error error) body
callNoArgs functionName bodyDecoder errorDecoder = callNoArgsNS
  { function = DefaultNS functionName
  , bodyDecoder = bodyDecoder
  , errorDecoder = errorDecoder
  }

{-| Creates a Task encapsulating an asyncronous invocation of a particular JavaScript function.
It behaves similarly to `call`, but this function is namespace-aware and is intended to be used
by Elm package developers, who want to use TaskPort's function namespaces feature to eliminate a possibility
of name clashes of their JavaScript functions with other packages that may also be using taskports.

Unlike `call`, this function uses a record to specify the details of the interop call, which leads to more readable code.

    TaskPort.callNS
        { function = TaskPort.WithNS "elm-package/namespace" "1.0.0" "setWidgetName"
        , bodyDecoder = TaskPort.ignoreValue -- expecting no return value
        , errorDecoder = TaskPort.jsErrorDecoder
        }
        Json.Encoder.string "new name"
        |> Task.attempt WidgetNameUpdated

**Note that specifying any `errorDecoder` other than `TaskPort.jsErrorDecoder` is deprecated, and this paramter will be removed in future.**
-}
callNS : 
  { function : QualifiedName
  , bodyDecoder : JD.Decoder body
  , errorDecoder : JD.Decoder error
  }
  -> JE.Value
  -> Task.Task (Error error) body
callNS details args = Http.task <| buildHttpCall details.function details.bodyDecoder details.errorDecoder args

{-| Creates a Task encapsulating an asyncronous invocation of a particular JavaScript function without parameters.
It behaves similarly to `callNoArgs`, but this function is namespace-aware and is intended to be used
by Elm package developers, who want to use TaskPort's function namespaces feature to eliminate a possibility
of name clashes of their JavaScript functions with other packages that may also be using taskports.

Unlike `callNoArgs`, this function uses a record to specify the details of the interop call, which leads to more readable code.

    TaskPort.callNoArgsNS
        { function = TaskPort.WithNS "elm-package/namespace" "1.0.0" "getWidgetName"
        , bodyDecoder = Json.Decoder.string -- expecting a string
        , errorDecoder = TaskPort.jsErrorDecoder
        }
        |> Task.attempt GotWidgetName

**Note that specifying any `errorDecoder` other than `TaskPort.jsErrorDecoder` is deprecated, and this paramter will be removed in future.**
-}
callNoArgsNS : 
  { function : QualifiedName
  , bodyDecoder : JD.Decoder body
  , errorDecoder : JD.Decoder error
  }
  -> Task.Task (Error error) body
callNoArgsNS details = Http.task <| buildHttpCall details.function details.bodyDecoder details.errorDecoder JE.null

type alias HttpTaskArgs x a =
  { method : String
  , headers : List Http.Header
  , url : String
  , body : Http.Body
  , resolver : Http.Resolver (Error x) a
  , timeout : Maybe Float }

buildHttpCall : QualifiedName -> (JD.Decoder body) -> (JD.Decoder error) -> JE.Value -> HttpTaskArgs error body
buildHttpCall function bodyDecoder errorDecoder args =
  { method = "POST"
  , headers = []
  , url = buildCallUrl function
  , body = Http.jsonBody args
  , resolver = Http.stringResolver (resolveResponse bodyDecoder errorDecoder)
  , timeout = Nothing
  }

buildCallUrl : QualifiedName -> String
buildCallUrl function =
  case function of
    DefaultNS name -> "elmtaskport:///" ++ name ++ "?v=" ++ moduleVersion
    WithNS ns nsVersion name -> "elmtaskport://" ++ ns ++ "/" ++ name ++ "?v=" ++ moduleVersion ++ "&nsv=" ++ nsVersion

resolveResponse : JD.Decoder a -> JD.Decoder x -> Http.Response String -> Result (Error x) a
resolveResponse bodyDecoder errorDecoder res =
  case res of
    Http.BadUrl_ url -> runtimeError <| "bad url" ++ url
    Http.Timeout_ -> runtimeError "timeout"
    Http.NetworkError_ -> Result.Err (InteropError NotInstalled)
    Http.BadStatus_ {statusCode} body -> 
      if (statusCode == 400) then
        Result.Err (InteropError VersionMismatch)
      else if (statusCode == 404) then
        Result.Err (InteropError FunctionNotFound)
      else if (statusCode == 500) then
        case JD.decodeString errorDecoder body of
          Result.Ok errorValue -> Result.Err (CallError errorValue)
          Result.Err decodeError -> Result.Err (InteropError <| CannotDecodeError decodeError body)
      else
        runtimeError <| "unexpected status " ++ String.fromInt statusCode
    Http.GoodStatus_ _ body -> 
      case JD.decodeString bodyDecoder body of
        Result.Ok returnValue -> Result.Ok returnValue
        Result.Err decodeError -> Result.Err (InteropError <| CannotDecodeResponse decodeError body)

runtimeError : String -> Result (Error x) a
runtimeError msg = Result.Err <|
  InteropError <|
    RuntimeError <|
      ("Runtime error in JavaScript interop: " ++ msg ++ ". JavaScript console may contain more information about the issue.")


{-| This is an embedded tests suite allowing to test module-internal logic. No need to use this. -}
tests : Test
tests = describe "test"
  [ test "runtimeError" <|
    \_ -> case runtimeError "(error)" of
        Result.Err (InteropError (RuntimeError msg)) -> Expect.true "error should contain the message" (String.contains "(error)" msg)
        _ -> Expect.fail "Must produce an error"
  , test "buildHttpCall" <|
    \_ -> case buildHttpCall (DefaultNS "function123") JD.string JD.string (JE.string "args") of
        {method, url, timeout} -> (method, url, timeout) |> Expect.equal ( "POST", buildCallUrl (DefaultNS "function123"), Nothing )
  , describe "resolveResponse"
    [ test "good response" <|
      \_ -> let response = Http.GoodStatus_ { url = buildCallUrl (DefaultNS "fn"), statusCode = 200, statusText = "", headers = Dict.empty } "123"
            in case resolveResponse JD.int JD.int response of
              Result.Ok (value) -> value |> Expect.equal 123
              _ -> Expect.fail "unexpected outcome for good response"
    , test "exception response" <|
      \_ -> let response = Http.BadStatus_ { url = buildCallUrl (DefaultNS "fn"), statusCode = 500, statusText = "", headers = Dict.empty } "321"
            in case resolveResponse JD.int JD.int response of
              Result.Err (CallError value) -> value |> Expect.equal 321
              _ -> Expect.fail "unexpected outcome for exception response"
    , test "module version mismatch" <|
      \_ -> let response = Http.BadStatus_ { url = buildCallUrl (DefaultNS "fn"), statusCode = 400, statusText = "", headers = Dict.empty } ""
            in case resolveResponse JD.int JD.int response of
              Result.Err (InteropError VersionMismatch) -> Expect.pass
              _ -> Expect.fail "unexpected outcome for exception response"
    , test "function not found" <|
      \_ -> let response = Http.BadStatus_ { url = buildCallUrl (DefaultNS "fn"), statusCode = 404, statusText = "", headers = Dict.empty } ""
            in case resolveResponse JD.int JD.int response of
              Result.Err (InteropError FunctionNotFound) -> Expect.pass
              _ -> Expect.fail "unexpected outcome for exception response"
    , test "interop not installed" <|
      \_ -> let response = Http.NetworkError_
            in case resolveResponse JD.int JD.int response of
              Result.Err (InteropError NotInstalled) -> Expect.pass
              _ -> Expect.fail "unexpected outcome for exception response"
    ]
  ]