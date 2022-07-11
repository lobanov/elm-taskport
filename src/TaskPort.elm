module TaskPort exposing (Error(..), InteropError(..), call)

import Task
import Json.Encode as JE
import Json.Decode as JD
import Http

type Error x
    = InteropError InteropError
    | BodyDecodeError JD.Error String
    | ErrorDecodeError JD.Error String
    | CallError x

type InteropError = FunctionNotFound String | RuntimeError String

call : String -> (JD.Decoder body) -> (JD.Decoder error) -> JE.Value -> Task.Task (Error error) body
call functionName bodyDecoder errorDecoder args = Http.task
  { method = "POST"
  , headers = []
  , url = "elmtaskport://" ++ functionName
  , body = Http.jsonBody args
  , resolver = Http.stringResolver (resolveResponse bodyDecoder errorDecoder)
  , timeout = Nothing
  }

resolveResponse : (JD.Decoder a) -> (JD.Decoder x) -> Http.Response String -> Result (Error x) a
resolveResponse bodyDecoder errorDecoder res =
  case res of
    Http.BadUrl_ url -> runtimeError <| "bad url" ++ url
    Http.Timeout_ -> runtimeError "timeout"
    Http.NetworkError_ -> runtimeError "network error"
    Http.BadStatus_ {statusCode} body -> 
      if (statusCode == 500) then
        case JD.decodeString errorDecoder (Debug.log "Parsing error body" body) of
          Result.Ok errorValue -> Result.Err (CallError errorValue)
          Result.Err decodeError -> Result.Err (ErrorDecodeError decodeError body)
      else runtimeError <| "unexpected status " ++ String.fromInt statusCode
    Http.GoodStatus_ _ body -> 
      case JD.decodeString bodyDecoder (Debug.log "Parsing response body" body) of
        Result.Ok returnValue -> Result.Ok returnValue
        Result.Err decodeError -> Result.Err (BodyDecodeError decodeError body)

runtimeError : String -> Result (Error x) a
runtimeError msg = Result.Err <|
  InteropError <|
    RuntimeError <|
      ("Runtime error in JavaScript interop: " ++ msg ++ ". Check JavaScript console for more information.")
