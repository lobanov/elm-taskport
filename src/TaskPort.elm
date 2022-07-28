module TaskPort exposing 
  ( Error(..), InteropError(..), JSError(..), JSErrorRecord, Result, Task
  , Namespace, Version, FunctionName, QualifiedName, inNamespace, noNamespace
  , ignoreValue
  , interopErrorToString, errorToString
  , call, callNoArgs
  , callNS, callNoArgsNS
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
@docs Error, Result, Task, JSError, JSErrorRecord, InteropError, interopErrorToString, errorToString

# Package development
Make sure you read section on package development in the README.

@docs QualifiedName, Namespace, Version, noNamespace, inNamespace, callNS, callNoArgsNS

-}

import Task
import Json.Encode as JE
import Json.Decode as JD
import Http

moduleVersion : String
moduleVersion = "2.0.0"

{-| Alias for `String` type representing a namespace for JavaScript interop functions.
Namespaces are typically used by Elm package developers, and passed as a paramter to `QualifiedName`.
Valid namespace string would match the following regular expression: `/^[\w-]+\/[\w-]+$/.

The following are valid namespaces: `elm/core`, `lobanov/elm-taskport`, `rtfeldman/elm-iso8601-date-strings`.
-}
type alias Namespace = String

{-| Alias for `String` type representing a version of a namespace for JavaScript interop functions.
Namespaces are typically used by Elm package developers, and passed as a parameter to `QualifiedName`.
TaskPort does not enforce any versioning scheme and allows any combination of alphanumeric characters, dots, and dashes.
Most likely, Elm package developers will use Elm package version.
-}
type alias Version = String

{-| Alias for `String` type representing a name of a JavaScript function.
Valid function names only contain alphanumeric characters.
-}
type alias FunctionName = String

{-| Represents the name of a function that may optionally be qualified with a versioned namespace.
-}
type QualifiedName = DefaultNS FunctionName | WithNS Namespace Version FunctionName

{-| Constructs a `QualifiedName` for a function in a particular versioned namespace.

    "functionName" |> inNamespace "author/package" "version" -- infix notation reads better...
    inNamespace "author/package" "version" "functionName" -- ... but this also works
-}
inNamespace : Namespace -> Version -> FunctionName -> QualifiedName
inNamespace ns v fn = WithNS ns v fn

{-| Constructs a `QualifiedName` for a function in the default namespace.
It's better to use non-namespace-aware `call` or `callNoArgs` function, but
it's provided for completeness.
-}
noNamespace : FunctionName -> QualifiedName
noNamespace fn = DefaultNS fn

{-| A structured error describing exactly how the interop call failed. You can use
this to determine the best way to react to and recover from the problem.

`JSError` variant is for errors explicitly sent from the JavaScript side. The error information
will be specific to the interop use case, and it should be reconsituted from a JSON payload.

`InteropError` variant is for the failures of the interop mechanism itself.
-}
type Error
    = InteropError InteropError
    | JSError JSError

{-| Convenience alias for a `Result` obtained from passing a `Task` created by one of
the variants of the `TaskPort.call` function to `Task.attempt'. Application code may be simplified,
because TaskPort always uses `TaskPort.Error` for `Result.Err`.

    type Msg = GotResult TaskPort.Result String

    Task.attempt GotResult TaskPort.call { {- ... call details ... -} } args

Writing `TaskPort.Result value` is equivalent to writing `Result TaskPort.Error value`.
-}
type alias Result value = Result.Result Error value

{-| Convenience alias for a `Task`created by one of the variants of the `TaskPort.call` function.
Application code may be simplified, because TaskPort always uses `TaskPort.Error` for the error parameter of the Tasks it creates.

    callJSFunction : String -> TaskPort.Task String
    callJSFunction arg = TaskPort.call { {- ... call details ... -} } arg

Writing `TaskPort.Task value` is equivalent to writing `Task TaskPort.Error value`.
-}
type alias Task value = Task.Task Error value

{-| Subcategory of errors indicating a failure of the interop mechanism itself.
These errors are generally not receoverable, but you can use them to allow the application to fail gracefully,
or at least provide useful context for debugging, for which you can use helper function `interopErrorToString`.

Interop calls can fail for various reasons:
* `NotInstalled`: JavaScript companion code responsible for TaskPort operations is missing or not working correctly,
which means that no further interop calls can succeed.
* `NotFound`: TaskPort was unable to find a registered function name, which means that no further calls to that function can succeed.
String value will contain the function name.
* `NotCompatible`: JavaScript and Elm code are not compatible. String value will contain the function name.
* `CannotDecodeValue`: value returned by the JavaScript function cannot be decoded with a given JSON decoder.
String value will contain the returned value verbatim, and `Json.Decode.Error` will contain the error details.
* `RuntimeError`: some other unexpected failure of the interop mechanism. String value will contain further details of the error.
-}
type InteropError
  = NotInstalled
  | NotFound String
  | NotCompatible String
  | CannotDecodeValue JD.Error String
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
    NotInstalled -> "NotInstalled: TaskPort JS component is not installed."
    NotFound msg -> "NotFound: " ++ msg
    NotCompatible msg -> "NotCompatible: " ++ msg
    CannotDecodeValue err value
      -> "CannotDecodeValue: unable to decode JavaScript function return value.\n"
      ++ "Value:\n" ++ value ++ "\n\n"
      ++ "Decoding error:\n" ++ (JD.errorToString err)
    RuntimeError msg -> "RuntimeError: " ++ msg

{-| Generic type representing all possibilities that could be returned from an interop call.
JavaScript is very lenient regarding its errors. Any value could be thrown, and, if the JS code
is asynchronous, the `Promise` can reject with any value. TaskPort always attempts to decode erroneous
results returned from iterop calls using `ErrorObject` variant followed by `JSErrorRecord` structure, which
contains standard fields for JavaScript `Error` object, but if that isn't possible, it resorts to
`ErrorValue` variant followed by the JSON value as-is.

In most cases you would pass values of this type to `errorToString` to create
a useful diagnostic information, but you might also have a need to handle certain types
of errors in a particular way. To make that easier, `ErrorObject` variant lifts up the error
name to aid pattern-match for error types. You may do something like this:

    case error of
        JSError (ErrorObject "VerySpecificError" _) -> -- handle a particular subtype of Error thrown by the JS code
        _ -> -- respond to the error in a generic way, e.g show a diagnostic message
-}
type JSError = ErrorObject String JSErrorRecord | ErrorValue JE.Value

{-| Structure describing an object conforming to JavaScript standard for the `Error` object.
Unless you need to handle very specific failure condition in a particular way, you are unlikely
to use this type directly.

The structure contains the following fields:
* `name` represents the type of the `Error` object, e.g. `ReferenceError`
* `message` is a free-form and potentially empty string typically passed as a parameter to the error constructor
* `stackLines` is a platform-specific stack trace for the error
* `cause` is an optional nested error object, which is first attempted to be decoded as a `JSErrorRecord`, but
falls back to `JSError.ErrorValue` if that's not possible.
-}
type alias JSErrorRecord =
  { name : String
  , message : String
  , stackLines : List String
  , cause : Maybe JSError
  }

jsErrorToString : JSError -> String
jsErrorToString error =
  case error of
    ErrorValue v -> "JSON object:\n" ++ (JE.encode 4 v)
    ErrorObject name o 
      -> name ++ ": " ++ o.message ++ "\n"
      ++ (String.join "\n" o.stackLines)
      ++ Maybe.withDefault "" (Maybe.map (\cause -> "\nCaused by:\n" ++ jsErrorToString cause) o.cause)

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

{-| Generates a human-readable and hopefully helpful string with diagnostic information
describing an error. It produces multiple lines of output, so you may want to peek at it with
something like this:

    import Html

    errorToHtml : TaskPort.JSError -> Html.Html msg
    errorToHtml error =
      Html.pre [] [ Html.text (TaskPort.jsErrorToString error) ]
-}
errorToString : Error -> String
errorToString error =
  case error of
    InteropError e -> interopErrorToString e
    JSError e -> jsErrorToString e

{-| JSON decoder that can be used with as a `valueDecoder` parameter when calling JavaScript functions
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

    type Msg = GotWidgetName (TaskPort.Result String)

    TaskPort.call
        { function = "getWidgetNameByIndex"
        , valueDecoder = Json.Decode.string
        , argsEncoder = Json.Encode.int
        }
        0
            |> Task.attempt GotWidgetName

The `Task` abstraction allows to effectively compose chains of tasks without creating many intermediate variants in the Msg type, and
designing the model to deal with partially completed call chain. The following example shows how this might be used
when working with a hypothetical 'chatty' JavaScript API, requiring to call `getWidgetsCount` function to obtain a number
of widgets, and then call `getWidgetName` with each widget's index to obtain its name.

    type Msg = GotWidgets (Result (List String))
    
    getWidgetsCount : TaskPort.Task Int
    getWidgetsCount = TaskPort.callNoArgs 
        { function = "getWidgetsCount"
        , valueDecoder = Json.Decode.int
        }

    getWidgetNameByIndex : Int -> TaskPort.Task String
    getWidgetNameByIndex = TaskPort.call
        { function = "getWidgetNameByIndex"
        , valueDecoder = Json.Decode.string
        , argsEncoder = Json.Encode.int
        } -- notice currying to return a function taking Int and producing a Task

    getWidgetsCount
        |> Task.andThen
            (\count ->
                List.range 0 (count - 1)
                    |> List.map getWidgetNameByIndex
                    |> Task.sequence
            )
        |> Task.attempt GotWidgets

The resulting task has type `TaskPort.Task (List String)`, which could be attempted as a single command,
which, if successful, provides a handy `List String` with all widget names.
-}
call :
  { function : FunctionName
  , valueDecoder : JD.Decoder value
  , argsEncoder : (args -> JE.Value)
  }
  -> args
  -> Task value
call details args = 
  callNS
    { function = DefaultNS details.function
    , valueDecoder = details.valueDecoder
    , argsEncoder = details.argsEncoder
    }
    args

{-| Special version of the `call` that reduces amount of boilerplate code required when calling JavaScript functions
that don't take any parameters.

    type Msg = GotWidgetsCount (TaskPort.Result Int)

    TaskPort.callNoArgs
        { function = "getWidgetsCount"
        , valueDecoder = Json.Decode.int
        }
          |> Task.attempt GotWidgetsCount
-}
callNoArgs :
  { function : FunctionName
  , valueDecoder : JD.Decoder value
  }
  -> Task value
callNoArgs details = 
  callNoArgsNS
    { function = DefaultNS details.function
    , valueDecoder = details.valueDecoder
    }

{-| Creates a Task encapsulating an asyncronous invocation of a particular JavaScript function.
It behaves similarly to `call`, but this function is namespace-aware and is intended to be used
by Elm package developers, who want to use TaskPort's function namespaces feature to eliminate a possibility
of name clashes of their JavaScript functions with other packages that may also be using taskports.

Unlike `call`, this function uses a record to specify the details of the interop call, which leads to more readable code.

    TaskPort.callNS
        { function = TaskPort.WithNS "elm-package/namespace" "1.0.0" "setWidgetName"
        , valueDecoder = TaskPort.ignoreValue -- expecting no return value
        , argsEncoder = Json.Encoder.string
        }
        "new name"
            |> Task.attempt WidgetNameUpdated
-}
callNS : 
  { function : QualifiedName
  , valueDecoder : JD.Decoder value
  , argsEncoder : (args -> JE.Value)
  }
  -> args
  -> Task value
callNS details args = Http.task <| buildHttpCall details.function details.valueDecoder <| details.argsEncoder args

{-| Creates a Task encapsulating an asyncronous invocation of a particular JavaScript function without parameters.
It behaves similarly to `callNoArgs`, but this function is namespace-aware and is intended to be used
by Elm package developers, who want to use TaskPort's function namespaces feature to eliminate a possibility
of name clashes of their JavaScript functions with other packages that may also be using taskports.

Unlike `callNoArgs`, this function uses a record to specify the details of the interop call, which leads to more readable code.

    TaskPort.callNoArgsNS
        { function = TaskPort.WithNS "elm-package/namespace" "1.0.0" "getWidgetName"
        , valueDecoder = Json.Decoder.string -- expecting a string
        }
            |> Task.attempt GotWidgetName
-}
callNoArgsNS : 
  { function : QualifiedName
  , valueDecoder : JD.Decoder value
  }
  -> Task value
callNoArgsNS details = Http.task <| buildHttpCall details.function details.valueDecoder JE.null

type alias HttpTaskArgs a =
  { method : String
  , headers : List Http.Header
  , url : String
  , body : Http.Body
  , resolver : Http.Resolver Error a
  , timeout : Maybe Float }

buildHttpCall : QualifiedName -> (JD.Decoder value) -> JE.Value -> HttpTaskArgs value
buildHttpCall function valueDecoder args =
  { method = "POST"
  , headers = []
  , url = buildCallUrl function
  , body = Http.jsonBody args
  , resolver = Http.stringResolver (resolveResponse valueDecoder)
  , timeout = Nothing
  }

buildCallUrl : QualifiedName -> String
buildCallUrl function =
  case function of
    DefaultNS name -> "elmtaskport:///" ++ name ++ "?v=" ++ moduleVersion
    WithNS ns nsVersion name -> "elmtaskport://" ++ ns ++ "/" ++ name ++ "?v=" ++ moduleVersion ++ "&nsv=" ++ nsVersion

resolveResponse : JD.Decoder a -> Http.Response String -> Result a
resolveResponse valueDecoder res =
  case res of
    Http.BadUrl_ url -> runtimeError <| "bad url " ++ url
    Http.Timeout_ -> runtimeError "timeout"
    Http.NetworkError_ -> Result.Err (InteropError NotInstalled)
    Http.BadStatus_ {statusCode} body -> 
      if (statusCode == 400) then
        Result.Err (InteropError (NotCompatible body))
      else if (statusCode == 404) then
        Result.Err (InteropError (NotFound body))
      else if (statusCode == 500) then
        case JD.decodeString jsErrorDecoder body of
          Result.Ok errorValue -> Result.Err (JSError errorValue)
          Result.Err decodeError -> Result.Err (InteropError <| RuntimeError <| JD.errorToString decodeError)
      else
        runtimeError <| "unexpected status " ++ String.fromInt statusCode
    Http.GoodStatus_ _ body -> 
      case JD.decodeString valueDecoder body of
        Result.Ok returnValue -> Result.Ok returnValue
        Result.Err decodeError -> Result.Err (InteropError <| CannotDecodeValue decodeError body)

runtimeError : String -> Result a
runtimeError msg = 
  Result.Err <|
    InteropError <|
      RuntimeError <|
        ("Runtime error in JavaScript interop: " ++ msg ++ ". JavaScript console may contain more information about the issue.")
