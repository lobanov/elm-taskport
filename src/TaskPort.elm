module TaskPort exposing (Error(..), InteropError(..), call, tests)

import Task
import Json.Encode as JE
import Json.Decode as JD
import Http
import Test exposing (..)
import Expect
import Dict

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
type InteropError = FunctionNotFound String | CannotDecodeResponse JD.Error String | CannotDecodeError JD.Error String | RuntimeError String

{-| Creates a Task encapsulating an invocation of a particular asyncronous JavaScript function.
This function will usually be wrapped into a more specific one, which will provide
the details but curry the last parameter, so that it could invoked where necessary.
-}
call : String -> (JD.Decoder body) -> (JD.Decoder error) -> JE.Value -> Task.Task (Error error) body
call functionName bodyDecoder errorDecoder args = Http.task <| buildHttpCall functionName bodyDecoder errorDecoder args

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
  , url = "elmtaskport://" ++ functionName
  , body = Http.jsonBody args
  , resolver = Http.stringResolver (resolveResponse bodyDecoder errorDecoder)
  , timeout = Nothing
  }

resolveResponse : JD.Decoder a -> JD.Decoder x -> Http.Response String -> Result (Error x) a
resolveResponse bodyDecoder errorDecoder res =
  case res of
    Http.BadUrl_ url -> runtimeError <| "bad url" ++ url
    Http.Timeout_ -> runtimeError "timeout"
    Http.NetworkError_ -> runtimeError "network error"
    Http.BadStatus_ {statusCode} body -> 
      if (statusCode == 500) then
        case JD.decodeString errorDecoder (Debug.log "Parsing error body" body) of
          Result.Ok errorValue -> Result.Err (CallError errorValue)
          Result.Err decodeError -> Result.Err (InteropError <| CannotDecodeError decodeError body)
      else runtimeError <| "unexpected status " ++ String.fromInt statusCode
    Http.GoodStatus_ _ body -> 
      case JD.decodeString bodyDecoder (Debug.log "Parsing response body" body) of
        Result.Ok returnValue -> Result.Ok returnValue
        Result.Err decodeError -> Result.Err (InteropError <| CannotDecodeResponse decodeError body)

runtimeError : String -> Result (Error x) a
runtimeError msg = Result.Err <|
  InteropError <|
    RuntimeError <|
      ("Runtime error in JavaScript interop: " ++ msg ++ ". JavaScript console may contain more information about the issue.")


tests : Test
tests = describe "test"
  [ test "runtimeError" <|
    \_ -> case runtimeError "(error)" of
        Result.Err (InteropError (RuntimeError msg)) -> Expect.true "error should contain the message" (String.contains "(error)" msg)
        _ -> Expect.fail "Must produce an error"
  , test "buildHttpCall" <|
    \_ -> case buildHttpCall "function123" JD.string JD.string (JE.string "args") of
        {method, url, timeout} -> (method, url, timeout) |> Expect.equal ( "POST", "elmtaskport://function123", Nothing )
  , describe "resolveResponse"
    [ test "good response" <|
      \_ -> let response = Http.GoodStatus_ { url = "elmtaskport://function123", statusCode = 200, statusText = "", headers = Dict.empty } "123"
            in case resolveResponse JD.int JD.int response of
              Result.Ok (value) -> value |> Expect.equal 123
              _ -> Expect.fail "unexpected outcome for good response"
    , test "exception response" <|
      \_ -> let response = Http.BadStatus_ { url = "elmtaskport://function123", statusCode = 500, statusText = "", headers = Dict.empty } "321"
            in case resolveResponse JD.int JD.int response of
              Result.Err (CallError value) -> value |> Expect.equal 321
              _ -> Expect.fail "unexpected outcome for exception response"
    , test "interop failure" <|
      \_ -> let response = Http.NetworkError_
            in case resolveResponse JD.int JD.int response of
              Result.Err (InteropError (RuntimeError msg)) -> Expect.pass
              _ -> Expect.fail "unexpected outcome for exception response"
    ]
  ]