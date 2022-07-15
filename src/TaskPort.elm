module TaskPort exposing (Error(..), InteropError(..), call, callNoArgs, tests)

{-| This module allows to invoke JavaScript functions using the Elm's Task abstraction,
which is convenient for chaining multiple API calls without introducing the complexity
in the model of an Elm application.

# Setting up
Before TypePort can be used in Elm, it must be set up on JavaScript side.
Refer to the [README](https://github.com/lobanov/elm-taskport/blob/main/README.md) for comprehensive instructions.

# Usage
@docs call, callNoArgs, Error, InteropError

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
moduleVersion = "1.0.3"

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
or at least provide useful context for debugging.
-}
type InteropError
  = FunctionNotFound
  | NotInstalled
  | VersionMismatch
  | CannotDecodeResponse JD.Error String
  | CannotDecodeError JD.Error String
  | RuntimeError String

{-| Creates a Task encapsulating an invocation of a particular asyncronous JavaScript function.
This function will usually be wrapped into a more specific one, which will partially apply it
providing the encoder and the decoders but curry the last parameter, so that it could invoked where necessary
as a `args -> Task` function.

Because interop calls can fail, produced task would likely need to be piped into a `Task.attempt` or handled further using `Task.onError`.

Here is a simple example that creates a `Cmd` invoking a registered JavaScript function called `ping`
and produces a message `GotPong` with a `Result`, containing either an `Ok` variant with a string (determined by the first decoder argument),
or an `Err`, containing a `TaskPort.Error` describing what went wrong.

    type Msg = GotWidgetName (Result String String)

    TaskPort.call "getWidgetNameByIndex" Json.Decode.string Json.Decode.string Json.Encode.int 0
        |> Task.attempt GotWidgetName

The `Task` abstraction allows to effectively compose chains of tasks without creating many intermediate variants in the Msg type, and
designing the model to deal with partially completed call chain. The following example shows how this might be used
when working with a hypothetical 'chatty' JavaScript API, requiring to call `getWidgetsCount` function to obtain a number
of widgets, and then call `getWidgetName` with each widget's index to obtain its name.

    type Msg = GotWidgets (Result String (List String))
    
    TaskPort.callNoArgs "getWidgetsCount" Json.Decode.int Json.Decode.string
        |> Task.andThen
            (\count ->
                List.range 0 (count - 1)
                    |> List.map Json.Encode.int
                    |> List.map (TaskPort.call "getWidgetNameByIndex" Json.Decode.string Json.Decode.string)
                    |> Task.sequence
            )
        |> Task.attempt GotWidgets

The resulting task has type `Task (TaskPort.Error String) (List String)`, which could be attempted as a single command,
which, if successful, provides a handy `List String` with all widget names.
-}
call : String -> (JD.Decoder body) -> (JD.Decoder error) -> (args -> JE.Value) -> args -> Task.Task (Error error) body
call functionName bodyDecoder errorDecoder argsEncoder args = callWithJson functionName bodyDecoder errorDecoder <| argsEncoder args

{-| Special version of the `call` that reduces amount of boilerplate code required when calling JavaScript functions
that don't take any parameters. It is eqivalent of passing `Json.Encoder.null` into the `call`.

    type Msg = GotWidgetsCount (Result String Int)

    TaskPort.callNoArgs "getWidgetsCount" Json.Decode.int Json.Decode.string
        |> Task.attempt GotWidgetsCount
-}
callNoArgs : String -> (JD.Decoder body) -> (JD.Decoder error) -> Task.Task (Error error) body
callNoArgs functionName bodyDecoder errorDecoder = callWithJson functionName bodyDecoder errorDecoder JE.null

callWithJson : String -> (JD.Decoder body) -> (JD.Decoder error) -> JE.Value -> Task.Task (Error error) body
callWithJson functionName bodyDecoder errorDecoder json = Http.task <| buildHttpCall functionName bodyDecoder errorDecoder json

type alias HttpTaskArgs x a =
  { method : String
  , headers : List Http.Header
  , url : String
  , body : Http.Body
  , resolver : Http.Resolver (Error x) a
  , timeout : Maybe Float }

buildHttpCall : String -> (JD.Decoder body) -> (JD.Decoder error) -> JE.Value -> HttpTaskArgs error body
buildHttpCall functionName bodyDecoder errorDecoder args =
  { method = "POST"
  , headers = [ Http.header "Accept" "application/json" ]
  , url = buildCallUrl functionName
  , body = Http.jsonBody args
  , resolver = Http.stringResolver (resolveResponse bodyDecoder errorDecoder)
  , timeout = Nothing
  }

buildCallUrl : String -> String
buildCallUrl functionName = "elmtaskport://" ++ functionName ++ "?v=" ++ moduleVersion

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
    \_ -> case buildHttpCall "function123" JD.string JD.string (JE.string "args") of
        {method, url, timeout} -> (method, url, timeout) |> Expect.equal ( "POST", buildCallUrl "function123", Nothing )
  , describe "resolveResponse"
    [ test "good response" <|
      \_ -> let response = Http.GoodStatus_ { url = buildCallUrl "fn", statusCode = 200, statusText = "", headers = Dict.empty } "123"
            in case resolveResponse JD.int JD.int response of
              Result.Ok (value) -> value |> Expect.equal 123
              _ -> Expect.fail "unexpected outcome for good response"
    , test "exception response" <|
      \_ -> let response = Http.BadStatus_ { url = buildCallUrl "fn", statusCode = 500, statusText = "", headers = Dict.empty } "321"
            in case resolveResponse JD.int JD.int response of
              Result.Err (CallError value) -> value |> Expect.equal 321
              _ -> Expect.fail "unexpected outcome for exception response"
    , test "module version mismatch" <|
      \_ -> let response = Http.BadStatus_ { url = buildCallUrl "fn", statusCode = 400, statusText = "", headers = Dict.empty } ""
            in case resolveResponse JD.int JD.int response of
              Result.Err (InteropError VersionMismatch) -> Expect.pass
              _ -> Expect.fail "unexpected outcome for exception response"
    , test "function not found" <|
      \_ -> let response = Http.BadStatus_ { url = buildCallUrl "fn", statusCode = 404, statusText = "", headers = Dict.empty } ""
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